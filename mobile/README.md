# IC ECG — app Android

App do projeto IC ECG: conecta ao ECG (ESP32-S3) por **Bluetooth Low Energy**, mostra o traçado em
tempo real, classifica cada janela de 10 s no próprio celular e guarda tudo num banco local.
Funciona **sem internet e sem servidor**.

```
ESP32-S3 + AD8232 ──BLE (100 Hz, pacotes de 10 amostras)──▶ app
                                                            ├─ traçado ao vivo
                                                            ├─ a cada 10 s: filtro → picos R → 10 features → Random Forest
                                                            ├─ SQLite no celular (sessões, medições, batimentos)
                                                            └─ PDF, revisão de rótulos, exportação do dataset
```

## Abas

| Aba | Quem vê | O que faz |
|---|---|---|
| **Medição** | todos | Conectar ao ECG, identificar o paciente, monitor ao vivo, resultado de cada medição |
| **Resultados** | administrador | Sessões com busca, relatório, **PDF**, excluir sessões e medições, revisar rótulos |
| **Operador** | todos | Modo paciente/administrador (PIN), simulador, medições por sessão, exportar dataset |

O app abre sempre no **modo paciente**. No primeiro acesso de administrador, o PIN digitado é criado.

## Instalar no celular

1. Copie `build/app/outputs/flutter-apk/app-release.apk` para o celular.
2. Abra o arquivo e permita "instalar apps desconhecidos" quando o Android pedir.
3. Na primeira conexão, permita o acesso a "Dispositivos por perto" (Bluetooth).

## Compilar

```bash
flutter test                  # pipeline Dart x Python, simulador e telas
flutter build apk --release
```

## Como a classificação fica igual ao treino

`lib/pipeline/pipeline_ecg.dart` é uma tradução linha a linha de `../ml/pipeline_ecg.py`.
`test/pipeline_test.dart` compara as duas com os casos de `test/golden.json` (sinais do MIT-BIH):
mesmos picos R, features com erro < 1e-6 e mesma classe em cada batimento. Se mudar a pipeline,
mude nos dois lugares, rode `python ../ml/gerar_golden.py` e o teste.

O modelo (`assets/modelo_rf.json`) vem de `python ../ml/treinar.py`. Para trocar o modelo, substitua o arquivo.

## Biblioteca de Bluetooth

`flutter_blue_plus` 2.x é gratuito para uso pessoal, pesquisa e instituições de ensino
(`License.nonprofit`); uso comercial exige licença paga. Ela envia um aviso anônimo de build
(nome e versão do app) ao compilar.
