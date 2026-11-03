/*
  IC ECG — firmware v3 (ESP32-S3 + AD8232 + display ST7789) com Bluetooth Low Energy

  Diferença para a v2.3: não usa Wi-Fi nem servidor. O ESP só adquire o sinal a 100 Hz e envia
  cada amostra para o app IC ECG pelo BLE, em tempo real. Filtro, detecção de picos e classificação
  rodam no celular. O display continua mostrando o traçado e o BPM aproximado.

  Protocolo BLE (o app procura o serviço abaixo ou o nome "IC-ECG-xxxx"):
    Serviço       a3c87500-8ed3-4bdf-8a39-a01bebede295
    ECG  (notify) a3c87501-8ed3-4bdf-8a39-a01bebede295
         22 bytes a cada 100 ms, little-endian: uint16 seq (contador de pacotes) + 10 x uint16 ADC (0..4095)
    STATUS (read/notify) a3c87502-8ed3-4bdf-8a39-a01bebede295
         4 bytes: flags (bit0 = eletrodo solto), fs em Hz, versão do firmware, amostras por pacote
  O app pede MTU 247 ao conectar (o pacote de 22 bytes não cabe no MTU padrão de 23).

  Placa: "ESP32S3 Dev Module" na IDE do Arduino (core esp32 3.x). Biblioteca: Adafruit ST7735 and ST7789.
*/
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <SPI.h>
#include <Adafruit_GFX.h>
#include <Adafruit_ST7789.h>

#define FIRMWARE_VERSAO 3

// ---------- ECG ----------
#define ECG_PIN 1          // GPIO1 = ADC1_CH0 (ok no ESP32-S3)
// Saídas LO+ e LO- do AD8232 (eletrodo solto). Na v2.3 estavam em 25 e 26, que NÃO existem no
// ESP32-S3 — por isso a detecção nunca funcionava. Coloque aqui os GPIOs onde os fios realmente estão
// (ex.: 4 e 5). Com -1 a detecção fica desligada e o app usa só a qualidade do sinal.
#define LO_PLUS  -1
#define LO_MINUS -1
#define FS 100
#define AMOSTRAS_POR_PACOTE 10
const uint32_t TS_US = 1000000UL / FS;

// ---------- BLE ----------
#define UUID_SERVICO "a3c87500-8ed3-4bdf-8a39-a01bebede295"
#define UUID_ECG     "a3c87501-8ed3-4bdf-8a39-a01bebede295"
#define UUID_STATUS  "a3c87502-8ed3-4bdf-8a39-a01bebede295"

BLEServer *servidor = nullptr;
BLECharacteristic *chEcg = nullptr;
BLECharacteristic *chStatus = nullptr;
volatile bool conectado = false;
bool estavaConectado = false;

uint16_t pacote[1 + AMOSTRAS_POR_PACOTE];  // [seq, amostras...]
uint8_t nPacote = 0;
uint16_t seq = 0;

// ---------- Display ----------
#define TFT_CS   10
#define TFT_DC    9
#define TFT_RST   8
#define TFT_MOSI 11
#define TFT_SCK  12
SPIClass spi = SPIClass(FSPI);
Adafruit_ST7789 tft = Adafruit_ST7789(&spi, TFT_CS, TFT_DC, TFT_RST);
#define GRAPH_TOP    40
#define GRAPH_BOTTOM 200
#define GRAPH_LEFT   10
#define GRAPH_RIGHT  310
int lastX = GRAPH_LEFT, lastY = (GRAPH_TOP + GRAPH_BOTTOM) / 2;

// ---------- BPM aproximado (só para o display; o valor oficial é calculado no app) ----------
long idx = 0;
long lastPeakIndex = -1000;
float bpmLocal = 0;
#define RR_MIN_SAMPLES 30

void detectarBPM(float v, long i) {
  static float prev = 0, media = 1.5;
  media = 0.99 * media + 0.01 * v;
  if (v > media + 0.2 && v > prev && i - lastPeakIndex > RR_MIN_SAMPLES) {
    if (lastPeakIndex > 0) bpmLocal = 60.0 * FS / (i - lastPeakIndex);
    lastPeakIndex = i;
  }
  prev = v;
}

bool eletrodoSolto() {
  if (LO_PLUS < 0 || LO_MINUS < 0) return false;
  return digitalRead(LO_PLUS) || digitalRead(LO_MINUS);
}

class Callbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *s) override { conectado = true; }
  void onDisconnect(BLEServer *s) override { conectado = false; }
};

void enviarStatus(bool solto) {
  uint8_t st[4] = {(uint8_t)(solto ? 1 : 0), FS, FIRMWARE_VERSAO, AMOSTRAS_POR_PACOTE};
  chStatus->setValue(st, sizeof(st));
  if (conectado) chStatus->notify();
}

// ---------- Display ----------
void corrigirEspelhamento(uint8_t madctl) {
  tft.startWrite(); tft.writeCommand(ST77XX_MADCTL); tft.spiWrite(madctl); tft.endWrite();
}

void desenharGrade() {
  tft.fillRect(0, GRAPH_TOP, 320, GRAPH_BOTTOM - GRAPH_TOP + 1, ST77XX_BLACK);
  tft.drawRect(GRAPH_LEFT, GRAPH_TOP, GRAPH_RIGHT - GRAPH_LEFT, GRAPH_BOTTOM - GRAPH_TOP, ST77XX_WHITE);
  lastX = GRAPH_LEFT;
}

void desenharCabecalho() {
  tft.fillRect(0, 0, 320, 36, ST77XX_BLACK);
  tft.setTextSize(2); tft.setTextColor(ST77XX_WHITE); tft.setCursor(10, 10); tft.print("IC ECG");
  tft.setTextSize(1); tft.setCursor(170, 14);
  if (conectado) { tft.setTextColor(ST77XX_GREEN); tft.print("BLE conectado"); }
  else { tft.setTextColor(ST77XX_YELLOW); tft.print("BLE aguardando app"); }
}

void desenharRodape(bool solto) {
  tft.fillRect(0, 205, 320, 35, ST77XX_BLACK);
  tft.setTextSize(2); tft.setCursor(10, 212);
  if (solto) { tft.setTextColor(ST77XX_RED); tft.print("ELETRODO SOLTO"); return; }
  tft.setTextColor(ST77XX_CYAN); tft.print("BPM ");
  if (bpmLocal > 0) tft.print((int)bpmLocal); else tft.print("--");
}

// ---------- Setup / Loop ----------
void setup() {
  Serial.begin(115200);
  if (LO_PLUS >= 0) pinMode(LO_PLUS, INPUT);
  if (LO_MINUS >= 0) pinMode(LO_MINUS, INPUT);
  analogReadResolution(12);

  spi.begin(TFT_SCK, -1, TFT_MOSI, TFT_CS);
  tft.init(240, 320);
  tft.setRotation(1);
  corrigirEspelhamento(0x28);
  tft.fillScreen(ST77XX_BLACK);

  // Nome com o final do MAC para diferenciar vários ESPs: IC-ECG-A1B2
  uint64_t mac = ESP.getEfuseMac();
  char nome[16];
  snprintf(nome, sizeof(nome), "IC-ECG-%04X", (uint16_t)(mac >> 32));
  BLEDevice::init(nome);
  BLEDevice::setMTU(247);
  servidor = BLEDevice::createServer();
  servidor->setCallbacks(new Callbacks());
  BLEService *svc = servidor->createService(UUID_SERVICO);
  chEcg = svc->createCharacteristic(UUID_ECG, BLECharacteristic::PROPERTY_NOTIFY);
  chEcg->addDescriptor(new BLE2902());
  chStatus = svc->createCharacteristic(UUID_STATUS, BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  chStatus->addDescriptor(new BLE2902());
  enviarStatus(false);
  svc->start();
  BLEAdvertising *adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(UUID_SERVICO);
  adv->setScanResponse(true);
  BLEDevice::startAdvertising();
  Serial.printf("IC ECG v%d anunciando como %s\n", FIRMWARE_VERSAO, nome);

  desenharCabecalho();
  desenharGrade();
  desenharRodape(false);
}

void loop() {
  static uint32_t proximaAmostra = micros();
  static uint32_t ultimoStatus = 0, ultimoRodape = 0;
  static bool soltoAnterior = false;

  // Conexão mudou: volta a anunciar ao desconectar, atualiza o display
  if (conectado != estavaConectado) {
    estavaConectado = conectado;
    if (!conectado) { delay(200); BLEDevice::startAdvertising(); }
    nPacote = 0;
    desenharCabecalho();
  }

  // Amostragem a 100 Hz com relógio fixo (sem acumular atraso)
  if ((int32_t)(micros() - proximaAmostra) >= 0) {
    proximaAmostra += TS_US;
    uint16_t adc = analogRead(ECG_PIN);
    float volts = adc * 3.3f / 4095.0f;
    idx++;
    detectarBPM(volts, idx);

    pacote[1 + nPacote++] = adc;
    if (nPacote == AMOSTRAS_POR_PACOTE) {
      pacote[0] = seq++;
      if (conectado) {
        chEcg->setValue((uint8_t *)pacote, sizeof(pacote));  // ESP32 é little-endian
        chEcg->notify();
      }
      nPacote = 0;
    }

    // Traçado no display
    int y = GRAPH_BOTTOM - 1 - (int)(volts / 3.3f * (GRAPH_BOTTOM - GRAPH_TOP - 2));
    int x = lastX + 1;
    if (x >= GRAPH_RIGHT) { desenharGrade(); x = GRAPH_LEFT + 1; lastY = y; }
    tft.drawLine(lastX, lastY, x, y, ST77XX_GREEN);
    lastX = x; lastY = y;
  }

  // Status (eletrodo solto) ao mudar e a cada 2 s; rodapé 1x por segundo
  bool solto = eletrodoSolto();
  uint32_t agora = millis();
  if (solto != soltoAnterior || agora - ultimoStatus > 2000) {
    enviarStatus(solto);
    ultimoStatus = agora;
  }
  if (solto != soltoAnterior || agora - ultimoRodape > 1000) {
    desenharRodape(solto);
    ultimoRodape = agora;
  }
  soltoAnterior = solto;
}
