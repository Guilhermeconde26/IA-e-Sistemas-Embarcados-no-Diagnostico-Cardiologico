"""Confere que as contas escritas à mão em pipeline_ecg.py são idênticas às do scipy.
Rodar: python ml/tests/test_equivalencia_scipy.py"""
import sys
from pathlib import Path

import numpy as np
from scipy import signal
from scipy.stats import kurtosis, skew

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import pipeline_ecg as P  # noqa: E402

rng = np.random.default_rng(0)

b, a = signal.butter(3, [0.5 / 50, 40 / 50], btype='band')
assert np.allclose(b, P.B, atol=1e-8) and np.allclose(a, P.A, atol=1e-8), (b, a)
assert np.allclose(signal.lfilter_zi(b, a), P.ZI, atol=1e-10)

x = np.cumsum(rng.normal(size=1000)) + np.sin(np.arange(1000) / 7)
assert np.allclose(signal.filtfilt(b, a, x), P.filtfilt(x), atol=1e-9)

for n in (10, 37, 70, 71):
    w = rng.normal(size=n)
    f, pxx = signal.welch(w, fs=100, nperseg=min(256, n))
    assert abs(np.trapezoid(pxx, f) - P.energia_espectral(w)) < 1e-10, n
    c = w - w.mean()
    assert abs(skew(w) - np.mean(c ** 3) / np.mean(c ** 2) ** 1.5) < 1e-12
    assert abs(kurtosis(w) - (np.mean(c ** 4) / np.mean(c ** 2) ** 2 - 3)) < 1e-12

print('OK: filtro, filtfilt, Welch, assimetria e curtose idênticos ao scipy')
