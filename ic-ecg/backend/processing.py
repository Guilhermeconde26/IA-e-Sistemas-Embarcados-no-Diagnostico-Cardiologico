"""
Processamento do sinal ECG — mesma pipeline do server.py original
(filtro Butterworth 0.5–40 Hz, z-score, Pan-Tompkins, 10 features por batimento),
mas devolvendo tudo o que o aplicativo precisa: sinal filtrado, picos R,
features e classificação de cada batimento, probabilidades e métricas de VFC.
"""
import numpy as np
import pandas as pd
import neurokit2 as nk
from scipy import signal
from scipy.stats import skew, kurtosis

FEATURE_COLS = [
    'rr_interval', 'heart_rate', 'r_amp', 'window_mean', 'window_std',
    'window_min', 'window_max', 'window_skew', 'window_kurt', 'spectral_energy'
]

# Símbolos de batimento do MIT-BIH
CLASSES = {
    'N': 'Batimento normal',
    'L': 'Bloqueio de ramo esquerdo',
    'R': 'Bloqueio de ramo direito',
    'A': 'Extrassístole atrial',
    'a': 'Extrassístole atrial aberrante',
    'J': 'Extrassístole juncional (nodal)',
    'S': 'Extrassístole supraventricular',
    'V': 'Extrassístole ventricular (ESV/PVC)',
    'F': 'Fusão ventricular + normal',
    'e': 'Escape atrial',
    'j': 'Escape juncional (nodal)',
    'E': 'Escape ventricular',
    '/': 'Batimento de marca-passo',
    'f': 'Fusão marca-passo + normal',
    'Q': 'Não classificável',
}

# Classes do padrão AAMI EC57 (modelo padrão do tools/treinar_modelo.py)
CLASSES_AAMI = {
    'N': 'Normal (inclui bloqueios de ramo e escapes)',
    'S': 'Ectópico supraventricular (extrassístole atrial/juncional)',
    'V': 'Ectópico ventricular (extrassístole ventricular/ESV)',
    'F': 'Fusão ventricular + normal',
}


def descricoes_classes(classes_modelo):
    """Descrições das classes que o modelo carregado realmente usa."""
    if classes_modelo is not None and set(classes_modelo) <= set(CLASSES_AAMI):
        return dict(CLASSES_AAMI)
    return dict(CLASSES)


class ProcessingError(Exception):
    pass


def filtrar_sinal(sinal, fs):
    b, a = signal.butter(3, [0.5 / (fs / 2), 40 / (fs / 2)], btype='band')
    return signal.filtfilt(b, a, sinal)


def extrair_features(signal_data, rpeaks, fs):
    """Uma linha por batimento (a partir do 2º pico). Devolve (DataFrame, índices dos picos usados)."""
    features, usados = [], []
    pre_s, post_s = int(0.3 * fs), int(0.4 * fs)

    for i in range(1, len(rpeaks)):
        r_idx, prev_r_idx = int(rpeaks[i]), int(rpeaks[i - 1])
        rr_interval = (r_idx - prev_r_idx) / fs
        if rr_interval <= 0:
            continue

        start, end = max(0, r_idx - pre_s), min(len(signal_data), r_idx + post_s)
        win = signal_data[start:end]
        if len(win) < 10:
            continue

        f, Pxx = signal.welch(win, fs=fs, nperseg=min(256, len(win)))
        features.append([
            rr_interval,
            60.0 / rr_interval,
            float(signal_data[r_idx]),
            float(np.mean(win)),
            float(np.std(win)),
            float(np.min(win)),
            float(np.max(win)),
            float(skew(win)),
            float(kurtosis(win)),
            float(np.trapezoid(Pxx, f)),
        ])
        usados.append(r_idx)

    return pd.DataFrame(features, columns=FEATURE_COLS), usados


def metricas_vfc(rpeaks, fs):
    """Métricas de variabilidade da frequência cardíaca (domínio do tempo)."""
    rr = np.diff(rpeaks) / fs * 1000.0  # ms
    if len(rr) < 2:
        return {}
    drr = np.diff(rr)
    return {
        'rr_medio_ms': round(float(np.mean(rr)), 1),
        'sdnn_ms': round(float(np.std(rr, ddof=1)), 1),
        'rmssd_ms': round(float(np.sqrt(np.mean(drr ** 2))), 1),
        'pnn50_pct': round(float(np.mean(np.abs(drr) > 50) * 100), 1),
        'rr_min_ms': round(float(np.min(rr)), 1),
        'rr_max_ms': round(float(np.max(rr)), 1),
    }


def preparar_sinal(ecg_raw, fs):
    """Filtro 0,5–40 Hz + z-score. Usado igual no app e na geração do dataset de treino."""
    ecg = np.asarray(ecg_raw, dtype=np.float64)
    if len(ecg) < fs * 2:
        raise ProcessingError('Sinal muito curto')
    ecg_filtrado = filtrar_sinal(ecg, fs)
    ecg_filtrado = ecg_filtrado - np.mean(ecg_filtrado)
    std = np.std(ecg_filtrado)
    if std < 1e-6:
        raise ProcessingError('Sinal muito fraco')
    return ecg_filtrado / std


def detectar_picos(ecg_filtrado, fs):
    """Pan-Tompkins + ajuste de cada pico para o máximo local (±50 ms)."""
    try:
        _, info = nk.ecg_peaks(ecg_filtrado, sampling_rate=fs, method='pantompkins1985')
        rpeaks = np.array(info['ECG_R_Peaks'], dtype=int)
    except Exception as e:
        raise ProcessingError(f'Falha na extração: {e}')
    viz = max(1, int(0.05 * fs))
    return np.array(sorted({
        int(max(0, r - viz) + np.argmax(ecg_filtrado[max(0, r - viz):r + viz + 1])) for r in rpeaks
    }), dtype=int)


def processar(ecg_raw, fs, modelo=None, le=None):
    """Executa a pipeline completa. Lança ProcessingError com mensagem amigável em caso de falha."""
    ecg_filtrado = preparar_sinal(ecg_raw, fs)
    rpeaks = detectar_picos(ecg_filtrado, fs)

    if len(rpeaks) < 2:
        raise ProcessingError('Poucos R-peaks detectados')

    df_feats, picos_usados = extrair_features(ecg_filtrado, rpeaks, fs)
    if df_feats.empty:
        raise ProcessingError('Falha na extração de features')

    bpm = float(round(60 / np.mean(np.diff(rpeaks) / fs), 1))

    resultado = {
        'filtered': [round(float(v), 4) for v in ecg_filtrado],
        'rpeaks': [int(r) for r in rpeaks],
        'bpm': bpm,
        'hrv': metricas_vfc(rpeaks, fs),
        'beats': [],
        'classe': None,
        'distribuicao': {},
    }

    labels, confs = [None] * len(df_feats), [None] * len(df_feats)
    if modelo is not None and le is not None:
        probs = modelo.predict_proba(df_feats)
        preds = np.argmax(probs, axis=1)
        labels = list(le.inverse_transform(modelo.classes_[preds]))
        confs = [float(p[i]) for p, i in zip(probs, preds)]
        # Mesma regra do server.py original: classe da medição = último batimento
        resultado['classe'] = str(labels[-1])
        dist = pd.Series(labels).value_counts()
        resultado['distribuicao'] = {str(k): int(v) for k, v in dist.items()}

    for (_, row), r_idx, lbl, conf in zip(df_feats.iterrows(), picos_usados, labels, confs):
        resultado['beats'].append({
            'r_sample': int(r_idx),
            'features': {c: float(row[c]) for c in FEATURE_COLS},
            'pred_label': None if lbl is None else str(lbl),
            'confidence': None if conf is None else round(conf, 3),
        })

    return resultado
