// Avalia o sinal ao vivo antes da medição (feedback para posicionar os eletrodos): sem sinal,
// ruído, batimentos não detectados ou sinal bom — com a frequência aproximada.
import 'dart:math' as math;

import '../pipeline/pipeline_ecg.dart' as pipe;

enum NivelSinal { aguardando, ruim, regular, bom }

class QualidadeSinal {
  const QualidadeSinal(this.nivel, this.mensagem, {this.bpm, this.picos = 0, this.alturaR});
  final NivelSinal nivel;
  final String mensagem;
  final double? bpm;
  final int picos;
  final double? alturaR; // altura típica do R em desvios-padrão (diagnóstico)
}

/// [buffer] é o traçado ao vivo (circular, NaN = vazio) e [cursor] a próxima posição a ser escrita.
QualidadeSinal avaliarSinal(List<double> buffer, int cursor, {bool eletrodoSolto = false}) {
  if (eletrodoSolto) {
    return const QualidadeSinal(NivelSinal.ruim, 'Eletrodo solto — confira os três eletrodos e o cabo.');
  }
  // desenrola o buffer em ordem de tempo e fica só com o trecho já preenchido
  final x = <double>[
    for (var i = 0; i < buffer.length; i++) buffer[(cursor + i) % buffer.length],
  ].where((v) => !v.isNaN).toList();
  // os primeiros ~1,5 s depois de conectar ainda têm o transitório do filtro
  if (x.length < 4 * pipe.fs) {
    return const QualidadeSinal(NivelSinal.aguardando, 'Recebendo sinal… aguarde alguns segundos.');
  }
  final y = x.sublist(x.length >= 5 * pipe.fs ? x.length - 5 * pipe.fs : 0);

  final media = y.reduce((a, b) => a + b) / y.length;
  var s2 = 0.0;
  for (final v in y) {
    s2 += (v - media) * (v - media);
  }
  final dp = math.sqrt(s2 / y.length);
  if (dp < 2e-3) {
    // ~2 mV: abaixo disso é linha reta (eletrodo sem contato, cabo solto ou AD8232 saturado)
    return const QualidadeSinal(NivelSinal.ruim, 'Sem sinal (linha reta) — confira se os eletrodos estão colados e o cabo conectado.');
  }
  final z = [for (final v in y) (v - media) / dp];
  final picos = pipe.detectarPicos(z);
  if (picos.length < 3) {
    return QualidadeSinal(NivelSinal.ruim, 'Batimentos não detectados — ajuste a posição dos eletrodos.', picos: picos.length);
  }

  final rr = [for (var i = 1; i < picos.length; i++) (picos[i] - picos[i - 1]) / pipe.fs];
  final rrOrd = List<double>.of(rr)..sort();
  final bpm = 60 / rrOrd[rrOrd.length ~/ 2];
  // altura típica do pico R em desvios-padrão: num ECG limpo o R se destaca bem; no ruído, não.
  // Calibrado com tool/calibrar_qualidade.dart: ECG simulado (todos os ritmos) >= 2,9; ruído sem ECG <= 2,2.
  // (em módulo, perto do pico: extrassístoles ventriculares costumam ter o QRS para baixo)
  double altura(int p) {
    var m = 0.0;
    for (var k = math.max(0, p - 5); k <= math.min(z.length - 1, p + 5); k++) {
      m = math.max(m, z[k].abs());
    }
    return m;
  }

  final alturas = [for (final p in picos) altura(p)]..sort();
  final alturaR = alturas[alturas.length ~/ 2];

  if (bpm < 30 || bpm > 220) {
    return QualidadeSinal(NivelSinal.ruim, 'Frequência fora do esperado — o sinal parece ser ruído. Confira os eletrodos.',
        bpm: bpm, picos: picos.length, alturaR: alturaR);
  }
  if (alturaR < 2.4) {
    return QualidadeSinal(NivelSinal.ruim,
        'Sinal com muito ruído — confira os eletrodos e peça para o paciente ficar parado e relaxado.',
        bpm: bpm, picos: picos.length, alturaR: alturaR);
  }
  // ritmo irregular NÃO conta como sinal ruim: pode ser justamente a arritmia que queremos medir
  if (alturaR < 2.8) {
    return QualidadeSinal(NivelSinal.regular,
        'Sinal aceitável, mas com interferência. Se possível, peça para o paciente ficar parado.',
        bpm: bpm, picos: picos.length, alturaR: alturaR);
  }
  return QualidadeSinal(NivelSinal.bom, 'Sinal bom — pode iniciar a medição.', bpm: bpm, picos: picos.length, alturaR: alturaR);
}
