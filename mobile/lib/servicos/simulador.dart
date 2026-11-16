// ECG sintético em tempo real (100 Hz, pacotes de 10 amostras a cada 100 ms), no mesmo formato do
// ESP (valores do ADC 0..4095). Cada onda (P, Q, R, S, T) é uma gaussiana; o ritmo escolhido decide
// quando cada batimento acontece, qual a forma dele e se há ondas de base (fibrilação, flutter).
// O simulador guarda a classe verdadeira de cada batimento (padrão AAMI) para conferir o modelo.
import 'dart:async';
import 'dart:math' as math;

enum GrupoRitmo { sinusal, extrassistoles, taquiarritmias, bloqueios }

enum Ritmo {
  normal('Ritmo sinusal normal', GrupoRitmo.sinusal, 72, true,
      'Batimentos regulares, cada um precedido de onda P.', {'N'}),
  bradicardia('Bradicardia sinusal', GrupoRitmo.sinusal, 45, true, 'Ritmo sinusal lento (< 60 bpm).', {'N'}),
  taquicardia('Taquicardia sinusal', GrupoRitmo.sinusal, 125, true, 'Ritmo sinusal rápido (> 100 bpm).', {'N'}),
  arritmiaSinusal('Arritmia sinusal respiratória', GrupoRitmo.sinusal, 70, true,
      'A frequência acelera na inspiração e desacelera na expiração. Normal em jovens.', {'N'}),
  extrassistolesV('Extrassístoles ventriculares', GrupoRitmo.extrassistoles, 72, true,
      'Batimentos precoces, sem onda P, com QRS largo e T invertida, seguidos de pausa compensatória.', {'N', 'V'}),
  bigeminismo('Bigeminismo ventricular', GrupoRitmo.extrassistoles, 70, true,
      'Um batimento normal e uma extrassístole ventricular alternados.', {'N', 'V'}),
  trigeminismo('Trigeminismo ventricular', GrupoRitmo.extrassistoles, 72, true,
      'Dois batimentos normais e uma extrassístole ventricular, repetidamente.', {'N', 'V'}),
  extrassistolesS('Extrassístoles supraventriculares', GrupoRitmo.extrassistoles, 72, true,
      'Batimentos precoces com onda P diferente e QRS normal, sem pausa compensatória.', {'N', 'S'}),
  fusao('Batimentos de fusão', GrupoRitmo.extrassistoles, 72, true,
      'Um impulso ventricular encontra o sinusal: QRS intermediário entre o normal e o ventricular.', {'N', 'F'}),
  taquicardiaV('Taquicardia ventricular (salvas)', GrupoRitmo.taquiarritmias, 72, true,
      'Sequências de batimentos ventriculares rápidos (~170 bpm) entre batimentos normais.', {'N', 'V'}),
  fibrilacaoAtrial('Fibrilação atrial', GrupoRitmo.taquiarritmias, 95, true,
      'Sem ondas P: a linha de base tremula (ondas f) e os intervalos RR são totalmente irregulares.', {'N'}),
  flutterAtrial('Flutter atrial', GrupoRitmo.taquiarritmias, 0, false,
      'Ondas F em "dente de serra" a 300/min, conduzidas 2:1 ou 4:1 para os ventrículos.', {'N'}),
  bloqueioRamo('Bloqueio de ramo', GrupoRitmo.bloqueios, 72, true,
      'QRS alargado e com entalhe (rSR\'), com T oposta ao QRS. Ritmo regular.', {'N'}),
  bloqueioAV2('Bloqueio AV de 2º grau (Wenckebach)', GrupoRitmo.bloqueios, 75, true,
      'O intervalo PR aumenta a cada batimento até uma onda P ficar sem QRS.', {'N'}),
  bloqueioAVTotal('Bloqueio AV total', GrupoRitmo.bloqueios, 0, false,
      'Ondas P (80/min) e QRS (40/min) sem relação entre si: escape juncional.', {'N'});

  const Ritmo(this.nome, this.grupo, this.bpmPadrao, this.usaBpm, this.descricao, this.classesEsperadas);
  final String nome;
  final GrupoRitmo grupo;
  final double bpmPadrao;
  final bool usaBpm;
  final String descricao;
  final Set<String> classesEsperadas;

  /// O modelo classifica batimentos, não o ritmo: estes aparecem como N com RR irregular ou pausas.
  bool get soRitmo => classesEsperadas.length == 1 && this != Ritmo.normal;
}

class _Onda {
  final double t, a, s; // centro (s), amplitude (mV), largura (s)
  const _Onda(this.t, this.a, this.s);
  _Onda desloca(double dt, [double escala = 1]) => _Onda(t + dt, a * escala, s);
}

// Formas (centros relativos ao pico R; a onda P é posta à parte, conforme o PR)
const _qrsNormal = [_Onda(-0.03, -0.12, 0.010), _Onda(0.0, 1.0, 0.012), _Onda(0.035, -0.25, 0.012), _Onda(0.25, 0.30, 0.050)];
const _qrsVentricular = [_Onda(0.0, 1.3, 0.035), _Onda(0.07, -0.5, 0.030), _Onda(0.30, -0.40, 0.070)];
const _qrsRamo = [
  _Onda(-0.03, -0.08, 0.010), _Onda(0.0, 0.75, 0.016), _Onda(0.032, -0.18, 0.010), _Onda(0.065, 0.6, 0.018),
  _Onda(0.30, -0.22, 0.060),
];
const _qrsJuncional = [_Onda(-0.02, -0.10, 0.011), _Onda(0.0, 0.95, 0.014), _Onda(0.04, -0.28, 0.013), _Onda(0.27, 0.25, 0.055)];
const _ondaP = _Onda(0, 0.15, 0.025);
const _ondaPEctopica = _Onda(0, -0.10, 0.020); // P de foco atrial diferente (invertida)

class BatimentoSimulado {
  final double t; // instante do pico R (s)
  final String classe; // N, S, V ou F (AAMI)
  const BatimentoSimulado(this.t, this.classe);
}

class _Evento {
  final List<_Onda> ondas; // centros absolutos
  final double fim;
  _Evento(this.ondas) : fim = ondas.map((o) => o.t + 4 * o.s).reduce(math.max);
}

class SimuladorEcg {
  SimuladorEcg({this.ritmo = Ritmo.normal, double? bpm, this.ruido = 0.03, bool extrassistoles = false})
      : bpm = bpm ?? (ritmo.bpmPadrao > 0 ? ritmo.bpmPadrao : 72) {
    if (extrassistoles && ritmo == Ritmo.normal) _ritmo = Ritmo.extrassistolesV;
  }

  final Ritmo ritmo;
  late Ritmo _ritmo = ritmo;
  final double bpm;
  final double ruido; // desvio do ruído em mV

  final _rnd = math.Random();
  Timer? _timer;
  int _n = 0;
  final List<_Evento> _eventos = [];
  final List<BatimentoSimulado> _verdade = [];
  double _proximo = 0.5; // próximo batimento sinusal
  double _ultimoR = 0;
  int _contador = 0;
  int _normaisNoGrupo = 0;
  double _proximoP = 0.4; // ondas P independentes (bloqueios)
  double _fase = 0; // fase das ondas f da fibrilação

  Ritmo get ritmoAtual => _ritmo;

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

  /// Batimentos gerados até agora, com a classe verdadeira.
  List<BatimentoSimulado> get batimentos => List.unmodifiable(_verdade);

  /// Instantes (s) das extrassístoles ventriculares geradas (usado nos testes).
  List<double> get temposVentriculares => [for (final b in _verdade) if (b.classe == 'V') b.t];

  double get _rr => 60.0 / bpm * (1 + (_rnd.nextDouble() - 0.5) * 0.04);

  void _batimento(double tR, String classe, List<_Onda> qrs, {double? pr, _Onda p = _ondaP, double escala = 1}) {
    final ondas = [for (final o in qrs) o.desloca(tR, escala)];
    if (pr != null) ondas.add(p.desloca(tR - pr));
    _eventos.add(_Evento(ondas));
    _verdade.add(BatimentoSimulado(tR, classe));
    _ultimoR = tR;
    _contador++;
  }

  void _soP(double t, [_Onda p = _ondaP]) => _eventos.add(_Evento([p.desloca(t)]));

  void _agendar(double t) {
    while (_proximo < t + 1.5) {
      final rr = _rr;
      switch (_ritmo) {
        case Ritmo.normal || Ritmo.bradicardia || Ritmo.taquicardia:
          _batimento(_proximo, 'N', _qrsNormal, pr: 0.16);
          _proximo += rr;
        case Ritmo.arritmiaSinusal:
          _batimento(_proximo, 'N', _qrsNormal, pr: 0.16);
          _proximo += rr * (1 + 0.15 * math.sin(2 * math.pi * 0.22 * _proximo));
        case Ritmo.extrassistolesV:
          final pvc = _verdade.isNotEmpty && _verdade.last.classe != 'V' && _rnd.nextDouble() < 0.17;
          if (pvc) {
            _batimento(_ultimoR + rr * 0.6, 'V', _qrsVentricular);
            _proximo += rr; // pausa compensatória completa: o sinusal seguinte vem 2 RR após o anterior
          } else {
            _batimento(_proximo, 'N', _qrsNormal, pr: 0.16);
            _proximo += rr;
          }
        case Ritmo.bigeminismo || Ritmo.trigeminismo:
          // bigeminismo: N V N V...; trigeminismo: N N V N N V...
          final normaisPorGrupo = _ritmo == Ritmo.bigeminismo ? 1 : 2;
          _batimento(_proximo, 'N', _qrsNormal, pr: 0.16);
          if (++_normaisNoGrupo == normaisPorGrupo) {
            _batimento(_proximo + rr * 0.6, 'V', _qrsVentricular);
            _proximo += 2 * rr; // pausa compensatória
            _normaisNoGrupo = 0;
          } else {
            _proximo += rr;
          }
        case Ritmo.extrassistolesS:
          final pac = _verdade.isNotEmpty && _verdade.last.classe != 'S' && _rnd.nextDouble() < 0.18;
          if (pac) {
            final t0 = _ultimoR + rr * 0.68;
            _batimento(t0, 'S', _qrsNormal, pr: 0.13, p: _ondaPEctopica);
            _proximo = t0 + rr; // sem pausa compensatória: o nó sinusal é "reiniciado"
          } else {
            _batimento(_proximo, 'N', _qrsNormal, pr: 0.16);
            _proximo += rr;
          }
        case Ritmo.fusao:
          if (_verdade.isNotEmpty && _verdade.last.classe != 'F' && _rnd.nextDouble() < 0.2) {
            // fusão: metade normal + metade ventricular, quase no tempo do sinusal
            final t0 = _proximo - rr * 0.06;
            _batimento(t0, 'F', [
              for (final o in _qrsNormal) _Onda(o.t, o.a * 0.55, o.s),
              for (final o in _qrsVentricular) _Onda(o.t + 0.01, o.a * 0.5, o.s),
            ], pr: 0.10);
          } else {
            _batimento(_proximo, 'N', _qrsNormal, pr: 0.16);
          }
          _proximo += rr;
        case Ritmo.taquicardiaV:
          if (_contador % 13 >= 7) {
            // salva de 6 batimentos ventriculares a ~170 bpm
            for (var i = 0; i < 6; i++) {
              _batimento(_proximo + i * 0.35, 'V', _qrsVentricular, escala: 0.9);
            }
            _proximo += 6 * 0.35 + rr * 0.9;
          } else {
            _batimento(_proximo, 'N', _qrsNormal, pr: 0.16);
            _proximo += rr;
          }
        case Ritmo.fibrilacaoAtrial:
          _batimento(_proximo, 'N', _qrsNormal); // sem onda P
          _proximo += 60.0 / bpm * (0.55 + _rnd.nextDouble() * 0.9); // RR "irregularmente irregular"
        case Ritmo.flutterAtrial:
          _batimento(_proximo, 'N', _qrsNormal);
          _proximo += _rnd.nextDouble() < 0.75 ? 0.4 : 0.8; // condução 2:1 (150 bpm) ou 4:1
        case Ritmo.bloqueioRamo:
          _batimento(_proximo, 'N', _qrsRamo, pr: 0.17);
          _proximo += rr;
        case Ritmo.bloqueioAV2:
          // Wenckebach 4:3 — PR 0,16 → 0,26 → 0,36 s e a 4ª onda P fica sem QRS
          final pp = 60.0 / bpm;
          final pos = _contador % 4;
          if (pos == 3) {
            _soP(_proximo);
            _contador++;
          } else {
            final pr = 0.16 + 0.10 * pos;
            _batimento(_proximo + pr, 'N', _qrsNormal, pr: pr);
          }
          _proximo += pp;
        case Ritmo.bloqueioAVTotal:
          _batimento(_proximo, 'N', _qrsJuncional); // escape juncional a 40/min
          _proximo += 1.5 * (1 + (_rnd.nextDouble() - 0.5) * 0.02);
      }
    }
    if (_ritmo == Ritmo.bloqueioAVTotal) {
      while (_proximoP < t + 1.5) {
        _soP(_proximoP);
        _proximoP += 0.75; // átrios a 80/min, independentes
      }
    }
    _eventos.removeWhere((e) => e.fim < t - 1);
    if (_verdade.length > 2000) _verdade.removeRange(0, 1000);
  }

  int _amostra() {
    final t = _n / 100.0;
    _n++;
    _agendar(t);
    var mv = 0.08 * math.sin(2 * math.pi * 0.25 * t); // respiração / deriva da linha de base
    for (final e in _eventos) {
      for (final o in e.ondas) {
        final d = t - o.t;
        if (d.abs() < 5 * o.s) mv += o.a * math.exp(-d * d / (2 * o.s * o.s));
      }
    }
    if (_ritmo == Ritmo.fibrilacaoAtrial) {
      _fase += 2 * math.pi * (5.5 + _rnd.nextDouble()) / 100; // ondas f de 5-6,5 Hz, irregulares
      mv += 0.05 * math.sin(_fase) + 0.025 * math.sin(2.3 * _fase + 1);
    } else if (_ritmo == Ritmo.flutterAtrial) {
      final x = (t * 5) % 1.0; // 300/min, dente de serra negativo
      mv += x < 0.8 ? -0.18 * x / 0.8 + 0.06 : -0.12 + 0.18 * (x - 0.8) / 0.2;
    }
    final g = math.sqrt(-2 * math.log(1 - _rnd.nextDouble())) * math.cos(2 * math.pi * _rnd.nextDouble());
    mv += ruido * g;
    final volts = 1.5 + 0.4 * mv;
    return (volts / 3.3 * 4095).round().clamp(0, 4095);
  }
}
