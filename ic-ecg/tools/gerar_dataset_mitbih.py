"""
Gera o dataset de treino a partir do MIT-BIH usando EXATAMENTE a pipeline do aplicativo.

Por que: o ecg_features.csv original foi extraído a 360 Hz, em mV, sem normalização.
O ESP32 manda 100 Hz e o servidor normaliza (z-score) — as features ficam em outra escala
(ex.: r_amp ~1,3 no treino vs ~3,8 no app) e o modelo classifica quase tudo errado.

Aqui cada registro é:
  1. reamostrado de 360 Hz para 100 Hz (taxa do ESP32)
  2. cortado em janelas de 10 s (o mesmo tamanho de cada medição do ESP32)
  3. passado por preparar_sinal + detectar_picos + extrair_features do backend
  4. cada pico detectado recebe o rótulo da anotação do MIT-BIH mais próxima (até 100 ms)

Uso:
  python tools/gerar_dataset_mitbih.py                     # baixa o MIT-BIH (~90 MB) em ./mitdb
  python tools/gerar_dataset_mitbih.py --mitdb C:/dados/mitdb --saida mitbih_100hz.csv
"""
import argparse
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np
import pandas as pd
import requests
import wfdb
from scipy.signal import resample_poly

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / 'backend'))
from processing import (FEATURE_COLS, ProcessingError, detectar_picos,  # noqa: E402
                        extrair_features, preparar_sinal)

FS_ORIG, FS = 360, 100
JANELA = 10 * FS
TOLERANCIA = int(0.1 * FS)  # 100 ms entre pico detectado e anotação
SIMBOLOS = set('NLRAaJSVFejE/fQ')  # anotações que são batimentos


# Espelho oficial da PhysioNet na AWS — bem mais rápido que physionet.org
ESPELHO = 'https://physionet-open.s3.amazonaws.com/mitdb/1.0.0'


def baixar_mitdb(pasta):
    print('Baixando o MIT-BIH Arrhythmia Database (~90 MB)...')
    pasta.mkdir(parents=True, exist_ok=True)
    registros = requests.get(f'{ESPELHO}/RECORDS', timeout=30).text.split()

    def baixar(nome):
        r = requests.get(f'{ESPELHO}/{nome}', timeout=120)
        r.raise_for_status()
        (pasta / nome).write_bytes(r.content)

    arquivos = [f'{rec}.{ext}' for rec in registros for ext in ('hea', 'dat', 'atr')]
    with ThreadPoolExecutor(max_workers=12) as ex:
        list(ex.map(baixar, arquivos))
    (pasta / 'RECORDS').write_text('\n'.join(registros))  # por último: marca o download como completo


def processar_registro(caminho, rec):
    record = wfdb.rdrecord(str(caminho / rec))
    ann = wfdb.rdann(str(caminho / rec), 'atr')
    canal = record.sig_name.index('MLII') if 'MLII' in record.sig_name else 0
    sinal = resample_poly(record.p_signal[:, canal], FS, FS_ORIG)

    amostras = np.round(np.array(ann.sample) * FS / FS_ORIG).astype(int)
    simbolos = np.array(ann.symbol)
    eh_batimento = np.isin(simbolos, list(SIMBOLOS))
    amostras, simbolos = amostras[eh_batimento], simbolos[eh_batimento]

    linhas = []
    for ini in range(0, len(sinal) - JANELA + 1, JANELA):
        try:
            filtrado = preparar_sinal(sinal[ini:ini + JANELA], FS)
            picos = detectar_picos(filtrado, FS)
        except ProcessingError:
            continue
        if len(picos) < 2:
            continue
        feats, usados = extrair_features(filtrado, picos, FS)
        for (_, row), r in zip(feats.iterrows(), usados):
            pos = ini + r
            j = np.searchsorted(amostras, pos)
            cand = [k for k in (j - 1, j) if 0 <= k < len(amostras)]
            if not cand:
                continue
            k = min(cand, key=lambda k: abs(amostras[k] - pos))
            if abs(amostras[k] - pos) > TOLERANCIA:
                continue  # pico falso (ruído) — não entra no treino
            linhas.append([*row[FEATURE_COLS].tolist(), pos, simbolos[k], rec, FS])
    return linhas


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--mitdb', default='mitdb', help='pasta com o MIT-BIH (baixa se não existir)')
    p.add_argument('--saida', default='mitbih_100hz_features.csv')
    a = p.parse_args()

    pasta = Path(a.mitdb)
    if not (pasta / 'RECORDS').exists():
        baixar_mitdb(pasta)
    registros = (pasta / 'RECORDS').read_text().split()

    todas = []
    for i, rec in enumerate(registros, 1):
        linhas = processar_registro(pasta, rec)
        todas += linhas
        print(f'[{i}/{len(registros)}] registro {rec}: {len(linhas)} batimentos')

    df = pd.DataFrame(todas, columns=FEATURE_COLS + ['r_sample', 'label', 'record', 'fs'])
    df.to_csv(a.saida, index=False)
    print(f'\n{len(df)} batimentos salvos em {a.saida}')
    print(df['label'].value_counts().to_string())


if __name__ == '__main__':
    main()
