# IC ECG

Interface gráfica do projeto **IA e Sistemas Embarcados no Diagnóstico Cardiológico**.

```
ESP32 + AD8232 ──POST /classify──▶ FastAPI (backend/main.py) ──▶ SQLite (data/cardio.db)
  (firmware sem alterações)          │ filtro + Pan-Tompkins + Random Forest
                                     ├─ WebSocket ──▶ Painel web (gráfico ao vivo)
                                     └─ Claude API ─▶ Parecer da sessão
```

O `backend/main.py` **substitui o `server.py`**: o endpoint `/classify` recebe e responde exatamente
como antes (`{"classe", "bpm"}`), então o ESP32 continua funcionando sem mudar nada. A diferença é que agora
cada medição também é salva e aparece no painel.

## O que o aplicativo faz

| Aba | Quem vê | Conteúdo |
|---|---|---|
| **Medição** | todos | Identificação do paciente (nome, prontuário, idade, sexo) e monitor: cada aquisição de 10 s aparece com varredura, picos R e a classe de cada batimento; BPM e progresso da sessão (x/10) |
| **Resultados** | admin | Banco de dados: todas as sessões com busca. Cada uma abre um relatório com resumo, **parecer da IA**, medições, revisão de rótulos, **Gerar PDF** e exclusão de sessões/medições |
| **Operador** | todos | Troca de modo. **Paciente**: só faz medições. **Administrador** (senha `ADMIN_SENHA` do `.env`, padrão `admin`): acesso total, simulador e export do dataset |

Ao clicar em **Iniciar medição** com um paciente identificado, a próxima medição do ESP32 abre uma sessão nova para ele.
O **Gerar PDF** abre a impressão do navegador; escolha "Salvar como PDF".

## Como rodar

```bash
pip install -r requirements.txt
cp .env.example .env          # e coloque sua ANTHROPIC_API_KEY
```

O modelo fica em `backend/models/`. Para gerar de novo (na primeira vez baixa o MIT-BIH, ~100 MB):

```bash
python tools/gerar_dataset_mitbih.py
python tools/treinar_modelo.py mitbih_100hz_features.csv
```

> **Não use o `ecg_features.csv` antigo com este servidor.** Ele foi extraído a 360 Hz, em mV e sem
> normalização; o servidor trabalha a 100 Hz com z-score. As features ficam em escalas diferentes e o
> modelo classifica quase tudo como `/` ou `L`. O `gerar_dataset_mitbih.py` passa o MIT-BIH pela mesma
> pipeline do ESP32 (100 Hz, janelas de 10 s, mesmo filtro e detector de picos).

Suba o servidor (de dentro de `backend/`):

```bash
uvicorn main:app --host 0.0.0.0 --port 8000
```

Abra **http://localhost:8000**. No celular, na mesma rede Wi-Fi, use `http://IP-DO-PC:8000`.

Para o ESP32, mantenha o ngrok apontando para a porta 8000 (`ngrok http 8000`); a URL `/classify` do firmware continua a mesma.

Sem hardware, use o painel **Simular medição** na aba Ao vivo (as sessões simuladas ficam marcadas e não entram no dataset) ou o script:

```bash
python tools/simulador_esp32.py --medicoes 10
```

## Retreinar com os seus dados

1. Revise os rótulos no detalhe de cada medição (por batimento ou da medição inteira).
2. Na aba Dataset, baixe **Features — só revisados**.
3. `python tools/treinar_modelo.py mitbih_100hz_features.csv app_ecg_features.csv`
4. Reinicie o servidor. A versão do modelo fica gravada em cada medição.

## Observações

- **Parecer**: usa o `claude-opus-5-5` (troque em `CLAUDE_MODEL`). Só os números calculados são enviados (classes, BPM, VFC, erros); o sinal bruto não é enviado. O texto avisa que não é um diagnóstico médico.
- **Picos R**: o ponto do Pan-Tompkins agora é ajustado para o máximo local (±50 ms), alinhando com as anotações do MIT-BIH usadas no treino.
- **Classes**: por padrão o modelo usa as classes AAMI: **N** (normal, inclui bloqueios de ramo), **S** (supraventricular), **V** (ventricular) e **F** (fusão). Em pacientes que o modelo nunca viu, as 12 classes do MIT-BIH confundem batimento normal com bloqueio de ramo (L/R). Avaliação por paciente: N com precisão de 0,98 e recall de 0,94; V com recall de 0,72; S e F ainda fracos. Para voltar às 12 classes: `--classes mitbih`.
- **Resposta ao ESP32**: fica curta de propósito, porque o firmware lê em um `DynamicJsonDocument(256)`.
