# Firmware IC ECG v3 (Bluetooth)

`ECGv3_ble/ECGv3_ble.ino` substitui o `ECGv2.3.ino`: sem Wi-Fi, sem servidor e sem ngrok. O ESP32-S3
lê o AD8232 a 100 Hz e envia cada amostra para o app por **Bluetooth Low Energy**. O display
continua mostrando o traçado, o BPM aproximado e o status da conexão.

## Gravar pela IDE do Arduino

1. **Placas**: instale "esp32 by Espressif Systems" (versão 3.x) no Gerenciador de Placas.
2. **Bibliotecas**: instale "Adafruit ST7735 and ST7789 Library" (a "Adafruit GFX" vem junto).
   O Bluetooth já vem no pacote do ESP32.
3. **Placa**: selecione *ESP32S3 Dev Module* e a porta COM do ESP.
4. Abra `ECGv3_ble.ino` e clique em Carregar.

No Monitor Serial (115200) deve aparecer `IC ECG v3 anunciando como IC-ECG-XXXX`, e o display mostra
"BLE aguardando app".

## Eletrodo solto (LO+ / LO−)

Na v2.3 os pinos eram 25 e 26, que **não existem no ESP32-S3**. Por isso, nesta versão a detecção vem
desligada (`LO_PLUS -1`, `LO_MINUS -1`). Se os fios LO+ e LO− do AD8232 estiverem ligados ao ESP,
coloque os números dos GPIOs reais nessas duas linhas. O app passa a avisar "Eletrodo solto" e
descarta as janelas afetadas.

## Protocolo

| Característica | UUID | Conteúdo |
|---|---|---|
| Serviço | `a3c87500-8ed3-4bdf-8a39-a01bebede295` | |
| ECG (notify) | `a3c87501-…` | 22 bytes a cada 100 ms: `uint16 seq` + 10 × `uint16` ADC (0–4095), little-endian |
| Status (read/notify) | `a3c87502-…` | `flags` (bit0 = eletrodo solto), `fs`, versão, amostras por pacote |

O contador `seq` permite ao app contar pacotes perdidos (aparece ao tocar no indicador do ECG).

Compilado com arduino-cli (esp32 3.3.12, ESP32-S3): 48% da flash e 9% da RAM.
