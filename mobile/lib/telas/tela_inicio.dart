// Tela inicial: um botão redondo grande para começar o ECG e o acesso ao simulador de arritmias.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../main.dart';
import '../ui/cabecalho.dart';
import '../ui/deci_marca.dart';
import '../ui/tema.dart';
import 'tela_monitor.dart';
import 'tela_nova_medicao.dart';
import 'tela_simulador.dart';

class TelaInicio extends StatelessWidget {
  const TelaInicio({super.key});

  @override
  Widget build(BuildContext context) {
    final m = Servicos.of(context).monitor;
    return Scaffold(
      appBar: AppBar(titleSpacing: 16, title: const MarcaDeci(), actions: const [PilulaEcg()]),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: m,
          builder: (context, _) => LayoutBuilder(
            builder: (context, lim) => SingleChildScrollView(
              child: ConstrainedBox(
                // ocupa a tela toda para o conteúdo ficar centralizado também no tablet
                constraints: BoxConstraints(minHeight: lim.maxHeight, minWidth: lim.maxWidth),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(m.medindo ? 'Medição em andamento' : 'Pronto para medir?',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Cores.texto)),
                    const SizedBox(height: 6),
                    Text(
                      m.medindo
                          ? 'Toque no botão para voltar ao monitor.'
                          : 'Toque no botão para conectar o ECG\ne identificar o paciente.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Cores.suave, fontSize: 14.5, height: 1.35),
                    ),
                    const SizedBox(height: 34),
                    BotaoEcg(
                      // cresce em telas grandes, sem passar da altura disponível
                      diametro: math.min(lim.biggest.shortestSide * 0.45, lim.maxHeight * 0.36).clamp(170.0, 320.0),
                      rotulo: m.medindo ? 'Ver medição' : 'Iniciar ECG',
                      aoTocar: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => m.medindo ? const TelaMonitor() : const TelaNovaMedicao())),
                    ),
                    const SizedBox(height: 40),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TelaSimulador())),
                      icon: const DeciIcone(DeciGlifo.simulador, tamanho: 22),
                      label: const Text('Simular arritmias'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(230, 52),
                        backgroundColor: Colors.white,
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text('Teste o app sem o ECG, com ritmos normais e arritmias.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Cores.suave, fontSize: 12.5)),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Botão redondo grande com o traçado de ECG e um halo que "respira".
class BotaoEcg extends StatefulWidget {
  const BotaoEcg({super.key, required this.rotulo, required this.aoTocar, this.diametro = 210});
  final String rotulo;
  final VoidCallback aoTocar;
  final double diametro;
  @override
  State<BotaoEcg> createState() => _BotaoEcgState();
}

class _BotaoEcgState extends State<BotaoEcg> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
    ..repeat();
  bool _pressionado = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.diametro;
    return Semantics(
      button: true,
      label: widget.rotulo,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressionado = true),
        onTapCancel: () => setState(() => _pressionado = false),
        onTapUp: (_) => setState(() => _pressionado = false),
        onTap: widget.aoTocar,
        child: AnimatedScale(
          scale: _pressionado ? 0.95 : 1,
          duration: const Duration(milliseconds: 120),
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final v = _c.value;
              return SizedBox(
                width: d * 1.35,
                height: d * 1.35,
                child: CustomPaint(
                  painter: _PintorBotao(v),
                  child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(
                        width: d * 0.62,
                        height: d * 0.32,
                        child: CustomPaint(painter: _TracoBotao(v)),
                      ),
                      const SizedBox(height: 10),
                      Text(widget.rotulo,
                          style: TextStyle(
                              color: Colors.white, fontSize: 18 * d / 210, fontWeight: FontWeight.w800, letterSpacing: .3)),
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PintorBotao extends CustomPainter {
  _PintorBotao(this.v);
  final double v;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 1.35 / 2;
    // ondas que se espalham, como um pulso
    for (final atraso in [0.0, 0.5]) {
      final f = (v + atraso) % 1.0;
      canvas.drawCircle(
        c,
        r * (1 + 0.32 * f),
        Paint()..color = DeciCores.coral.withValues(alpha: 0.18 * (1 - f)),
      );
    }
    canvas.drawCircle(c, r * 1.02, Paint()
      ..color = DeciCores.coral.withValues(alpha: .35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18));
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.linear(c - Offset(r, r), c + Offset(r, r),
            const [DeciCores.rosaClaro, DeciCores.rosa, DeciCores.coral], const [0, .45, 1]),
    );
    // brilho suave no topo
    canvas.drawCircle(c - Offset(r * .3, r * .38), r * .45, Paint()
      ..color = Colors.white.withValues(alpha: .18)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * .3));
  }

  @override
  bool shouldRepaint(covariant _PintorBotao old) => old.v != v;
}

/// Traçado de ECG dentro do botão, com um ponto luminoso percorrendo a linha.
class _TracoBotao extends CustomPainter {
  _TracoBotao(this.v);
  final double v;

  static double _y(double x) {
    double g(double c, double a, double s) => a * math.exp(-math.pow(x - c, 2) / (2 * s * s));
    return -(g(.28, .12, .03) + g(.44, -.12, .012) + g(.48, .85, .014) + g(.52, -.3, .012) + g(.7, .22, .05));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    Offset p(double x) => Offset(x * w, h * .62 + _y(x) * h * .62);
    final path = Path()..moveTo(0, p(0).dy);
    for (var i = 1; i <= 120; i++) {
      path.lineTo(p(i / 120).dx, p(i / 120).dy);
    }
    canvas.drawPath(path, Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round);
    final ponto = p(v);
    canvas.drawCircle(ponto, 9, Paint()
      ..color = Colors.white.withValues(alpha: .5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    canvas.drawCircle(ponto, 4.5, Paint()..color = DeciCores.marrom);
  }

  @override
  bool shouldRepaint(covariant _TracoBotao old) => old.v != v;
}
