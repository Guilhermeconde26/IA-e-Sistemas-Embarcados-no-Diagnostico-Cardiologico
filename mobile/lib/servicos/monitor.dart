// Estado central do app: fonte de sinal (BLE ou simulador), traçado ao vivo, sessão de medição
// em andamento e classificação de cada janela de 10 s.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ble/ecg_ble.dart';
import '../dados/banco.dart';
import '../pipeline/modelo_rf.dart';
import '../pipeline/pipeline_ecg.dart' as pipe;
import 'simulador.dart';

const int amostrasPorMedicao = 10 * pipe.fs; // 10 s, igual ao treino
const int amostrasNoMonitor = 6 * pipe.fs; // o traçado ao vivo mostra 6 s

class MedicaoClassificada {
  final int id;
  final List<double> filtrado;
  final List<int> rpeaks;
  final Map<int, String> classePorPico;
  final double? bpm;
  final String? classe;
  final Map<String, int> distribuicao;
  final String? erro;
  MedicaoClassificada(this.id, this.filtrado, this.rpeaks, this.classePorPico, this.bpm, this.classe,
      this.distribuicao, this.erro);
}

enum Fonte { nenhuma, ble, simulador }

class Monitor extends ChangeNotifier {
  Monitor(this.banco, this.modelo, this.ble) {
    ble.addListener(_aoMudarBle);
  }

  final Banco banco;
  final ModeloRF modelo;
  final EcgBle ble;

  // ---- fonte
  Fonte fonte = Fonte.nenhuma;
  StreamSubscription<List<int>>? _sub;
  SimuladorEcg? _sim;

  // ---- traçado ao vivo (buffer circular com varredura, como num monitor)
  final List<double> monitor = List<double>.filled(amostrasNoMonitor, double.nan);
  int cursor = 0;
  final _filtroVivo = pipe.FiltroAoVivo();
  double? bpmAoVivo;

  // ---- sessão
  Paciente? paciente;
  int? sessaoId;
  int medicoesPorSessao = 6;
  int medicoesFeitas = 0;
  final List<int> _bloco = [];
  MedicaoClassificada? ultima;
  final List<MedicaoClassificada> daSessao = [];
  String? aviso;

  bool get medindo => sessaoId != null;
  double get progressoBloco => _bloco.length / amostrasPorMedicao;
  String get nomeFonte => switch (fonte) {
        Fonte.ble => ble.nomeConectado ?? 'ECG',
        Fonte.simulador => 'Simulador',
        Fonte.nenhuma => '—',
      };

  void _aoMudarBle() {
    if (ble.conectado && fonte != Fonte.ble) {
      _usar(ble.amostras, Fonte.ble);
    } else if (!ble.conectado && fonte == Fonte.ble) {
      _soltarFonte();
      if (medindo) aviso = 'Conexão com o ECG perdida — a medição em andamento foi pausada.';
    }
    notifyListeners();
  }

  void _usar(Stream<List<int>> s, Fonte f) {
    _sub?.cancel();
    _filtroVivo.reiniciar();
    monitor.fillRange(0, monitor.length, double.nan);
    cursor = 0;
    _bloco.clear();
    fonte = f;
    _sub = s.listen(_aoReceber);
  }

  void _soltarFonte() {
    _sub?.cancel();
    _sub = null;
    _sim?.parar();
    _sim = null;
    fonte = Fonte.nenhuma;
    _bloco.clear();
  }

  // ---- simulador (modo administrador)
  void iniciarSimulador({double bpm = 72, double ruido = 0.03, bool extrassistoles = false}) {
    if (ble.conectado) ble.desconectar();
    _sim?.parar();
    _sim = SimuladorEcg(bpm: bpm, ruido: ruido, extrassistoles: extrassistoles);
    _usar(_sim!.iniciar(), Fonte.simulador);
    notifyListeners();
  }

  void pararSimulador() {
    if (fonte != Fonte.simulador) return;
    if (medindo) encerrarSessao();
    _soltarFonte();
    notifyListeners();
  }

  // ---- sessão
  Future<void> iniciarSessao(Paciente? p) async {
    paciente = p;
    sessaoId = await banco.novaSessao(fonte == Fonte.simulador ? 'simulador' : nomeFonte, p,
        simulada: fonte == Fonte.simulador);
    medicoesFeitas = 0;
    daSessao.clear();
    ultima = null;
    aviso = null;
    _bloco.clear();
    notifyListeners();
  }

  void encerrarSessao() {
    sessaoId = null;
    _bloco.clear();
    notifyListeners();
  }

  // ---- amostras chegando (a cada ~100 ms)
  int _desdeNotificar = 0;
  void _aoReceber(List<int> amostras) {
    for (final a in amostras) {
      final v = _filtroVivo.filtrar(a * 3.3 / 4095);
      monitor[cursor] = v;
      cursor = (cursor + 1) % monitor.length;
      if (medindo && !ble.eletrodoSolto) _bloco.add(a);
    }
    if (medindo && ble.eletrodoSolto && fonte == Fonte.ble) {
      _bloco.clear(); // janela com eletrodo solto não serve: recomeça
      aviso = 'Eletrodo solto — confira os eletrodos.';
    }
    if (medindo && _bloco.length >= amostrasPorMedicao) {
      final janela = List<int>.of(_bloco.take(amostrasPorMedicao));
      _bloco.removeRange(0, amostrasPorMedicao);
      _classificar(janela);
    }
    // redesenha a ~20 fps (2 pacotes)
    if (++_desdeNotificar >= 2) {
      _desdeNotificar = 0;
      notifyListeners();
    }
  }

  Future<void> _classificar(List<int> janela) async {
    final sid = sessaoId;
    if (sid == null) return;
    final volts = [for (final a in janela) a * 3.3 / 4095];
    MedicaoClassificada m;
    try {
      final r = pipe.processar(volts);
      final previsoes = [for (final f in r.features) modelo.prever(f)];
      final dist = <String, int>{};
      for (final p in previsoes) {
        dist[p.classe] = (dist[p.classe] ?? 0) + 1;
      }
      final classe = (dist.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
      final rrMedio = (r.rpeaks.last - r.rpeaks.first) / (r.rpeaks.length - 1) / pipe.fs;
      final bpm = (600 / rrMedio).round() / 10;
      bpmAoVivo = bpm;
      final id = await banco.salvarMedicao(
        sessionId: sid,
        sinal: janela,
        rpeaks: r.rpeaks,
        bpm: bpm,
        classe: classe,
        distribuicao: dist,
        vfc: pipe.metricasVfc(r.rpeaks),
        modelo: modelo.treinadoEm,
        batimentos: [
          for (var i = 0; i < r.usados.length; i++)
            (r: r.usados[i], f: r.features[i], classe: previsoes[i].classe, conf: previsoes[i].confianca),
        ],
      );
      m = MedicaoClassificada(id, r.filtrado, r.rpeaks,
          {for (var i = 0; i < r.usados.length; i++) r.usados[i]: previsoes[i].classe}, bpm, classe, dist, null);
      aviso = null;
    } on pipe.ErroSinal catch (e) {
      final id = await banco.salvarMedicao(sessionId: sid, sinal: janela, erro: e.mensagem);
      m = MedicaoClassificada(id, const [], const [], const {}, null, null, const {}, e.mensagem);
      aviso = '${e.mensagem} — confira os eletrodos e fique parado.';
    }
    ultima = m;
    daSessao.add(m);
    medicoesFeitas++;
    if (medicoesFeitas >= medicoesPorSessao) {
      sessaoId = null; // sessão completa
      aviso = null;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    ble.removeListener(_aoMudarBle);
    _soltarFonte();
    super.dispose();
  }
}
