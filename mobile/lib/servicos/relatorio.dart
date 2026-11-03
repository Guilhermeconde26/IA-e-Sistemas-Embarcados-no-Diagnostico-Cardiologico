// Monta os dados de uma sessão (usado na tela de relatório e no PDF).
import 'dart:convert';

import '../dados/banco.dart';
import '../pipeline/pipeline_ecg.dart' as pipe;

class MedicaoRelatorio {
  final Map<String, Object?> linha;
  final List<double> filtrado;
  final List<int> rpeaks;
  final Map<int, String> classes;
  MedicaoRelatorio(this.linha, this.filtrado, this.rpeaks, this.classes);
  int get id => linha['id'] as int;
  double? get bpm => (linha['bpm'] as num?)?.toDouble();
  String? get classe => linha['classe'] as String?;
  String? get erro => linha['erro'] as String?;
  double? get sdnn => linha['vfc'] == null ? null : ((jsonDecode(linha['vfc'] as String) as Map)['sdnn_ms'] as num?)?.toDouble();
}

class DadosRelatorio {
  final Map<String, Object?> sessao;
  final List<MedicaoRelatorio> medicoes;
  final Map<String, int> batimentosPorClasse;
  DadosRelatorio(this.sessao, this.medicoes, this.batimentosPorClasse);

  List<MedicaoRelatorio> get validas => medicoes.where((m) => m.erro == null).toList();
  double? get bpmMedio {
    final v = validas.map((m) => m.bpm).whereType<double>().toList();
    return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
  }

  double? get sdnnMedio {
    final v = validas.map((m) => m.sdnn).whereType<double>().toList();
    return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
  }

  int get totalBatimentos => batimentosPorClasse.values.fold(0, (a, b) => a + b);

  static Future<DadosRelatorio?> carregar(Banco banco, int sessaoId) async {
    final s = await banco.sessao(sessaoId);
    if (s == null) return null;
    final meds = <MedicaoRelatorio>[];
    final contagem = <String, int>{};
    for (final m in await banco.medicoesDaSessao(sessaoId)) {
      final sinal = (jsonDecode(m['sinal'] as String) as List).cast<int>();
      final volts = [for (final a in sinal) a * 3.3 / 4095];
      List<double> f;
      try {
        f = pipe.preparar(volts);
      } on pipe.ErroSinal {
        f = volts;
      }
      final bats = await banco.batimentos(m['id'] as int);
      final classes = <int, String>{};
      for (final b in bats) {
        final c = (b['true_label'] ?? b['pred_label']) as String?;
        if (c == null) continue;
        classes[b['r_sample'] as int] = c;
        contagem[c] = (contagem[c] ?? 0) + 1;
      }
      final rp = m['rpeaks'] == null ? <int>[] : (jsonDecode(m['rpeaks'] as String) as List).cast<int>();
      meds.add(MedicaoRelatorio(m, f, rp, classes));
    }
    return DadosRelatorio(s, meds, contagem);
  }
}
