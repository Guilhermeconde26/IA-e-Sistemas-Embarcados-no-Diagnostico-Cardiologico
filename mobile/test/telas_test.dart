// Abre o app num tamanho de celular e percorre o fluxo inteiro — falha se alguma tela estourar o
// layout ou lançar exceção: Início -> simulador de arritmias -> ADM (PIN) -> nova medição -> monitor
// -> resumo -> Resultados -> relatório.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ic_ecg/ble/ecg_ble.dart';
import 'package:ic_ecg/dados/banco.dart';
import 'package:ic_ecg/main.dart';
import 'package:ic_ecg/pipeline/modelo_rf.dart';
import 'package:ic_ecg/servicos/monitor.dart';
import 'package:ic_ecg/servicos/operador.dart';
import 'package:ic_ecg/telas/tela_adm.dart';
import 'package:ic_ecg/telas/tela_nova_medicao.dart';
import 'package:ic_ecg/telas/tela_relatorio.dart';
import 'package:ic_ecg/telas/tela_simulador.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // celular, tablet em pé e tablet deitado (este usa o menu lateral)
  for (final (nome, tela) in [
    ('celular', const Size(390, 844)),
    ('tablet', const Size(800, 1280)),
    ('tablet deitado', const Size(1280, 800)),
  ]) {
    testWidgets('fluxo completo ($nome)', (tester) async {
      tester.view.physicalSize = tela * 3;
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
        servicos = Servicos(
          banco: banco,
          modelo: modelo,
          ble: ble,
          monitor: Monitor(banco, modelo, ble),
          operador: op,
          child: const DeciApp(),
        );
      });
      await tester.pumpWidget(servicos);
      await _esperar(tester);

      // Início no modo paciente: botão de ECG, simulador e só duas abas
      expect(find.text('Iniciar ECG'), findsOneWidget);
      expect(find.text('Simular arritmias'), findsOneWidget);
      expect(find.text('Resultados'), findsNothing);
      _ok(tester, 'inicio');

      // Simulador independente: bigeminismo por 11 s
      await tester.tap(find.text('Simular arritmias'));
      await _esperar(tester);
      await tester.tap(find.text('Bigeminismo ventricular'));
      await tester.pump();
      _ok(tester, 'simulador aberto');
      await tester.scrollUntilVisible(find.text('Iniciar simulação'), 200, scrollable: _lista<TelaSimulador>());
      _acionar(tester, 'Iniciar simulação');
      await _passarTempo(tester, 11);
      await tester.scrollUntilVisible(
        find.text('Desempenho do modelo nesta simulação'),
        300,
        scrollable: _lista<TelaSimulador>(),
      );
      expect(find.textContaining('batimentos corretos'), findsOneWidget);
      _ok(tester, 'simulador rodando');
      await tester.pageBack();
      await _esperar(tester);

      // ADM: informações do projeto e criação do PIN
      await tester.tap(find.text('ADM'));
      await _esperar(tester);
      expect(find.text('Sobre o projeto'), findsOneWidget);
      _ok(tester, 'adm');
      expect(find.text('Guilherme Conde', skipOffstage: false), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '1234');
      await tester.tap(find.text('Criar PIN e entrar'));
      await _esperar(tester);
      expect(find.text('Resultados'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Dataset para treino'), 400, scrollable: _lista<TelaAdm>());

      // Nova medição com sinal simulado (atalho de admin), 30 s
      await tester.tap(find.text('Início'));
      await _esperar(tester);
      await tester.tap(find.text('Iniciar ECG'));
      await _esperar(tester);
      _acionar(tester, 'Sem ECG? Usar sinal simulado (admin)');
      await tester.pump();
      _ok(tester, 'nova medicao');
      // prévia do sinal antes de gravar: com o simulador limpo, deve dar "Sinal bom"
      expect(find.text('Conferir o sinal'), findsOneWidget);
      await _passarTempo(tester, 6);
      expect(find.text('Sinal bom'), findsOneWidget);
      expect(servicos.monitor.medindo, isFalse);
      _ok(tester, 'previa do sinal');
      await tester.enterText(find.widgetWithText(TextField, 'Nome completo'), 'Maria Teste');
      await tester.scrollUntilVisible(find.text('30 s'), 200, scrollable: _lista<TelaNovaMedicao>());
      await tester.ensureVisible(find.text('30 s'));
      await tester.pump();
      await tester.tap(find.text('30 s'));
      await tester.pump();
      _acionar(tester, 'Iniciar ECG');
      await _esperar(tester);
      expect(servicos.monitor.medindo, isTrue);
      expect(find.text('Monitor'), findsOneWidget);
      _ok(tester, 'monitor');

      await _passarTempo(tester, 31);
      expect(servicos.monitor.medindo, isFalse);
      expect(servicos.monitor.daSessao.length, 3);
      expect(servicos.monitor.daSessao.every((u) => u.erro == null && u.classe == 'N'), isTrue);
      expect(find.text('Medição concluída!'), findsOneWidget);
      _ok(tester, 'resumo');
      _acionar(tester, 'Concluir');
      await _esperar(tester);
      servicos.monitor.pararSimulador();

      // Resultados -> relatório
      await tester.tap(find.text('Resultados'));
      await _esperar(tester);
      expect(find.text('Maria Teste'), findsOneWidget);
      _ok(tester, 'resultados');
      await tester.tap(find.text('Maria Teste'));
      await _esperar(tester, 8);
      expect(find.text('Batimentos por classe'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Medições'), 300, scrollable: _lista<TelaRelatorio>());
      await _esperar(tester);
      expect(tester.takeException(), isNull);
    });
  }
}

/// Deixa o banco (que roda fora do relógio falso do teste) responder e redesenha.
Future<void> _esperar(WidgetTester tester, [int vezes = 5]) async {
  for (var i = 0; i < vezes; i++) {
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 120)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Avança o relógio do teste (o simulador gera 10 amostras a cada 100 ms).
Future<void> _passarTempo(WidgetTester tester, int segundos) async {
  for (var i = 0; i < segundos * 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (i % 10 == 0) await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 40)));
  }
  await _esperar(tester);
}

/// Aciona um botão pelo texto (sem depender de ele estar fora da barra de abas).
void _acionar(WidgetTester tester, String texto) {
  final f = find.ancestor(of: find.text(texto), matching: find.bySubtype<ButtonStyleButton>());
  tester.widget<ButtonStyleButton>(f.first).onPressed!();
}

/// A lista rolável de uma tela específica (há várias abas montadas ao mesmo tempo).
Finder _lista<T>() => find.descendant(of: find.byType(T), matching: find.byType(Scrollable)).first;

/// Falha já na etapa em que apareceu um erro de layout (para saber qual tela estourou).
void _ok(WidgetTester tester, String etapa) {
  final e = tester.takeException();
  if (e != null) fail('$etapa: ${e is FlutterError ? e.toStringDeep() : e}');
}
