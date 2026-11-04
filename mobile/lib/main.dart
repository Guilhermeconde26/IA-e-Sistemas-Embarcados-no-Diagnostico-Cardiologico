import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ble/ecg_ble.dart';
import 'dados/banco.dart';
import 'pipeline/modelo_rf.dart';
import 'servicos/monitor.dart';
import 'servicos/operador.dart';
import 'telas/tela_abertura.dart';
import 'telas/tela_medicao.dart';
import 'telas/tela_operador.dart';
import 'telas/tela_resultados.dart';
import 'ui/deci_marca.dart';
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

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DeciRaiz());
}

/// Mostra a abertura animada enquanto carrega banco, modelo e preferências; depois abre o app.
class DeciRaiz extends StatefulWidget {
  const DeciRaiz({super.key});
  @override
  State<DeciRaiz> createState() => _DeciRaizState();
}

class _DeciRaizState extends State<DeciRaiz> {
  Servicos? _servicos;
  bool _pronto = false;

  Future<void> _carregar() async {
    final banco = await Banco.abrir();
    final modelo = ModeloRF.deJson(await rootBundle.loadString('assets/modelo_rf.json'));
    final operador = await Operador.carregar();
    final ble = EcgBle();
    final monitor = Monitor(banco, modelo, ble)..medicoesPorSessao = operador.medicoesPorSessao;
    _servicos = Servicos(banco: banco, modelo: modelo, ble: ble, monitor: monitor, operador: operador, child: const DeciApp());
  }

  @override
  Widget build(BuildContext context) {
    if (_pronto && _servicos != null) return _servicos!;
    return MaterialApp(
      title: 'DECI',
      debugShowCheckedModeBanner: false,
      theme: temaDeci(),
      home: TelaAbertura(carregar: _carregar, aoTerminar: () => setState(() => _pronto = true)),
    );
  }
}

class DeciApp extends StatelessWidget {
  const DeciApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'DECI',
        debugShowCheckedModeBanner: false,
        theme: temaDeci(),
        // entra suavemente depois da abertura
        home: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 450),
          builder: (_, v, child) => Opacity(opacity: v, child: child),
          child: const Inicio(),
        ),
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
          (const TelaMedicao(), const NavigationDestination(icon: DeciIcone(DeciGlifo.ecg, tamanho: 34, blob: true, ativo: false),
              selectedIcon: DeciIcone(DeciGlifo.ecg, tamanho: 34, blob: true), label: 'Medição')),
          if (op.admin)
            (const TelaResultados(), const NavigationDestination(icon: DeciIcone(DeciGlifo.pasta, tamanho: 34, blob: true, ativo: false),
                selectedIcon: DeciIcone(DeciGlifo.pasta, tamanho: 34, blob: true), label: 'Resultados')),
          (const TelaOperador(), const NavigationDestination(icon: DeciIcone(DeciGlifo.pessoa, tamanho: 34, blob: true, ativo: false),
              selectedIcon: DeciIcone(DeciGlifo.pessoa, tamanho: 34, blob: true), label: 'Operador')),
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
