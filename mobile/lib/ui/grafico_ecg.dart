// Traçado de ECG em papel milimetrado (quadrados de 0,04 s e 0,2 s).
import 'package:flutter/material.dart';

import 'tema.dart';

class GraficoEcg extends StatelessWidget {
  const GraficoEcg({
    super.key,
    required this.sinal,
    this.fs = 100,
    this.cursor,
    this.rpeaks = const [],
    this.classePorPico = const {},
    this.altura = 220,
    this.grade = true,
    this.rotulos = true,
    this.destaque,
    this.mensagemVazio = 'Aguardando sinal do ECG…',
  });

  final List<double> sinal; // NaN = sem dado (buffer ainda enchendo)
  final int fs;
  final int? cursor; // varredura: posição sendo escrita
  final List<int> rpeaks;
  final Map<int, String> classePorPico;
  final double altura;
  final bool grade, rotulos;
  final int? destaque;
  final String mensagemVazio;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: altura,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Cores.linha),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        size: Size.infinite,
        painter: _Pintor(this),
      ),
    );
  }
}

class _Pintor extends CustomPainter {
  _Pintor(this.g);
  final GraficoEcg g;

  @override
  void paint(Canvas canvas, Size size) {
    final n = g.sinal.length;
    final w = size.width, h = size.height;
    final dur = n / g.fs;
    if (g.grade && n > 0) {
      final pxPorS = w / dur;
      for (final (passo, cor) in [(0.04, Cores.ecgGrade), (0.2, Cores.ecgGradeForte)]) {
        if (pxPorS * passo < 4) continue;
        final p = Paint()
          ..color = cor
          ..strokeWidth = 1;
        for (double t = 0; t <= dur + 1e-9; t += passo) {
          canvas.drawLine(Offset(t * pxPorS, 0), Offset(t * pxPorS, h), p);
        }
        for (double y = h; y >= 0; y -= pxPorS * passo) {
          canvas.drawLine(Offset(0, y), Offset(w, y), p);
        }
      }
    }

    double lo = double.infinity, hi = double.negativeInfinity;
    for (final v in g.sinal) {
      if (v.isNaN) continue;
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    if (lo == double.infinity) {
      final tp = TextPainter(
          text: TextSpan(text: g.mensagemVazio, style: const TextStyle(color: Cores.suave, fontSize: 13)),
          textDirection: TextDirection.ltr)
        ..layout(maxWidth: w);
      tp.paint(canvas, Offset((w - tp.width) / 2, (h - tp.height) / 2));
      return;
    }
    final faixa = (hi - lo) < 1e-9 ? 1.0 : hi - lo;
    final topo = g.rotulos ? 20.0 : 4.0, base = 4.0;
    double x(int i) => n == 1 ? 0 : i / (n - 1) * w;
    double y(double v) => topo + (1 - (v - lo) / faixa) * (h - topo - base);

    if (g.destaque != null) {
      canvas.drawRect(Rect.fromLTWH(x(g.destaque!) - 12, 0, 24, h), Paint()..color = Cores.verde.withValues(alpha: .15));
    }

    final traco = Paint()
      ..color = Cores.ecgTraco
      ..strokeWidth = g.rotulos ? 1.7 : 1.1
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    var aberto = false;
    for (var i = 0; i < n; i++) {
      final v = g.sinal[i];
      // na varredura, deixa um vão logo à frente do cursor (como nos monitores)
      final noVao = g.cursor != null && ((i - g.cursor!) % n + n) % n < (g.fs * 0.15);
      if (v.isNaN || noVao) {
        aberto = false;
        continue;
      }
      aberto ? path.lineTo(x(i), y(v)) : path.moveTo(x(i), y(v));
      aberto = true;
    }
    canvas.drawPath(path, traco);

    if (g.cursor != null) {
      final i = (g.cursor! - 1 + n) % n;
      if (!g.sinal[i].isNaN) canvas.drawCircle(Offset(x(i), y(g.sinal[i])), 4, Paint()..color = Cores.verde);
    }

    for (final r in g.rpeaks) {
      if (r < 0 || r >= n || g.sinal[r].isNaN) continue;
      final c = g.classePorPico[r];
      final cor = corDaClasse(c);
      canvas.drawCircle(Offset(x(r), y(g.sinal[r])), g.rotulos ? 3.5 : 2, Paint()..color = c == null ? Cores.suave : cor);
      if (g.rotulos && c != null) {
        final tp = TextPainter(
            text: TextSpan(text: c, style: TextStyle(color: cor, fontSize: 12, fontWeight: FontWeight.w700)),
            textDirection: TextDirection.ltr)
          ..layout();
        tp.paint(canvas, Offset(x(r) - tp.width / 2, 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _Pintor old) => true;
}
