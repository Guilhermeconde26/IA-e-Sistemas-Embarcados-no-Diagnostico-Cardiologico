"""
Pipeline de referência do IC ECG — a MESMA conta é feita no app (mobile/lib/pipeline/).

Por que existe: o modelo só acerta se as features do treino forem calculadas exatamente como no app.
Tudo aqui é numpy puro, passo a passo, para ser traduzido linha a linha para Dart; o filtro e o
detector de picos são nossos (sem neurokit/scipy na inferência). tests/golden.json guarda saídas
desta implementação que o teste do app compara número a número.

Entrada: uma janela de 10 s a 100 Hz (1000 amostras, qualquer escala — é normalizada).
Saída: picos R e as 10 features de cada batimento (a partir do 2º pico).
"""
import numpy as np

FS = 100
FEATURES = ['rr_interval', 'heart_rate', 'r_amp', 'window_mean', 'window_std',
            'window_min', 'window_max', 'window_skew', 'window_kurt', 'spectral_energy']

# Butterworth ordem 3, passa-faixa 0,5–40 Hz a 100 Hz: scipy.signal.butter(3, [0.5/50, 40/50], 'band')
# (coeficientes fixos para o app não depender de projeto de filtro)
B = np.array([0.5103784499368984, 0.0, -1.5311353498106952, 0.0, 1.5311353498106952, 0.0, -0.5103784499368984])
A = np.array([1.0, -1.1805341192831271, -1.1025652254782896, 0.9232840789432326, 0.9315984103575622,
              -0.3115879665987758, -0.2600665881864121])

PADLEN = 3 * max(len(A), len(B))  # 21, igual ao padrão do scipy.signal.filtfilt
JANELA_INTEGRACAO = int(0.15 * FS)  # 150 ms
REFRATARIO = int(0.25 * FS)  # 250 ms entre batimentos (máx. 240 bpm)
LIMIAR_REL = 0.15  # fração do percentil 98 do sinal integrado (avaliar_detector.py: Se 98,96%, VPP 98,74%)
BUSCA_R = int(0.15 * FS)  # o R fica até 150 ms antes do pico do sinal integrado
PRE, POS = int(0.3 * FS), int(0.4 * FS)  # janela de cada batimento: -300 ms .. +400 ms


class ErroSinal(Exception):
    pass


# ---------------------------------------------------------------- filtro
def lfilter_zi(b, a):
    """Condições iniciais de regime (igual a scipy.signal.lfilter_zi)."""
    n = len(a)
    m = np.zeros((n - 1, n - 1))  # = transposta da matriz companheira de a
    m[:, 0] = -a[1:]
    m[:-1, 1:] = np.eye(n - 2)
    i_minus_a = np.eye(n - 1) - m
    bb = b[1:] - a[1:] * b[0]
    return np.linalg.solve(i_minus_a, bb)


ZI = lfilter_zi(B, A)


def lfilter(b, a, x, zi):
    """IIR forma direta II transposta (a[0] = 1)."""
    z = zi.copy()
    y = np.empty_like(x)
    n = len(z)
    for i, xi in enumerate(x):
        yi = b[0] * xi + z[0]
        for k in range(n - 1):
            z[k] = b[k + 1] * xi + z[k + 1] - a[k + 1] * yi
        z[n - 1] = b[n] * xi - a[n] * yi
        y[i] = yi
    return y


def filtfilt(x):
    """Filtro de fase zero com extensão ímpar nas bordas (= scipy.signal.filtfilt padrão)."""
    if len(x) <= PADLEN:
        raise ErroSinal('Sinal muito curto')
    ext = np.concatenate([2 * x[0] - x[PADLEN:0:-1], x, 2 * x[-1] - x[-2:-PADLEN - 2:-1]])
    y = lfilter(B, A, ext, ZI * ext[0])
    y = lfilter(B, A, y[::-1], ZI * y[-1])[::-1]
    return y[PADLEN:-PADLEN]


def preparar(sinal):
    x = np.asarray(sinal, dtype=np.float64)
    if len(x) < 2 * FS:
        raise ErroSinal('Sinal muito curto')
    y = filtfilt(x)
    y = y - y.mean()
    std = np.sqrt(np.mean(y * y))
    if std < 1e-6:
        raise ErroSinal('Sinal muito fraco')
    return y / std


# ---------------------------------------------------------------- detector de picos R
def percentil_inferior(v, q):
    """Elemento de posição floor(q*(n-1)) do vetor ordenado (definição simples e portável)."""
    s = np.sort(v)
    return s[int(np.floor(q * (len(s) - 1)))]


def detectar_picos(y):
    """Estilo Pan-Tompkins: derivada -> quadrado -> média móvel de 150 ms -> máximos locais
    acima do limiar, com período refratário; cada pico é levado ao máximo do sinal filtrado."""
    n = len(y)
    d = np.zeros(n)
    d[1:] = y[1:] - y[:-1]
    sq = d * d
    mwi = np.zeros(n)
    acc = 0.0
    for i in range(n):  # média móvel causal
        acc += sq[i]
        if i >= JANELA_INTEGRACAO:
            acc -= sq[i - JANELA_INTEGRACAO]
        mwi[i] = acc / JANELA_INTEGRACAO
    limiar = LIMIAR_REL * percentil_inferior(mwi, 0.98)

    picos = []
    for i in range(1, n - 1):
        if mwi[i] > limiar and mwi[i] >= mwi[i - 1] and mwi[i] > mwi[i + 1]:
            if picos and i - picos[-1] < REFRATARIO:
                if mwi[i] > mwi[picos[-1]]:
                    picos[-1] = i
            else:
                picos.append(i)

    rpeaks = []
    for p in picos:
        ini = max(0, p - BUSCA_R)
        r = ini + int(np.argmax(y[ini:p + 1]))
        if not rpeaks or r - rpeaks[-1] >= REFRATARIO:
            rpeaks.append(r)
        elif y[r] > y[rpeaks[-1]]:
            rpeaks[-1] = r
    return rpeaks


# ---------------------------------------------------------------- features
def energia_espectral(w, fs=FS):
    """= trapz(Pxx, f) de scipy.signal.welch(w, fs, nperseg=len(w)) (1 segmento, Hann periódica,
    detrend constante, densidade, unilateral). Escrito com DFT explícita para portar ao Dart."""
    n = len(w)
    win = 0.5 - 0.5 * np.cos(2 * np.pi * np.arange(n) / n)
    x = (w - w.mean()) * win
    escala = 1.0 / (fs * np.sum(win * win))
    nf = n // 2 + 1
    k = np.arange(nf)
    ang = 2 * np.pi * np.outer(k, np.arange(n)) / n
    re = (x * np.cos(ang)).sum(axis=1)
    im = -(x * np.sin(ang)).sum(axis=1)
    p = (re * re + im * im) * escala
    if n % 2 == 0:
        p[1:-1] *= 2
    else:
        p[1:] *= 2
    df = fs / n
    return float(np.sum((p[1:] + p[:-1]) * 0.5) * df)


def features_batimentos(y, rpeaks, fs=FS):
    linhas, usados = [], []
    for i in range(1, len(rpeaks)):
        r, rp = rpeaks[i], rpeaks[i - 1]
        rr = (r - rp) / fs
        if rr <= 0:
            continue
        w = y[max(0, r - PRE):min(len(y), r + POS)]
        if len(w) < 10:
            continue
        m = w.mean()
        c = w - m
        m2 = np.mean(c ** 2)
        m3 = np.mean(c ** 3)
        m4 = np.mean(c ** 4)
        skew = m3 / m2 ** 1.5 if m2 > 0 else 0.0
        kurt = m4 / m2 ** 2 - 3.0 if m2 > 0 else 0.0
        linhas.append([rr, 60.0 / rr, float(y[r]), float(m), float(np.sqrt(m2)),
                       float(w.min()), float(w.max()), float(skew), float(kurt), energia_espectral(w, fs)])
        usados.append(r)
    return np.array(linhas, dtype=np.float64).reshape(-1, len(FEATURES)), usados


def processar(sinal):
    """Janela de 10 s -> (sinal filtrado, picos R, matriz de features, picos usados)."""
    y = preparar(sinal)
    rpeaks = detectar_picos(y)
    if len(rpeaks) < 2:
        raise ErroSinal('Poucos picos R detectados')
    feats, usados = features_batimentos(y, rpeaks)
    if len(usados) == 0:
        raise ErroSinal('Falha na extração de features')
    return y, rpeaks, feats, usados
