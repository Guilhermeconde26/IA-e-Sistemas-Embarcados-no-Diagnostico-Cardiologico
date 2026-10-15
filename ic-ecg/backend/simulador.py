"""Gera ECG sintético na mesma faixa de tensão que o ESP32 lê do AD8232 (0–3,3 V)."""
import neurokit2 as nk
import numpy as np
from scipy.signal import resample_poly

FS_SIM = 500  # o ecgsyn do neurokit2 trava em algumas frequências cardíacas quando gera direto a 100 Hz


def gerar_sinal(bpm, ruido, fs=100, duracao=10):
    ecg = nk.ecg_simulate(duration=duracao, sampling_rate=FS_SIM, heart_rate=bpm,
                          noise=ruido, random_state=np.random.randint(1e6))
    ecg = resample_poly(ecg, fs, FS_SIM)
    ecg = 1.5 + 0.5 * ecg / np.max(np.abs(ecg))  # ~1,0–2,0 V
    return [round(float(v), 4) for v in np.clip(ecg, 0, 3.3)[:fs * duracao]]
