import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ble/ecg_ble.dart';
import 'dados/banco.dart';
import 'pipeline/modelo_rf.dart';
import 'servicos/monitor.dart';
import 'servicos/operador.dart';
import 'telas/tela_abertura.dart';
import 'telas/tela_adm.dart';
import 'telas/tela_inicio.dart';
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
  String _aba = 'Início'; // pela etiqueta: as abas mudam ao entrar/sair do modo admin

  @override
  Widget build(BuildContext context) {
    final op = Servicos.of(context).operador;
    return ListenableBuilder(
      listenable: op,
      builder: (context, _) {
        // modo paciente: só Início e ADM
        final abas = [
          (const TelaInicio(), const NavigationDestination(icon: DeciIcone(DeciGlifo.casa, tamanho: 34, blob: true, ativo: false),
              selectedIcon: DeciIcone(DeciGlifo.casa, tamanho: 34, blob: true), label: 'Início')),
          if (op.admin)
            (const TelaResultados(), const NavigationDestination(icon: DeciIcone(DeciGlifo.pasta, tamanho: 34, blob: true, ativo: false),
                selectedIcon: DeciIcone(DeciGlifo.pasta, tamanho: 34, blob: true), label: 'Resultados')),
          (const TelaAdm(), const NavigationDestination(icon: DeciIcone(DeciGlifo.pessoa, tamanho: 34, blob: true, ativo: false),
              selectedIcon: DeciIcone(DeciGlifo.pessoa, tamanho: 34, blob: true), label: 'ADM')),
        ];
        final i = abas.indexWhere((a) => a.$2.label == _aba);
        final aba = i < 0 ? 0 : i;
        final telas = IndexedStack(index: aba, children: [for (final a in abas) a.$1]);
        void escolher(int i) => setState(() => _aba = abas[i].$2.label);
        // tela larga (tablet deitado): menu na lateral em vez da barra de baixo
        if (MediaQuery.sizeOf(context).width >= 840) {
          return Scaffold(
            body: Row(children: [
              SafeArea(
                right: false,
                child: NavigationRail(
                  selectedIndex: aba,
                  onDestinationSelected: escolher,
                  labelType: NavigationRailLabelType.all,
                  backgroundColor: Colors.white,
                  indicatorColor: Colors.transparent,
                  groupAlignment: 0,
                  minWidth: 96,
                  selectedLabelTextStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Cores.destaqueEscuro),
                  unselectedLabelTextStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Cores.suave),
                  destinations: [
                    for (final a in abas)
                      NavigationRailDestination(icon: a.$2.icon, selectedIcon: a.$2.selectedIcon, label: Text(a.$2.label)),
                  ],
                ),
              ),
              const VerticalDivider(width: 1, thickness: 1, color: Cores.linha),
              Expanded(child: telas),
            ]),
          );
        }
        return Scaffold(
          body: telas,
          bottomNavigationBar: NavigationBar(
            selectedIndex: aba,
            onDestinationSelected: escolher,
            destinations: [for (final a in abas) a.$2],
          ),
        );
      },
    );
  }
}
