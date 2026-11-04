// Abertura: o personagem do DECI aparece, sorri, vira um traçado de ECG e surge o nome do app.
// Enquanto a animação roda, o app carrega o banco e o modelo; só segue quando os dois terminam.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui/deci_marca.dart';

class TelaAbertura extends StatefulWidget {
  const TelaAbertura({super.key, required this.carregar, required this.aoTerminar});
  final Future<void> Function() carregar;
  final VoidCallback aoTerminar;

  static const duracao = Duration(milliseconds: 3400);

  @override
  State<TelaAbertura> createState() => _TelaAberturaState();
}

class _TelaAberturaState extends State<TelaAbertura> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: TelaAbertura.duracao);

  @override
  void initState() {
    super.initState();
    Future.wait([widget.carregar(), _c.forward().orCancel]).then((_) {
      if (mounted) widget.aoTerminar();
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Fração 0..1 do trecho [ini, fim] (em segundos) da linha do tempo.
  double _trecho(double t, double ini, double fim, [Curve curva = Curves.linear]) =>
      curva.transform(((t - ini) / (fim - ini)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DeciCores.creme,
      body: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value * TelaAbertura.duracao.inMilliseconds / 1000; // segundos
          final entrada = _trecho(t, 0.0, 0.7, Curves.elasticOut);
          final rosto = 1 - _trecho(t, 1.25, 1.5);
          final morph = _trecho(t, 1.3, 2.2);
          final pulso = t > 2.2 ? _trecho(t, 2.2, 3.1, Curves.easeInOut) : null;
          final texto = _trecho(t, 2.25, 2.85, Curves.easeOutCubic);
          // "amassa e estica" de alegria antes de virar ECG
          final pulo = math.sin(_trecho(t, 0.75, 1.2) * math.pi);
          final escalaX = 1 + 0.07 * pulo, escalaY = 1 - 0.06 * pulo;

          return LayoutBuilder(builder: (context, lim) {
            final lado = math.min(lim.maxWidth * 0.42, 220.0);
            // o ECG estica até ~86% da largura da tela
            final larguraFinal = math.min(lim.maxWidth * 0.86 / lado, 2.6);
            final largura = 1 + (larguraFinal - 1) * _trecho(t, 1.6, 2.4, Curves.easeOutCubic);
            return Stack(fit: StackFit.expand, children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [DeciCores.brilho.withValues(alpha: 0.9 * (1 - morph)), DeciCores.creme],
                      radius: 0.7,
                    ),
                  ),
                ),
              ),
              Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Transform.scale(
                  scaleX: (0.3 + 0.7 * entrada) * escalaX,
                  scaleY: (0.3 + 0.7 * entrada) * escalaY,
                  child: SizedBox(
                    width: lim.maxWidth, // espaço para o ECG esticar
                    height: lado / 1.074,
                    child: CustomPaint(
                      painter: MascotePainter(rosto: rosto, morph: morph, larguraEcg: largura, pulso: pulso),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Opacity(
                  opacity: texto,
                  child: Transform.translate(
                    offset: Offset(0, 16 * (1 - texto)),
                    child: Column(children: [
                      Text('DECI',
                          style: TextStyle(
                              fontSize: lado * 0.36,
                              fontWeight: FontWeight.w800,
                              letterSpacing: lado * 0.06,
                              color: DeciCores.marrom)),
                      const SizedBox(height: 6),
                      const Text('Diagnóstico de Eletrocardiograma Instantâneo',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 15, color: Color(0xFF8A6669), fontWeight: FontWeight.w500)),
                    ]),
                  ),
                ),
              ])),
            ]);
          });
        },
      ),
    );
  }
}
