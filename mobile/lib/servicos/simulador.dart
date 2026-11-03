// ECG sintético em tempo real (100 Hz, pacotes de 10 amostras a cada 100 ms), no mesmo formato do
// ESP (valores do ADC 0..4095). Cada batimento é uma soma de gaussianas (ondas P, Q, R, S, T).
import 'dart:async';
import 'dart:math' as math;

class _Onda {
  final double t, a, s; // centro relativo ao R (s), amplitude (mV), largura (s)
  const _Onda(this.t, this.a, this.s);
}

const _normal = [
  _Onda(-0.20, 0.15, 0.025), _Onda(-0.03, -0.12, 0.010), _Onda(0.0, 1.0, 0.012),
  _Onda(0.035, -0.25, 0.012), _Onda(0.25, 0.30, 0.050),
];
// Extrassístole ventricular: sem onda P, QRS largo e T invertida
const _ventricular = [_Onda(0.0, 1.3, 0.035), _Onda(0.07, -0.5, 0.030), _Onda(0.30, -0.40, 0.070)];

class SimuladorEcg {
  final double bpm;
  final double ruido; // desvio do ruído em mV
  final bool extrassistoles; // ~1 a cada 6 batimentos vira ventricular precoce
  SimuladorEcg({this.bpm = 72, this.ruido = 0.03, this.extrassistoles = false});

  final _rnd = math.Random();
  Timer? _timer;
  int _n = 0;
  final List<({double t, bool ventricular})> _batimentos = [];
  final List<double> _historicoPvc = []; // não é podado (usado nos testes)
  double _proximo = 0.4;

  Stream<List<int>> iniciar() {
    final c = StreamController<List<int>>();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      c.add([for (var i = 0; i < 10; i++) _amostra()]);
    });
    c.onCancel = parar;
    return c.stream;
  }

  void parar() {
    _timer?.cancel();
    _timer = null;
  }

  /// Gera n amostras de uma vez (usado nos testes).
  List<int> gerar(int n) => [for (var i = 0; i < n; i++) _amostra()];

  /// Instantes (s) das extrassístoles já geradas — para conferir a classificação nos testes.
  List<double> get temposVentriculares => List.unmodifiable(_historicoPvc);

  void _agendar(double t) {
    while (_proximo < t + 1.0) {
      final rr = 60.0 / bpm * (1 + (_rnd.nextDouble() - 0.5) * 0.08);
      final pvc = extrassistoles && _batimentos.isNotEmpty && !_batimentos.last.ventricular && _rnd.nextDouble() < 0.17;
      if (pvc) {
        final t0 = _proximo - rr * 0.38; // precoce...
        _batimentos.add((t: t0, ventricular: true));
        _historicoPvc.add(t0);
        _proximo += rr * 0.6; // ...seguida de pausa compensatória
      } else {
        _batimentos.add((t: _proximo, ventricular: false));
        _proximo += rr;
      }
    }
    _batimentos.removeWhere((b) => b.t < t - 2);
  }

  int _amostra() {
    final t = _n / 100.0;
    _n++;
    _agendar(t);
    var mv = 0.08 * math.sin(2 * math.pi * 0.25 * t); // respiração / deriva da linha de base
    for (final b in _batimentos) {
      for (final o in b.ventricular ? _ventricular : _normal) {
        final d = t - b.t - o.t;
        mv += o.a * math.exp(-d * d / (2 * o.s * o.s));
      }
    }
    // ruído gaussiano (Box-Muller)
    final g = math.sqrt(-2 * math.log(1 - _rnd.nextDouble())) * math.cos(2 * math.pi * _rnd.nextDouble());
    mv += ruido * g;
    final volts = 1.5 + 0.4 * mv;
    return (volts / 3.3 * 4095).round().clamp(0, 4095);
  }
}
