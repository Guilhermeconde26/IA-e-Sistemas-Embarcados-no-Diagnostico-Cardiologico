// Abre o app num tamanho de celular, passa pelas abas, entra como admin, liga o simulador e
// faz uma medição de 10 s — falha se alguma tela estourar o layout ou lançar exceção.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ic_ecg/ble/ecg_ble.dart';
import 'package:ic_ecg/dados/banco.dart';
import 'package:ic_ecg/main.dart';
import 'package:ic_ecg/pipeline/modelo_rf.dart';
import 'package:ic_ecg/servicos/monitor.dart';
import 'package:ic_ecg/servicos/operador.dart';
import 'package:ic_ecg/telas/tela_operador.dart';
import 'package:ic_ecg/telas/tela_relatorio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  testWidgets('fluxo completo nas três abas', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});

    late Servicos servicos;
    await tester.runAsync(() async {
      await databaseFactory.deleteDatabase('${await getDatabasesPath()}/icecg.db');
      final banco = await Banco.abrir();
      final modelo = ModeloRF.deJson(File('assets/modelo_rf.json').readAsStringSync());
      final op = await Operador.carregar();
      final ble = EcgBle();
      servicos = Servicos(banco: banco, modelo: modelo, ble: ble, monitor: Monitor(banco, modelo, ble), operador: op,
          child: const DeciApp());
    });
    await tester.pumpWidget(servicos);
    await tester.pump();

    // Modo paciente: só Medição e Operador
    expect(find.text('Resultados'), findsNothing);
    expect(find.text('Procurar ECG'), findsOneWidget);

    // Operador -> cria PIN e entra como admin
    await tester.tap(find.text('Operador'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '1234');
    await tester.tap(find.text('Criar PIN e entrar'));
    await _esperar(tester);
    expect(find.text('Resultados'), findsOneWidget);

    // Liga o simulador
    await tester.scrollUntilVisible(find.text('Ligar simulador'), 300, scrollable: _lista<TelaOperador>());
    // o botão fica rente à barra de abas; aciona direto (o objetivo aqui é o fluxo e o layout)
    tester.widget<ButtonStyleButton>(find.ancestor(of: find.text('Ligar simulador'),
        matching: find.bySubtype<ButtonStyleButton>())).onPressed!();
    await tester.pump();
    expect(servicos.monitor.fonte, Fonte.simulador);

    // Medição: identifica o paciente e mede 10 s
    await tester.tap(find.text('Medição'));
    await _esperar(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Nome completo'), 'Maria Teste');
    await tester.tap(find.text('Iniciar medição'));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    expect(servicos.monitor.medindo, isTrue);
    for (var i = 0; i < 110; i++) {
      await tester.pump(const Duration(milliseconds: 100)); // 11 s de sinal simulado
      if (i % 10 == 0) await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
    }
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 500)));
    await tester.pump();
    expect(servicos.monitor.ultima, isNotNull, reason: 'a primeira medição de 10 s deveria ter sido classificada');
    expect(servicos.monitor.ultima!.erro, isNull);
    expect(servicos.monitor.ultima!.classe, 'N');
    expect(find.text('Última medição (10 s)'), findsOneWidget);

    // Resultados: a sessão aparece; abre o relatório
    servicos.monitor.pararSimulador();
    await tester.tap(find.text('Resultados'));
    await _esperar(tester);
    expect(find.text('Maria Teste'), findsOneWidget);
    await tester.tap(find.text('Maria Teste'));
    await _esperar(tester);
    expect(find.text('Batimentos por classe'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Medições'), 300, scrollable: _lista<TelaRelatorio>());
    await _esperar(tester);
    expect(tester.takeException(), isNull);
  });
}

/// Deixa o banco (que roda fora do relógio falso do teste) responder e redesenha.
Future<void> _esperar(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 120)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// A lista rolável de uma tela específica (há várias abas montadas ao mesmo tempo).
Finder _lista<T>() => find.descendant(of: find.byType(T), matching: find.byType(Scrollable)).first;
