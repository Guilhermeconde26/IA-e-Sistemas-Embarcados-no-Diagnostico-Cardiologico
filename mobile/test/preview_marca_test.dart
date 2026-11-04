// Gera uma folha de pré-visualização da identidade visual (personagem, morfose e ícones) em PNG.
// Rodar: flutter test test/preview_marca_test.dart --dart-define=PREVIEW=caminho/da/pasta
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ic_ecg/ui/deci_marca.dart';

const _pasta = String.fromEnvironment('PREVIEW');

Future<void> salvar(WidgetTester tester, GlobalKey chave, String nome) async {
  await tester.runAsync(() async {
    final ro = chave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await ro.toImage(pixelRatio: 2);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$_pasta/$nome.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  // flutter test test/preview_marca_test.dart --dart-define=ASSETS=assets/img  -> regenera deci-mascote.png
  testWidgets('gera o PNG do personagem (usado no PDF)', (tester) async {
    const destino = String.fromEnvironment('ASSETS');
    if (destino.isEmpty) return;
    tester.view.physicalSize = const Size(600, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final chave = GlobalKey();
    await tester.pumpWidget(Center(
      child: RepaintBoundary(
        key: chave,
        child: const SizedBox(width: 256, height: 256, child: CustomPaint(painter: _SemBrilho())),
      ),
    ));
    await tester.runAsync(() async {
      final ro = chave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await ro.toImage(pixelRatio: 2);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$destino/deci-mascote.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });

  testWidgets('folha de identidade visual', (tester) async {
    if (_pasta.isEmpty) return;
    tester.view.physicalSize = const Size(1200, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final chave = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: RepaintBoundary(
        key: chave,
        child: Container(
          color: DeciCores.creme,
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Mascote(tamanho: 300),
              const SizedBox(width: 30),
              for (final m in [0.25, 0.5, 0.75, 1.0])
                SizedBox(width: 190, height: 180, child: CustomPaint(painter: MascotePainter(morph: m, larguraEcg: 1.6))),
            ]),
            const SizedBox(height: 20),
            SizedBox(width: 600, height: 200, child: CustomPaint(painter: MascotePainter(morph: 1, larguraEcg: 2.4, pulso: .47))),
            const SizedBox(height: 20),
            Wrap(spacing: 18, runSpacing: 18, children: [
              for (final g in DeciGlifo.values)
                Column(mainAxisSize: MainAxisSize.min, children: [
                  DeciIcone(g, tamanho: 56, blob: true),
                  const SizedBox(height: 6),
                  DeciIcone(g, tamanho: 30),
                  const SizedBox(height: 4),
                  DeciIcone(g, tamanho: 40, blob: true, ativo: false),
                ]),
            ]),
          ]),
        ),
      ),
    ));
    await tester.pump();
    await salvar(tester, chave, 'folha_marca');
  });
}

class _SemBrilho extends CustomPainter {
  const _SemBrilho();
  @override
  void paint(Canvas canvas, Size size) => MascotePainter(brilho: false).paint(canvas, size);
  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
