// Simulação independente (tela "Simular arritmias"): gera o ritmo escolhido, classifica cada janela
// de 10 s e compara com a classe verdadeira de cada batimento. Não grava nada e não usa o Bluetooth.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../pipeline/modelo_rf.dart';
import '../pipeline/pipeline_ecg.dart' as pipe;
import 'simulador.dart';

class JanelaSimulada {
  final List<double> filtrado;
  final List<int> rpeaks;
  final Map<int, String> previsto; // pico -> classe prevista
  final Map<int, String> verdade; // pico -> classe verdadeira (quando o pico casa com um batimento simulado)
  final double? bpm;
  final double? cvRR; // coeficiente de variação do RR (irregularidade do ritmo)
  final String? erro;
  JanelaSimulada(this.filtrado, this.rpeaks, this.previsto, this.verdade, this.bpm, this.cvRR, this.erro);
  Set<int> get errados => {for (final e in previsto.entries) if (verdade[e.key] != null && verdade[e.key] != e.value) e.key};
}

class Simulacao extends ChangeNotifier {
  Simulacao(this.modelo);
  final ModeloRF modelo;

  Ritmo ritmo = Ritmo.normal;
  double bpm = Ritmo.normal.bpmPadrao;
  double ruido = 0.03;

  SimuladorEcg? _sim;
  StreamSubscription<List<int>>? _sub;
  bool get rodando => _sub != null;

  static const _noMonitor = 600;
  final List<double> monitor = List<double>.filled(_noMonitor, double.nan);
  int cursor = 0;
  final _filtro = pipe.FiltroAoVivo();
  final List<int> _bloco = [];
  int _janelas = 0;
  double get progresso => _bloco.length / 1000;

  JanelaSimulada? ultima;
  // verdade -> previsto -> contagem (acumulado desde o início)
  final Map<String, Map<String, int>> confusao = {};
  int get total => confusao.values.fold(0, (a, m) => a + m.values.fold(0, (x, y) => x + y));
  int get acertos => confusao.entries.fold(0, (a, e) => a + (e.value[e.key] ?? 0));

  void escolher(Ritmo r) {
    ritmo = r;
    if (r.usaBpm) bpm = r.bpmPadrao;
    if (rodando) iniciar();
    notifyListeners();
  }

  void ajustar({double? bpm, double? ruido}) {
    if (bpm != null) this.bpm = bpm;
    if (ruido != null) this.ruido = ruido;
    notifyListeners();
  }

  /// Reinicia a simulação com os parâmetros atuais (zera as estatísticas).
  void iniciar() {
    parar(notificar: false);
    _sim = SimuladorEcg(ritmo: ritmo, bpm: ritmo.usaBpm ? bpm : null, ruido: ruido);
    monitor.fillRange(0, monitor.length, double.nan);
    cursor = 0;
    _filtro.reiniciar();
    _bloco.clear();
    _janelas = 0;
    ultima = null;
    confusao.clear();
    _sub = _sim!.iniciar().listen(_receber);
    notifyListeners();
  }

  void parar({bool notificar = true}) {
    _sub?.cancel();
    _sub = null;
    _sim?.parar();
    _sim = null;
    if (notificar) notifyListeners();
  }

  void _receber(List<int> amostras) {
    for (final a in amostras) {
      monitor[cursor] = _filtro.filtrar(a * 3.3 / 4095);
      cursor = (cursor + 1) % monitor.length;
      _bloco.add(a);
    }
    if (_bloco.length >= 1000) {
      _classificar(List<int>.of(_bloco.take(1000)));
      _bloco.removeRange(0, 1000);
    }
    notifyListeners();
  }

  void _classificar(List<int> janela) {
    final inicio = _janelas * 10.0;
    _janelas++;
    try {
      final r = pipe.processar([for (final a in janela) a * 3.3 / 4095]);
      final previsto = <int, String>{};
      final verdade = <int, String>{};
      final reais = _sim?.batimentos.where((b) => b.t >= inicio && b.t < inicio + 10).toList() ?? const [];
      for (var i = 0; i < r.usados.length; i++) {
        final pico = r.usados[i];
        final c = modelo.prever(r.features[i]).classe;
        previsto[pico] = c;
        final t = inicio + pico / pipe.fs;
        BatimentoSimulado? par;
        for (final b in reais) {
          if ((b.t - t).abs() <= 0.1) par = b;
        }
        if (par != null) {
          verdade[pico] = par.classe;
          (confusao[par.classe] ??= {})[c] = (confusao[par.classe]![c] ?? 0) + 1;
        }
      }
      final rr = [for (var i = 1; i < r.rpeaks.length; i++) (r.rpeaks[i] - r.rpeaks[i - 1]) / pipe.fs];
      final media = rr.reduce((a, b) => a + b) / rr.length;
      final dp = math.sqrt(rr.map((v) => (v - media) * (v - media)).reduce((a, b) => a + b) / rr.length);
      ultima = JanelaSimulada(r.filtrado, r.rpeaks, previsto, verdade, 60 / media, dp / media, null);
    } on pipe.ErroSinal catch (e) {
      ultima = JanelaSimulada(const [], const [], const {}, const {}, null, null, e.mensagem);
    }
  }

  @override
  void dispose() {
    parar(notificar: false);
    super.dispose();
  }
}
