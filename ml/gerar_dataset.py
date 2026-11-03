"""
Gera o dataset de treino do app mobile passando o MIT-BIH pela pipeline_ecg.py
(100 Hz, janelas de 10 s, mesmo filtro, detector e features que o app usa).
Cada pico detectado recebe o rótulo AAMI da anotação mais próxima (até 100 ms).

Uso: python ml/gerar_dataset.py --mitdb pasta/do/mitdb --saida ml/dados/mitbih_pipeline.csv
     (baixa o MIT-BIH, ~90 MB, se a pasta não existir)
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np
import pandas as pd
import requests
import wfdb
from scipy.signal import resample_poly

import pipeline_ecg as P

ESPELHO = 'https://physionet-open.s3.amazonaws.com/mitdb/1.0.0'  # espelho oficial da PhysioNet
# Padrão AAMI EC57; marca-passo (/, f) e Q ficam de fora
AAMI = {**{k: 'N' for k in 'NLRej'}, **{k: 'S' for k in 'AaJS'}, 'V': 'V', 'E': 'V', 'F': 'F'}
TOL = int(0.1 * P.FS)


def baixar(pasta):
    print('Baixando o MIT-BIH (~90 MB)...')
    pasta.mkdir(parents=True, exist_ok=True)
    recs = requests.get(f'{ESPELHO}/RECORDS', timeout=30).text.split()

    def um(nome):
        r = requests.get(f'{ESPELHO}/{nome}', timeout=120)
        r.raise_for_status()
        (pasta / nome).write_bytes(r.content)
    with ThreadPoolExecutor(12) as ex:
        list(ex.map(um, [f'{r}.{e}' for r in recs for e in ('hea', 'dat', 'atr')]))
    (pasta / 'RECORDS').write_text('\n'.join(recs))


def registro(pasta, rec):
    record = wfdb.rdrecord(str(pasta / rec))
    ann = wfdb.rdann(str(pasta / rec), 'atr')
    canal = record.sig_name.index('MLII') if 'MLII' in record.sig_name else 0
    sinal = resample_poly(record.p_signal[:, canal], P.FS, 360)
    pos = np.array([round(s * P.FS / 360) for s in ann.sample])
    sym = np.array(ann.symbol)
    ok = np.isin(sym, list('NLRAaJSVFejE/fQ'))
    pos, sym = pos[ok], sym[ok]

    linhas, jan = [], 10 * P.FS
    for ini in range(0, len(sinal) - jan + 1, jan):
        try:
            _, _, feats, usados = P.processar(sinal[ini:ini + jan])
        except P.ErroSinal:
            continue
        for f, r in zip(feats, usados):
            t = ini + r
            k = int(np.abs(pos - t).argmin())
            if abs(pos[k] - t) <= TOL and sym[k] in AAMI:
                linhas.append([*f, t, AAMI[sym[k]], sym[k], rec])
    return linhas


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--mitdb', default='mitdb')
    p.add_argument('--saida', default='dados/mitbih_pipeline.csv')
    a = p.parse_args()
    pasta = Path(a.mitdb)
    if not (pasta / 'RECORDS').exists():
        baixar(pasta)
    recs = (pasta / 'RECORDS').read_text().split()
    with ThreadPoolExecutor(8) as ex:
        partes = list(ex.map(lambda r: registro(pasta, r), recs))
    df = pd.DataFrame([l for parte in partes for l in parte],
                      columns=P.FEATURES + ['r_sample', 'label', 'simbolo', 'record'])
    Path(a.saida).parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(a.saida, index=False)
    print(f'{len(df)} batimentos em {a.saida}')
    print(df['label'].value_counts().to_string())


if __name__ == '__main__':
    main()
