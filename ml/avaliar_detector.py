"""
Mede o detector de picos R do pipeline_ecg.py contra as anotações do MIT-BIH, nas mesmas
condições do ESP32 (100 Hz, janelas de 10 s). Acerto = pico a até 100 ms de uma anotação.

Uso: python ml/avaliar_detector.py --mitdb pasta/do/mitdb
"""
import argparse
from pathlib import Path

import numpy as np
import wfdb
from scipy.signal import resample_poly

import pipeline_ecg as P

SIMBOLOS = set('NLRAaJSVFejE/fQ')
TOL = int(0.1 * P.FS)


def avaliar(pasta, rec):
    record = wfdb.rdrecord(str(pasta / rec))
    ann = wfdb.rdann(str(pasta / rec), 'atr')
    canal = record.sig_name.index('MLII') if 'MLII' in record.sig_name else 0
    sinal = resample_poly(record.p_signal[:, canal], P.FS, 360)
    anot = np.array([round(s * P.FS / 360) for s, sym in zip(ann.sample, ann.symbol) if sym in SIMBOLOS])
    vp = fn = fp = 0
    jan = 10 * P.FS
    for ini in range(0, len(sinal) - jan + 1, jan):
        verdade = anot[(anot >= ini + 5) & (anot < ini + jan - 5)] - ini  # ignora bordas
        try:
            picos = np.array(P.detectar_picos(P.preparar(sinal[ini:ini + jan])))
        except P.ErroSinal:
            picos = np.array([], dtype=int)
        picos = picos[(picos >= 5) & (picos < jan - 5)]
        usados = set()
        for t in verdade:
            if len(picos) and (d := np.abs(picos - t)).min() <= TOL and int(d.argmin()) not in usados:
                vp += 1
                usados.add(int(d.argmin()))
            else:
                fn += 1
        fp += len(picos) - len(usados)
    return vp, fn, fp


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--mitdb', default='mitdb')
    a = p.parse_args()
    pasta = Path(a.mitdb)
    total = np.zeros(3, dtype=int)
    for rec in (pasta / 'RECORDS').read_text().split():
        vp, fn, fp = avaliar(pasta, rec)
        total += (vp, fn, fp)
        se, ppv = vp / max(1, vp + fn), vp / max(1, vp + fp)
        if se < 0.95 or ppv < 0.95:
            print(f'  registro {rec}: sensibilidade {se:.3f}  VPP {ppv:.3f}')
    vp, fn, fp = total
    print(f'TOTAL: sensibilidade {vp / (vp + fn):.4f}  valor preditivo positivo {vp / (vp + fp):.4f}  '
          f'(VP {vp}, FN {fn}, FP {fp})')


if __name__ == '__main__':
    main()
