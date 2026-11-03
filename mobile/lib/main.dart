import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ble/ecg_ble.dart';
import 'dados/banco.dart';
import 'pipeline/modelo_rf.dart';
import 'servicos/monitor.dart';
import 'servicos/operador.dart';
import 'telas/tela_medicao.dart';
import 'telas/tela_operador.dart';
import 'telas/tela_resultados.dart';
import 'ui/tema.dart';

/// Serviços do app, acessíveis em qualquer tela com Servicos.of(context).
class Servicos extends InheritedWidget {
  const Servicos({super.key, required this.banco, required this.modelo, required this.ble, required this.monitor,
      required this.operador, required super.child});
  final Banco banco;
  final ModeloRF modelo;
  final EcgBle ble;
  final Monitor monitor;
  final Operador operador;

  static Servicos of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<Servicos>()!;
  @override
  bool updateShouldNotify(Servicos old) => false;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final banco = await Banco.abrir();
  final modelo = ModeloRF.deJson(await rootBundle.loadString('assets/modelo_rf.json'));
  final operador = await Operador.carregar();
  final ble = EcgBle();
  final monitor = Monitor(banco, modelo, ble)..medicoesPorSessao = operador.medicoesPorSessao;
  runApp(Servicos(banco: banco, modelo: modelo, ble: ble, monitor: monitor, operador: operador, child: const IcEcgApp()));
}

class IcEcgApp extends StatelessWidget {
  const IcEcgApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'IC ECG',
        debugShowCheckedModeBanner: false,
        theme: temaIcEcg(),
        home: const Inicio(),
      );
}

class Inicio extends StatefulWidget {
  const Inicio({super.key});
  @override
  State<Inicio> createState() => _InicioState();
}

class _InicioState extends State<Inicio> {
  String _aba = 'Medição'; // pela etiqueta: as abas mudam ao entrar/sair do modo admin

  @override
  Widget build(BuildContext context) {
    final op = Servicos.of(context).operador;
    return ListenableBuilder(
      listenable: op,
      builder: (context, _) {
        // modo paciente: só Medição e Operador
        final abas = [
          (const TelaMedicao(), const NavigationDestination(icon: Icon(Icons.monitor_heart_outlined),
              selectedIcon: Icon(Icons.monitor_heart), label: 'Medição')),
          if (op.admin)
            (const TelaResultados(), const NavigationDestination(icon: Icon(Icons.folder_outlined),
                selectedIcon: Icon(Icons.folder), label: 'Resultados')),
          (const TelaOperador(), const NavigationDestination(icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person), label: 'Operador')),
        ];
        final i = abas.indexWhere((a) => a.$2.label == _aba);
        final aba = i < 0 ? 0 : i;
        return Scaffold(
          body: IndexedStack(index: aba, children: [for (final a in abas) a.$1]),
          bottomNavigationBar: NavigationBar(
            selectedIndex: aba,
            onDestinationSelected: (i) => setState(() => _aba = abas[i].$2.label),
            destinations: [for (final a in abas) a.$2],
          ),
        );
      },
    );
  }
}
