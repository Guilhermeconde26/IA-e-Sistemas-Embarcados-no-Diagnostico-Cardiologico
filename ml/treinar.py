"""
Treina o Random Forest do app mobile e exporta em JSON (mobile/assets/modelo_rf.json).

Avaliação honesta: GroupKFold por paciente (registro) — nenhum paciente do teste aparece no treino.
O modelo é compacto (poucas árvores, profundidade limitada) para caber no app e rodar rápido no
celular; --comparar mede essa perda contra um RF grande.

Uso:
  python ml/treinar.py dados/mitbih_pipeline.csv                       # avalia, treina e exporta
  python ml/treinar.py dados/mitbih_pipeline.csv app_dataset.csv       # + dados revisados do app
  python ml/treinar.py dados/mitbih_pipeline.csv --comparar
"""
import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import balanced_accuracy_score, classification_report
from sklearn.model_selection import GroupKFold

import pipeline_ecg as P

CLASSES = ['F', 'N', 'S', 'V']
SAIDA = Path(__file__).resolve().parent.parent / 'mobile' / 'assets' / 'modelo_rf.json'
# Sem peso de classe: com 'balanced' o recall de N cai de 0,97 para 0,90 (muito alarme falso em gente saudável)
CONFIG_APP = dict(n_estimators=60, max_depth=12, min_samples_leaf=3, class_weight=None)


def novo(cfg):
    return RandomForestClassifier(**{'class_weight': 'balanced_subsample', **cfg}, random_state=42, n_jobs=-1)


def carregar(csvs):
    df = pd.concat([pd.read_csv(c) for c in csvs], ignore_index=True)
    df = df[df['label'].isin(CLASSES)].reset_index(drop=True)
    X = df[P.FEATURES].to_numpy(np.float64)
    ok = np.isfinite(X).all(axis=1)
    return df[ok].reset_index(drop=True), X[ok]


def avaliar(df, X, cfg, nome):
    y, grupos = df['label'].to_numpy(), df['record'].astype(str).to_numpy()
    pred = np.empty_like(y)
    for tr, te in GroupKFold(n_splits=4).split(X, y, grupos):
        pred[te] = novo(cfg).fit(X[tr], y[tr]).predict(X[te])
    print(f'\n=== {nome}: acurácia balanceada {balanced_accuracy_score(y, pred):.3f} (pacientes fora do treino)')
    print(classification_report(y, pred, zero_division=0, digits=3))


def exportar(modelo, n_treino):
    arvores = []
    for est in modelo.estimators_:
        t = est.tree_
        folha = t.children_left == -1
        val = t.value[:, 0, :]
        prob = val / val.sum(axis=1, keepdims=True)
        arvores.append({
            # nós internos: feature >= 0; folhas: feature = -1 e "valor" = índice em "probs"
            'feature': [int(f) if not fl else -1 for f, fl in zip(t.feature, folha)],
            # o sklearn compara em float32: x(float32) <= limiar
            'limiar': [float(np.float32(v)) if not fl else 0.0 for v, fl in zip(t.threshold, folha)],
            'esq': [int(v) for v in t.children_left],
            'dir': [int(v) for v in t.children_right],
            'probs': [[round(float(p), 6) for p in prob[i]] if folha[i] else None for i in range(t.node_count)],
        })
    doc = {
        'formato': 'icecg-rf-v1',
        'classes': [str(c) for c in modelo.classes_],
        'features': P.FEATURES,
        'fs': P.FS,
        'treinado_em': datetime.now(timezone.utc).isoformat(timespec='seconds'),
        'n_batimentos_treino': int(n_treino),
        'config': CONFIG_APP,
        'arvores': arvores,
    }
    SAIDA.parent.mkdir(parents=True, exist_ok=True)
    SAIDA.write_text(json.dumps(doc, separators=(',', ':')), encoding='utf-8')
    print(f'\nModelo exportado: {SAIDA} ({SAIDA.stat().st_size / 1e6:.1f} MB, '
          f'{sum(len(a["feature"]) for a in arvores)} nós)')


def main():
    p = argparse.ArgumentParser()
    p.add_argument('csvs', nargs='+')
    p.add_argument('--comparar', action='store_true')
    a = p.parse_args()
    df, X = carregar(a.csvs)
    print('Batimentos por classe:', df['label'].value_counts().to_dict())
    if a.comparar:
        avaliar(df, X, dict(n_estimators=200, max_depth=None, min_samples_leaf=2), 'RF grande (200 árvores)')
    avaliar(df, X, CONFIG_APP, 'RF do app (60 árvores, profundidade 12, sem peso de classe)')
    modelo = novo(CONFIG_APP).fit(X, df['label'].to_numpy())
    exportar(modelo, len(df))


if __name__ == '__main__':
    main()
