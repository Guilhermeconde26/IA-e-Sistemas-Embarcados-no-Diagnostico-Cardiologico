// Simulador -> pipeline -> modelo, tudo em Dart, como o app faz com o sinal do ESP.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ic_ecg/pipeline/modelo_rf.dart';
import 'package:ic_ecg/pipeline/pipeline_ecg.dart';
import 'package:ic_ecg/servicos/simulador.dart';

void main() {
  final modelo = ModeloRF.deJson(File('assets/modelo_rf.json').readAsStringSync());
  List<double> volts(List<int> adc) => [for (final a in adc) a * 3.3 / 4095];

  for (final bpm in [50.0, 72.0, 110.0, 150.0]) {
    test('ECG normal a ${bpm.round()} bpm: batimentos N e BPM correto', () {
      final sim = SimuladorEcg(bpm: bpm, ruido: 0.03);
      var n = 0, total = 0;
      final bpms = <double>[];
      for (var janela = 0; janela < 6; janela++) {
        final r = processar(volts(sim.gerar(1000)));
        for (final f in r.features) {
          total++;
          if (modelo.prever(f).classe == 'N') n++;
        }
        bpms.add(60 / ((r.rpeaks.last - r.rpeaks.first) / (r.rpeaks.length - 1) / fs));
      }
      final media = bpms.reduce((a, b) => a + b) / bpms.length;
      expect(n / total, greaterThan(0.9), reason: '$n de $total batimentos classificados como N');
      expect((media - bpm).abs(), lessThan(bpm * 0.05), reason: 'BPM medido $media');
    });
  }

  test('extrassístoles ventriculares: a maioria é marcada como não-normal', () {
    final sim = SimuladorEcg(bpm: 72, ruido: 0.02, extrassistoles: true);
    var acertos = 0, pvcs = 0, falsos = 0, normais = 0;
    for (var janela = 0; janela < 12; janela++) {
      final inicio = janela * 10.0;
      final r = processar(volts(sim.gerar(1000)));
      final pvcTempos = sim.temposVentriculares.where((t) => t >= inicio && t < inicio + 10).map((t) => t - inicio);
      for (var i = 0; i < r.usados.length; i++) {
        final t = r.usados[i] / fs;
        final ehPvc = pvcTempos.any((p) => (p - t).abs() < 0.1);
        final c = modelo.prever(r.features[i]).classe;
        if (ehPvc) {
          pvcs++;
          if (c != 'N') acertos++;
        } else {
          normais++;
          if (c != 'N') falsos++;
        }
      }
    }
    // ignore: avoid_print
    print('Extrassístoles: $acertos/$pvcs detectadas · falsos alarmes em normais: $falsos/$normais');
    expect(pvcs, greaterThan(5));
    expect(falsos / normais, lessThan(0.1));
  });
}
