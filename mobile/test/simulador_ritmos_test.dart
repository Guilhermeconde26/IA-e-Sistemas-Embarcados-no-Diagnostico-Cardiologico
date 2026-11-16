// Para cada ritmo do simulador: 2 min de sinal -> pipeline -> modelo, comparando com a classe verdadeira.
// Com --dart-define=CAPTURAS=pasta também desenha uma folha com 8 s de cada ritmo.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ic_ecg/pipeline/modelo_rf.dart';
import 'package:ic_ecg/pipeline/pipeline_ecg.dart';
import 'package:ic_ecg/servicos/simulador.dart';
import 'package:ic_ecg/ui/grafico_ecg.dart';

const _saida = String.fromEnvironment('CAPTURAS');

/// Compara os picos detectados com os batimentos verdadeiros (tolerância de 100 ms).
({int total, int acertos, Map<String, Map<String, int>> confusao, int perdidos}) avaliar(
    ModeloRF modelo, Ritmo ritmo, {int janelas = 12}) {
  final sim = SimuladorEcg(ritmo: ritmo, ruido: 0.02);
  final confusao = <String, Map<String, int>>{};
  var total = 0, acertos = 0, perdidos = 0;
  for (var j = 0; j < janelas; j++) {
    final r = processar([for (final a in sim.gerar(1000)) a * 3.3 / 4095]);
    final verdade = sim.batimentos.where((b) => b.t >= j * 10 + 0.35 && b.t < (j + 1) * 10 - 0.45).toList();
    for (final b in verdade) {
      final rel = (b.t - j * 10) * fs;
      final i = r.usados.indexWhere((u) => (u - rel).abs() <= 10);
      if (i < 0) {
        perdidos++;
        continue;
      }
      final prev = modelo.prever(r.features[i]).classe;
      (confusao[b.classe] ??= {})[prev] = (confusao[b.classe]![prev] ?? 0) + 1;
      total++;
      if (prev == b.classe) acertos++;
    }
  }
  return (total: total, acertos: acertos, confusao: confusao, perdidos: perdidos);
}

void main() {
  final modelo = ModeloRF.deJson(File('assets/modelo_rf.json').readAsStringSync());

  test('todos os ritmos geram sinal processável e o modelo é medido', () {
    final linhas = <String>[];
    for (final ritmo in Ritmo.values) {
      final a = avaliar(modelo, ritmo);
      expect(a.total, greaterThan(40), reason: '${ritmo.nome}: poucos batimentos avaliados');
      final porClasse = a.confusao.entries.map((e) {
        final certo = e.value[e.key] ?? 0;
        final n = e.value.values.fold(0, (x, y) => x + y);
        return '${e.key} $certo/$n';
      }).join('  ');
      linhas.add('${ritmo.nome.padRight(40)} acerto ${(100 * a.acertos / a.total).toStringAsFixed(0).padLeft(3)}%'
          '  | $porClasse | não detectados: ${a.perdidos}');
    }
    // ignore: avoid_print
    print(linhas.join('\n'));
  });

  test('extrassístoles ventriculares e bigeminismo: V detectado', () {
    for (final ritmo in [Ritmo.extrassistolesV, Ritmo.bigeminismo, Ritmo.trigeminismo]) {
      final a = avaliar(modelo, ritmo);
      final v = a.confusao['V']!;
      expect((v['V'] ?? 0) / v.values.fold(0, (x, y) => x + y), greaterThan(0.8), reason: ritmo.nome);
      final n = a.confusao['N']!;
      expect((n['N'] ?? 0) / n.values.fold(0, (x, y) => x + y), greaterThan(0.9), reason: ritmo.nome);
    }
  });

  testWidgets('folha com 8 s de cada ritmo', (tester) async {
    if (_saida.isEmpty) return;
    tester.view.physicalSize = const Size(1100, 2300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final chave = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: RepaintBoundary(
        key: chave,
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.all(10),
          child: Column(children: [
            for (final r in Ritmo.values)
              SizedBox(
                height: 150,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.nome, style: const TextStyle(fontSize: 12)),
                  Expanded(
                    child: GraficoEcg(
                      sinal: [
                        for (final a in (SimuladorEcg(ritmo: r, ruido: 0.01)..gerar(150)).gerar(800)) a * 3.3 / 4095,
                      ],
                      rotulos: false,
                      altura: 130,
                    ),
                  ),
                ]),
              ),
          ]),
        ),
      ),
    ));
    await tester.runAsync(() async {
      final ro = chave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await ro.toImage();
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$_saida/ritmos.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });
}
