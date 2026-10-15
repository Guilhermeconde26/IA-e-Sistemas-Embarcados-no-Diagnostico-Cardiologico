"""
Simula o ESP32 pela rede: gera 10 s de ECG sintético a 100 Hz e envia para /classify,
exatamente como o firmware ECGv2.3.ino faz. (No site, o mesmo está no painel "Simular medição".)

Uso:
  python tools/simulador_esp32.py                       # 1 ciclo de 10 medições, 1 s entre elas
  python tools/simulador_esp32.py --medicoes 3 --bpm 110 --intervalo 0
  python tools/simulador_esp32.py --url https://seu-ngrok.ngrok-free.dev/classify
"""
import argparse
import sys
import time
from pathlib import Path

import numpy as np
import requests

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / 'backend'))
from simulador import gerar_sinal  # noqa: E402


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--url', default='http://localhost:8000/classify')
    p.add_argument('--medicoes', type=int, default=10)
    p.add_argument('--bpm', type=float, default=72)
    p.add_argument('--ruido', type=float, default=0.02)
    p.add_argument('--intervalo', type=float, default=1.0, help='segundos entre envios')
    a = p.parse_args()

    for i in range(a.medicoes):
        sinal = gerar_sinal(a.bpm + np.random.uniform(-4, 4), a.ruido)
        r = requests.post(a.url, json={'signal': sinal}, timeout=30)
        print(f'[{i + 1}/{a.medicoes}] HTTP {r.status_code}: {r.text}')
        if i < a.medicoes - 1:
            time.sleep(a.intervalo)


if __name__ == '__main__':
    main()
