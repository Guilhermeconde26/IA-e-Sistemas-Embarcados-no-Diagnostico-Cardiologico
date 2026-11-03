🔧 Projeto de ECG com Arduino e Classificação de Arritmias

Este projeto combina aquisição de sinal cardíaco via Arduino com processamento e classificação de arritmias utilizando um modelo de Random Forest. O objetivo é desenvolver um sistema simples e acessível para detecção automática de padrões cardíacos anormais a partir de sinais ECG.

📡 Aquisição do Sinal

Captura do traçado ECG em tempo real usando Arduino.

Pré-processamento do sinal (filtros, normalização e remoção de ruídos).

Extração de características relevantes para análise.

🤖 Classificação de Arritmias

Treinamento de um classificador Random Forest usando dados do MIT-BIH Arrhythmia Database.

Identificação das principais classes de batimentos (N, V, A, L, entre outras).

Foco em precisão e interpretabilidade.

🎯 Objetivo

Criar uma pipeline completa — da leitura do sinal ao diagnóstico automatizado — para apoiar estudos, prototipagem e aplicações educacionais em engenharia biomédica e ciência de dados.

🚀 Tecnologias utilizadas

Arduino (aquisição do sinal)

Python (NumPy, SciPy, scikit-learn)

Random Forest Classifier

MIT-BIH Arrhythmia Database

📱 Aplicativo IC ECG

A pasta [`ic-ecg/`](ic-ecg/) contém a interface gráfica do projeto: servidor FastAPI que substitui o `server.py`
(o ESP32 continua enviando para `/classify` sem mudanças), painel web com monitor ao vivo, identificação do paciente,
banco de dados das medições, relatório em PDF, parecer gerado por IA e modo administrador.
Instruções de instalação e uso em [`ic-ecg/README.md`](ic-ecg/README.md).

📲 App mobile com Bluetooth (branch `app-mobile-ble`)

Versão sem servidor nem Wi-Fi: o ESP32-S3 envia o sinal por Bluetooth Low Energy para um app Android
que mostra o ECG ao vivo, classifica no próprio celular e guarda tudo localmente.

- [`firmware/`](firmware/): firmware v3 do ESP32-S3 (BLE)
- [`mobile/`](mobile/): app Android em Flutter
- [`ml/`](ml/): pipeline de referência, dataset do MIT-BIH a 100 Hz e treino do modelo usado no app
