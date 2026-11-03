// Pipeline do IC ECG — tradução linha a linha de ml/pipeline_ecg.py.
// O modelo só acerta se estas contas forem idênticas às do treino; test/pipeline_test.dart
// compara com test/golden.json (gerado pelo Python). Mudou algo aqui? Mude lá e regenere o golden.
import 'dart:math' as math;

const int fs = 100;
const List<String> nomesFeatures = [
  'rr_interval', 'heart_rate', 'r_amp', 'window_mean', 'window_std',
  'window_min', 'window_max', 'window_skew', 'window_kurt', 'spectral_energy',
];

// Butterworth ordem 3, passa-faixa 0,5–40 Hz a 100 Hz (scipy.signal.butter(3, [0.5/50, 40/50], 'band'))
const List<double> _b = [
  0.5103784499368984, 0.0, -1.5311353498106952, 0.0, 1.5311353498106952, 0.0, -0.5103784499368984,
];
const List<double> _a = [
  1.0, -1.1805341192831271, -1.1025652254782896, 0.9232840789432326, 0.9315984103575622,
  -0.3115879665987758, -0.2600665881864121,
];

const int _padlen = 21; // 3 * max(len(a), len(b))
const int _janelaIntegracao = 15; // 150 ms
const int _refratario = 25; // 250 ms
const double _limiarRel = 0.15;
const int _buscaR = 15; // 150 ms
const int _pre = 30, _pos = 40; // -300 ms .. +400 ms

class ErroSinal implements Exception {
  final String mensagem;
  ErroSinal(this.mensagem);
  @override
  String toString() => mensagem;
}

class ResultadoPipeline {
  final List<double> filtrado;
  final List<int> rpeaks;
  final List<List<double>> features; // uma linha por batimento (a partir do 2º pico)
  final List<int> usados; // posição do pico R de cada linha de features
  ResultadoPipeline(this.filtrado, this.rpeaks, this.features, this.usados);
}

// ------------------------------------------------------------------ filtro
/// Resolve (I - Mᵀ) zi = b[1:] - a[1:]·b[0] por eliminação de Gauss (= scipy.signal.lfilter_zi).
List<double> _lfilterZi() {
  final n = _a.length - 1;
  // m = transposta da matriz companheira: m[i][0] = -a[i+1]; m[i][i+1] = 1
  final mat = List.generate(n, (i) => List<double>.filled(n + 1, 0));
  for (var i = 0; i < n; i++) {
    for (var j = 0; j < n; j++) {
      double m = 0;
      if (j == 0) m = -_a[i + 1];
      if (j == i + 1) m = 1;
      mat[i][j] = (i == j ? 1.0 : 0.0) - m;
    }
    mat[i][n] = _b[i + 1] - _a[i + 1] * _b[0];
  }
  for (var c = 0; c < n; c++) {
    var piv = c;
    for (var r = c + 1; r < n; r++) {
      if (mat[r][c].abs() > mat[piv][c].abs()) piv = r;
    }
    final t = mat[c]; mat[c] = mat[piv]; mat[piv] = t;
    for (var r = 0; r < n; r++) {
      if (r == c) continue;
      final f = mat[r][c] / mat[c][c];
      for (var k = c; k <= n; k++) {
        mat[r][k] -= f * mat[c][k];
      }
    }
  }
  return List.generate(n, (i) => mat[i][n] / mat[i][i]);
}

final List<double> _zi = _lfilterZi();

/// IIR forma direta II transposta (a[0] = 1). Também usado, só para frente, no traçado ao vivo.
List<double> lfilter(List<double> x, List<double> zi) {
  final z = List<double>.of(zi);
  final y = List<double>.filled(x.length, 0);
  final n = z.length;
  for (var i = 0; i < x.length; i++) {
    final xi = x[i];
    final yi = _b[0] * xi + z[0];
    for (var k = 0; k < n - 1; k++) {
      z[k] = _b[k + 1] * xi + z[k + 1] - _a[k + 1] * yi;
    }
    z[n - 1] = _b[n] * xi - _a[n] * yi;
    y[i] = yi;
  }
  return y;
}

List<double> filtfilt(List<double> x) {
  if (x.length <= _padlen) throw ErroSinal('Sinal muito curto');
  final n = x.length;
  final ext = <double>[
    for (var i = _padlen; i >= 1; i--) 2 * x[0] - x[i],
    ...x,
    for (var i = n - 2; i >= n - 1 - _padlen; i--) 2 * x[n - 1] - x[i],
  ];
  var y = lfilter(ext, [for (final v in _zi) v * ext[0]]);
  final rev = y.reversed.toList();
  y = lfilter(rev, [for (final v in _zi) v * rev[0]]).reversed.toList();
  return y.sublist(_padlen, y.length - _padlen);
}

/// Filtro só para frente (causal), com estado — usado no traçado ao vivo do app.
class FiltroAoVivo {
  List<double>? _z;
  double filtrar(double x) {
    final z = _z ??= [for (final v in _zi) v * x];
    final n = z.length;
    final y = _b[0] * x + z[0];
    for (var k = 0; k < n - 1; k++) {
      z[k] = _b[k + 1] * x + z[k + 1] - _a[k + 1] * y;
    }
    z[n - 1] = _b[n] * x - _a[n] * y;
    return y;
  }

  void reiniciar() => _z = null;
}

double _media(List<double> v) {
  var s = 0.0;
  for (final x in v) {
    s += x;
  }
  return s / v.length;
}

List<double> preparar(List<double> sinal) {
  if (sinal.length < 2 * fs) throw ErroSinal('Sinal muito curto');
  final y = filtfilt(sinal);
  final m = _media(y);
  var s2 = 0.0;
  for (var i = 0; i < y.length; i++) {
    y[i] -= m;
    s2 += y[i] * y[i];
  }
  final std = math.sqrt(s2 / y.length);
  if (std < 1e-6) throw ErroSinal('Sinal muito fraco');
  return [for (final v in y) v / std];
}

// ------------------------------------------------------------------ detector de picos R
double _percentilInferior(List<double> v, double q) {
  final s = List<double>.of(v)..sort();
  return s[(q * (s.length - 1)).floor()];
}

List<int> detectarPicos(List<double> y) {
  final n = y.length;
  final sq = List<double>.filled(n, 0);
  for (var i = 1; i < n; i++) {
    final d = y[i] - y[i - 1];
    sq[i] = d * d;
  }
  final mwi = List<double>.filled(n, 0);
  var acc = 0.0;
  for (var i = 0; i < n; i++) {
    acc += sq[i];
    if (i >= _janelaIntegracao) acc -= sq[i - _janelaIntegracao];
    mwi[i] = acc / _janelaIntegracao;
  }
  final limiar = _limiarRel * _percentilInferior(mwi, 0.98);

  final picos = <int>[];
  for (var i = 1; i < n - 1; i++) {
    if (mwi[i] > limiar && mwi[i] >= mwi[i - 1] && mwi[i] > mwi[i + 1]) {
      if (picos.isNotEmpty && i - picos.last < _refratario) {
        if (mwi[i] > mwi[picos.last]) picos[picos.length - 1] = i;
      } else {
        picos.add(i);
      }
    }
  }

  final rpeaks = <int>[];
  for (final p in picos) {
    final ini = math.max(0, p - _buscaR);
    var r = ini;
    for (var k = ini + 1; k <= p; k++) {
      if (y[k] > y[r]) r = k; // argmax: primeiro máximo, como no numpy
    }
    if (rpeaks.isEmpty || r - rpeaks.last >= _refratario) {
      rpeaks.add(r);
    } else if (y[r] > y[rpeaks.last]) {
      rpeaks[rpeaks.length - 1] = r;
    }
  }
  return rpeaks;
}

// ------------------------------------------------------------------ features
/// = trapz(Pxx, f) de scipy.signal.welch(w, fs, nperseg=len(w)).
double energiaEspectral(List<double> w) {
  final n = w.length;
  final m = _media(w);
  final x = List<double>.filled(n, 0);
  var somaJan = 0.0;
  for (var i = 0; i < n; i++) {
    final jan = 0.5 - 0.5 * math.cos(2 * math.pi * i / n);
    x[i] = (w[i] - m) * jan;
    somaJan += jan * jan;
  }
  final escala = 1.0 / (fs * somaJan);
  final nf = n ~/ 2 + 1;
  final p = List<double>.filled(nf, 0);
  for (var k = 0; k < nf; k++) {
    var re = 0.0, im = 0.0;
    for (var i = 0; i < n; i++) {
      final ang = 2 * math.pi * k * i / n;
      re += x[i] * math.cos(ang);
      im -= x[i] * math.sin(ang);
    }
    p[k] = (re * re + im * im) * escala;
  }
  final ultimo = n.isEven ? nf - 1 : nf; // Nyquist (n par) não é dobrado
  for (var k = 1; k < ultimo; k++) {
    p[k] *= 2;
  }
  final df = fs / n;
  var area = 0.0;
  for (var k = 1; k < nf; k++) {
    area += (p[k] + p[k - 1]) * 0.5;
  }
  return area * df;
}

({List<List<double>> features, List<int> usados}) featuresBatimentos(List<double> y, List<int> rpeaks) {
  final linhas = <List<double>>[];
  final usados = <int>[];
  for (var i = 1; i < rpeaks.length; i++) {
    final r = rpeaks[i], rp = rpeaks[i - 1];
    final rr = (r - rp) / fs;
    if (rr <= 0) continue;
    final w = y.sublist(math.max(0, r - _pre), math.min(y.length, r + _pos));
    if (w.length < 10) continue;
    final m = _media(w);
    var m2 = 0.0, m3 = 0.0, m4 = 0.0, mn = w[0], mx = w[0];
    for (final v in w) {
      final c = v - m;
      m2 += c * c;
      m3 += c * c * c;
      m4 += c * c * c * c;
      if (v < mn) mn = v;
      if (v > mx) mx = v;
    }
    m2 /= w.length;
    m3 /= w.length;
    m4 /= w.length;
    final skew = m2 > 0 ? m3 / math.pow(m2, 1.5) : 0.0;
    final kurt = m2 > 0 ? m4 / (m2 * m2) - 3.0 : 0.0;
    linhas.add([rr, 60.0 / rr, y[r], m, math.sqrt(m2), mn, mx, skew, kurt, energiaEspectral(w)]);
    usados.add(r);
  }
  return (features: linhas, usados: usados);
}

ResultadoPipeline processar(List<double> sinal) {
  final y = preparar(sinal);
  final rpeaks = detectarPicos(y);
  if (rpeaks.length < 2) throw ErroSinal('Poucos picos R detectados');
  final f = featuresBatimentos(y, rpeaks);
  if (f.usados.isEmpty) throw ErroSinal('Falha na extração de features');
  return ResultadoPipeline(y, rpeaks, f.features, f.usados);
}

/// Métricas de variabilidade da frequência cardíaca (domínio do tempo), em ms.
Map<String, double> metricasVfc(List<int> rpeaks) {
  if (rpeaks.length < 3) return {};
  final rr = [for (var i = 1; i < rpeaks.length; i++) (rpeaks[i] - rpeaks[i - 1]) * 1000.0 / fs];
  final m = _media(rr);
  var s = 0.0;
  for (final v in rr) {
    s += (v - m) * (v - m);
  }
  final d = [for (var i = 1; i < rr.length; i++) rr[i] - rr[i - 1]];
  var q = 0.0;
  for (final v in d) {
    q += v * v;
  }
  double r1(double v) => (v * 10).roundToDouble() / 10;
  return {
    'rr_medio_ms': r1(m),
    'sdnn_ms': r1(math.sqrt(s / (rr.length - 1))),
    'rmssd_ms': r1(d.isEmpty ? 0 : math.sqrt(q / d.length)),
  };
}
