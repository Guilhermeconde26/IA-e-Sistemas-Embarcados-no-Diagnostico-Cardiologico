"""
Gera mobile/test/golden.json: casos de entrada + saídas da pipeline Python + modelo JSON.
O teste do app (mobile/test/pipeline_test.dart) exige que o Dart reproduza tudo:
mesmos picos R, features com erro < 1e-6 e mesma classe em cada batimento.

Uso: python ml/gerar_golden.py --mitdb pasta/do/mitdb
"""
import argparse
import json
import sys
from pathlib import Path

import numpy as np
import wfdb
from scipy.signal import resample_poly

import pipeline_ecg as P
from modelo_json import ModeloRF

RAIZ = Path(__file__).resolve().parent.parent
MODELO = RAIZ / 'mobile' / 'assets' / 'modelo_rf.json'
SAIDA = RAIZ / 'mobile' / 'test' / 'golden.json'


def janela_mitbih(pasta, rec, ini_s):
    r = wfdb.rdrecord(str(pasta / rec))
    c = r.sig_name.index('MLII') if 'MLII' in r.sig_name else 0
    s = resample_poly(r.p_signal[:, c], P.FS, 360)
    x = s[ini_s * P.FS:(ini_s + 10) * P.FS]
    return [round(float(v) * 0.5 + 1.5, 4) for v in x]  # escala/offset parecidos com o ADC do ESP


def sintetico():
    import neurokit2 as nk
    e = nk.ecg_simulate(duration=10, sampling_rate=500, heart_rate=75, noise=0.03, random_state=7)
    e = resample_poly(e, P.FS, 500)
    return [round(float(v), 4) for v in 1.5 + 0.5 * e / np.max(np.abs(e))][:1000]


def caso(nome, sinal, modelo):
    c = {'nome': nome, 'entrada': sinal}
    try:
        y, rpeaks, feats, usados = P.processar(sinal)
    except P.ErroSinal as e:
        c['erro'] = str(e)
        return c
    preds = [modelo.prever(f) for f in feats]
    c.update(filtrado=[float(v) for v in y], rpeaks=[int(r) for r in rpeaks], usados=[int(u) for u in usados],
             features=[[float(v) for v in f] for f in feats],
             classes=[p[0] for p in preds], probs=[[float(v) for v in p[2]] for p in preds])
    return c


def main():
    a = argparse.ArgumentParser()
    a.add_argument('--mitdb', default='mitdb')
    pasta = Path(a.parse_args().mitdb)
    modelo = ModeloRF(MODELO)

    # 1) o modelo JSON concorda com o sklearn? (mesmo treino, avaliado nos dados de treino)
    import pandas as pd
    df = pd.read_csv(Path(__file__).parent / 'dados' / 'mitbih_pipeline.csv').sample(2000, random_state=0)
    sys.path.insert(0, str(Path(__file__).parent))
    import treinar as T
    sk = T.novo(T.CONFIG_APP).fit(*(lambda d, X: (X, d['label'].to_numpy()))(*T.carregar(
        [Path(__file__).parent / 'dados' / 'mitbih_pipeline.csv'])))
    X = df[P.FEATURES].to_numpy()
    iguais = np.mean([modelo.prever(x)[0] == p for x, p in zip(X, sk.predict(X))])
    print(f'Concordância modelo JSON x sklearn (2000 batimentos): {iguais:.2%}')

    casos = [
        caso('mitbih_100_normal', janela_mitbih(pasta, '100', 60), modelo),
        caso('mitbih_119_bigeminismo_V', janela_mitbih(pasta, '119', 300), modelo),
        caso('mitbih_208_V_e_F', janela_mitbih(pasta, '208', 120), modelo),
        caso('mitbih_232_S', janela_mitbih(pasta, '232', 200), modelo),
        caso('sintetico_75bpm', sintetico(), modelo),
        caso('erro_sinal_plano', [1.5] * 1000, modelo),
        caso('erro_sinal_curto', [1.5] * 150, modelo),
    ]
    SAIDA.parent.mkdir(parents=True, exist_ok=True)
    SAIDA.write_text(json.dumps({'casos': casos}), encoding='utf-8')
    for c in casos:
        print(f"  {c['nome']:28s}", c.get('erro') or f"{len(c['rpeaks'])} picos, classes {''.join(c['classes'])}")
    print('Golden salvo em', SAIDA)


if __name__ == '__main__':
    main()
