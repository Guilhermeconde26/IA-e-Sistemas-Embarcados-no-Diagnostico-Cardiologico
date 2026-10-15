"""
Treina o Random Forest (mesma receita do rf.py original) e salva em backend/models/.

Uso:
  python tools/treinar_modelo.py mitbih_100hz_features.csv        # gerado por gerar_dataset_mitbih.py
  python tools/treinar_modelo.py mitbih_100hz_features.csv app_ecg_features.csv   # + dados do app
  python tools/treinar_modelo.py --classes mitbih mitbih_100hz_features.csv       # 12 símbolos originais

--classes aami (padrão): agrupa os símbolos do MIT-BIH nas classes do padrão AAMI EC57
  N = normal, bloqueios de ramo (L, R) e escapes (e, j)
  S = ectópicos supraventriculares (A, a, J, S)
  V = ectópicos ventriculares (V, E)
  F = fusão ventricular + normal (F)
  Batimentos de marca-passo (/, f) e não classificáveis (Q) ficam de fora, como manda o padrão.
  Em pacientes que o modelo nunca viu, N vs L/R é praticamente impossível de separar com estas
  features (L e R vêm de poucos pacientes) — com 12 classes o modelo confunde batimentos normais
  com bloqueio de ramo. Com AAMI, N e V ficam confiáveis.

Os CSVs exportados pelo aplicativo (aba Dataset) têm as mesmas colunas do MIT-BIH, então
são simplesmente concatenados. Prefira o export "só revisados".
"""
import sys
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import classification_report
from sklearn.model_selection import GroupShuffleSplit
from sklearn.preprocessing import LabelEncoder

FEATURES = ['rr_interval', 'heart_rate', 'r_amp', 'window_mean', 'window_std',
            'window_min', 'window_max', 'window_skew', 'window_kurt', 'spectral_energy']
VALIDOS = set('NLRAaJSVFejE/fQ')  # símbolos de batimento do MIT-BIH (descarta ruído/ritmo)
SAIDA = Path(__file__).resolve().parent.parent / 'backend' / 'models'


AAMI = {**{k: 'N' for k in 'NLRej'}, **{k: 'S' for k in 'AaJS'}, 'V': 'V', 'E': 'V', 'F': 'F'}


def main(csvs, classes):
    df = pd.concat([pd.read_csv(c, low_memory=False) for c in csvs], ignore_index=True)
    print('Linhas lidas:', len(df))

    df['label'] = df['label'].astype(str).str.strip()
    df = df[df['label'].isin(VALIDOS)]
    if classes == 'aami':
        df['label'] = df['label'].map(AAMI)  # rótulos já em AAMI (N/S/V/F) mapeiam para si mesmos
        df = df.dropna(subset=['label'])
    counts = df['label'].value_counts()
    df = df[df['label'].isin(counts[counts >= 50].index)]
    print('Classes mantidas:', dict(df['label'].value_counts()))

    X = df[FEATURES].apply(pd.to_numeric, errors='coerce')
    X = X.replace([np.inf, -np.inf], np.nan).fillna(X.median())
    le = LabelEncoder()
    y = le.fit_transform(df['label'])

    novo_modelo = lambda: RandomForestClassifier(n_estimators=200, min_samples_leaf=2,
                                                 class_weight='balanced_subsample',
                                                 random_state=42, n_jobs=-1)

    # Avaliação honesta: pacientes (records) do teste nunca aparecem no treino.
    # Um split aleatório mistura batimentos do mesmo paciente e infla a acurácia.
    grupos = df['record'].astype(str).values
    tr, te = next(GroupShuffleSplit(n_splits=1, test_size=0.25, random_state=42).split(X, y, grupos))
    model = novo_modelo().fit(X.iloc[tr], y[tr])
    print(f'Avaliação com {len(set(grupos[te]))} pacientes fora do treino:')
    presentes = np.unique(np.concatenate([y[te], model.predict(X.iloc[te])]))
    print(classification_report(y[te], model.predict(X.iloc[te]), labels=presentes,
                                target_names=le.classes_[presentes], zero_division=0))

    # Modelo final: treinado com todos os dados
    model = novo_modelo().fit(X, y)

    SAIDA.mkdir(parents=True, exist_ok=True)
    joblib.dump(model, SAIDA / 'rf_ecg_model.pkl', compress=3)
    joblib.dump(le, SAIDA / 'label_encoder.pkl')
    print('Modelo salvo em', SAIDA, '— reinicie o servidor para carregar.')


if __name__ == '__main__':
    args = sys.argv[1:]
    classes = 'aami'
    if args[:1] == ['--classes']:
        classes, args = args[1], args[2:]
    if not args or classes not in ('aami', 'mitbih'):
        sys.exit(__doc__)
    main(args, classes)
