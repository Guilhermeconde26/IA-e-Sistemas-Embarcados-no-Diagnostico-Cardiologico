// Calibração do avaliador de qualidade do sinal: dart run tool/calibrar_qualidade.dart
// ignore_for_file: avoid_print
import 'dart:math' as math;

import 'package:ic_ecg/pipeline/pipeline_ecg.dart' as pipe;
import 'package:ic_ecg/servicos/qualidade_sinal.dart';
import 'package:ic_ecg/servicos/simulador.dart';

/// Passa as amostras pelo mesmo filtro ao vivo do app e monta o buffer de 6 s.
(List<double>, int) buffer(List<int> amostras) {
  final f = pipe.FiltroAoVivo();
  final b = List<double>.filled(600, double.nan);
  var c = 0;
  for (final a in amostras) {
    b[c] = f.filtrar(a * 3.3 / 4095);
    c = (c + 1) % 600;
  }
  return (b, c);
}

String fmt(QualidadeSinal q) => '${q.nivel.name.padRight(8)} bpm=${q.bpm?.toStringAsFixed(0) ?? '--'} R=${q.alturaR?.toStringAsFixed(2) ?? '--'} ${q.mensagem}';

void main() {
  for (final ruido in [0.01, 0.03, 0.08, 0.12]) {
    print('== ruído $ruido');
    for (final r in Ritmo.values) {
      final s = SimuladorEcg(ritmo: r, ruido: ruido);
      final (b, c) = buffer(s.gerar(1200));
      print('  ${r.nome.padRight(40)} ${fmt(avaliarSinal(b, c))}');
    }
  }
  final rnd = math.Random(1);
  print('== sem ECG');
  final (b1, c1) = buffer(List.filled(1200, 2048));
  print('  linha reta: ${fmt(avaliarSinal(b1, c1))}');
  final (b2, c2) = buffer(List.generate(1200, (_) => 2048 + (rnd.nextDouble() * 400 - 200).round()));
  print('  ruído branco: ${fmt(avaliarSinal(b2, c2))}');
  final (b3, c3) = buffer(List.generate(1200, (i) => 2048 + (300 * math.sin(2 * math.pi * 50 * i / 100 + 0.3) + rnd.nextDouble() * 60).round()));
  print('  rede 50 Hz: ${fmt(avaliarSinal(b3, c3))}');
  final (b4, c4) = buffer(List.generate(1200, (i) => 2048 + (600 * math.sin(2 * math.pi * 0.3 * i / 100) + rnd.nextDouble() * 200).round()));
  print('  movimento+ruído: ${fmt(avaliarSinal(b4, c4))}');
  final (b5, c5) = buffer(List.generate(300, (_) => 2048));
  print('  3 s: ${fmt(avaliarSinal(b5, c5))}');
}
