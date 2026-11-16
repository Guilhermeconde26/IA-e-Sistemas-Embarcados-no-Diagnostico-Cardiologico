// Capturas de tela do app (fonte Roboto real, tamanho de celular) para conferir o visual.
// Rodar: flutter test test/capturas_test.dart --dart-define=CAPTURAS=pasta/de/saida
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ic_ecg/ble/ecg_ble.dart';
import 'package:ic_ecg/dados/banco.dart';
import 'package:ic_ecg/main.dart';
import 'package:ic_ecg/pipeline/modelo_rf.dart';
import 'package:ic_ecg/servicos/monitor.dart';
import 'package:ic_ecg/servicos/operador.dart';
import 'package:ic_ecg/servicos/simulador.dart';
import 'package:ic_ecg/telas/tela_abertura.dart';
import 'package:ic_ecg/ui/tema.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _saida = String.fromEnvironment('CAPTURAS');
// tamanho da tela em dp, ex.: --dart-define=TAMANHO=800x1280 (tablet em pé)
const _tamanho = String.fromEnvironment('TAMANHO', defaultValue: '390x844');
Size get _tela {
  final p = _tamanho.split('x').map(double.parse).toList();
  return Size(p[0] * 2, p[1] * 2);
}
final _raiz = GlobalKey();

Future<void> _fontes() async {
  final pasta = '${Platform.environment['FLUTTER_ROOT'] ?? 'C:/Users/USUARIO/dev/flutter'}/bin/cache/artifacts/material_fonts';
  ByteData ler(String f) => ByteData.view(File('$pasta/$f').readAsBytesSync().buffer);
  final roboto = FontLoader('Roboto');
  for (final f in ['roboto-regular', 'roboto-medium', 'roboto-bold', 'roboto-black']) {
    roboto.addFont(Future.value(ler('$f.ttf')));
  }
  await roboto.load();
  // ícones do Material (setas de menus/dropdowns) — sem isso aparecem como quadrados na captura
  await (FontLoader('MaterialIcons')..addFont(Future.value(ler('materialicons-regular.otf')))).load();
}

Future<void> _foto(WidgetTester tester, String nome) async {
  await tester.runAsync(() async {
    final ro = _raiz.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await ro.toImage(pixelRatio: 2);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$_saida/$nome.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> _esperar(WidgetTester tester, [int vezes = 5]) async {
  for (var i = 0; i < vezes; i++) {
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 120)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    if (_saida.isNotEmpty) await _fontes();
  });

  testWidgets('abertura', (tester) async {
    if (_saida.isEmpty) return;
    tester.view.physicalSize = _tela;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RepaintBoundary(
      key: _raiz,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: temaDeci(),
        home: TelaAbertura(carregar: () async {}, aoTerminar: () {}),
      ),
    ));
    var t = 0;
    for (final ms in [350, 950, 1450, 1800, 2150, 2700, 3300]) {
      await tester.pump(Duration(milliseconds: ms - t));
      t = ms;
      await _foto(tester, 'abertura_${ms.toString().padLeft(4, '0')}');
    }
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('telas', (tester) async {
    if (_saida.isEmpty) return;
    tester.view.physicalSize = _tela;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    late Servicos s;
    await tester.runAsync(() async {
      await databaseFactory.deleteDatabase('${await getDatabasesPath()}/icecg.db');
      final banco = await Banco.abrir();
      final modelo = ModeloRF.deJson(File('assets/modelo_rf.json').readAsStringSync());
      final op = await Operador.carregar();
      final ble = EcgBle();
      s = Servicos(banco: banco, modelo: modelo, ble: ble, monitor: Monitor(banco, modelo, ble), operador: op,
          child: RepaintBoundary(key: _raiz, child: const DeciApp()));
    });
    await tester.pumpWidget(s);
    await tester.pump(const Duration(milliseconds: 700));
    await _foto(tester, 'tela_1_inicio');

    // simulador: bigeminismo por 21 s
    await tester.tap(find.text('Simular arritmias'));
    await _esperar(tester);
    await tester.tap(find.text('Bigeminismo ventricular'));
    await tester.pump();
    await _foto(tester, 'tela_2_simulador_ritmos');
    await tester.scrollUntilVisible(find.text('Iniciar simulação'), 200, scrollable: find.byType(Scrollable).last);
    final iniciar = find.ancestor(of: find.text('Iniciar simulação'), matching: find.bySubtype<ButtonStyleButton>());
    tester.widget<ButtonStyleButton>(iniciar).onPressed!();
    await _passar(tester, 21);
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -900));
    await tester.pump();
    await _foto(tester, 'tela_3_simulador_resultado');
    await tester.pageBack();
    await _esperar(tester);

    // admin + medição simulada de 30 s
    s.operador.entrar('1234');
    await tester.pump();
    await tester.tap(find.text('Iniciar ECG'));
    await _esperar(tester);
    await _foto(tester, 'tela_4_nova_medicao');
    s.monitor.iniciarSimulador(ritmo: Ritmo.extrassistolesV);
    await tester.pump();
    await _passar(tester, 6);
    await _foto(tester, 'tela_4b_previa_sinal');
    await tester.enterText(find.widgetWithText(TextField, 'Nome completo'), 'Maria Silva');
    await tester.ensureVisible(find.text('30 s'));
    await tester.pump();
    await tester.tap(find.text('30 s'));
    await tester.pump();
    final comecar = find.ancestor(of: find.text('Iniciar ECG'), matching: find.bySubtype<ButtonStyleButton>());
    tester.widget<ButtonStyleButton>(comecar).onPressed!();
    await _esperar(tester);
    await _passar(tester, 31);
    await _foto(tester, 'tela_5_monitor_resumo');
    s.monitor.pararSimulador();
    await tester.pageBack();
    await _esperar(tester);

    await tester.tap(find.text('Resultados'));
    await _esperar(tester);
    await _foto(tester, 'tela_6_resultados');
    await tester.tap(find.text('ADM'));
    await _esperar(tester);
    await _foto(tester, 'tela_7_adm');
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -1100));
    await tester.pump();
    await _foto(tester, 'tela_8_adm_como_funciona');
  });
}

Future<void> _passar(WidgetTester tester, int segundos) async {
  for (var i = 0; i < segundos * 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (i % 10 == 0) await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 40)));
  }
  await _esperar(tester);
}
