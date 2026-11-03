# ml — pipeline, dataset e modelo do app mobile

| Arquivo | Para quê |
|---|---|
| `pipeline_ecg.py` | Pipeline de referência (filtro, detector de picos R, features). Numpy puro, espelhado em `mobile/lib/pipeline/pipeline_ecg.dart` |
| `avaliar_detector.py` | Mede o detector contra as anotações do MIT-BIH (100 Hz, janelas de 10 s) |
| `gerar_dataset.py` | MIT-BIH → `dados/mitbih_pipeline.csv`, com rótulos AAMI (N, S, V, F) |
| `treinar.py` | Avalia por paciente e exporta `mobile/assets/modelo_rf.json` |
| `modelo_json.py` | Avalia o JSON como o app faz (confere com o sklearn) |
| `gerar_golden.py` | Gera `mobile/test/golden.json` para o teste do app |
| `tests/test_equivalencia_scipy.py` | Confere que o filtro, o Welch e as estatísticas escritos à mão são iguais ao scipy |

```bash
pip install numpy scipy pandas scikit-learn wfdb requests neurokit2
python tests/test_equivalencia_scipy.py
python gerar_dataset.py --mitdb mitdb          # baixa o MIT-BIH (~90 MB) na 1ª vez
python treinar.py dados/mitbih_pipeline.csv    # + CSVs exportados pelo app, se houver
python gerar_golden.py --mitdb mitdb
```

## Resultados atuais (pacientes fora do treino, GroupKFold por registro)

- Detector de picos R: sensibilidade 98,96%, valor preditivo positivo 98,74%.
- Modelo do app (60 árvores, profundidade 12):

| Classe | Precisão | Recall |
|---|---|---|
| N (normal, inclui bloqueios de ramo) | 0,95 | 0,97 |
| V (ventricular) | 0,79 | 0,77 |
| S (supraventricular) | 0,11 | 0,06 |
| F (fusão) | 0,17 | 0,03 |

S e F são fracos em qualquer configuração testada: as 10 features não bastam para separá-los entre
pacientes diferentes. O caminho para melhorar é treinar com dados do próprio hardware, revisados no app.
