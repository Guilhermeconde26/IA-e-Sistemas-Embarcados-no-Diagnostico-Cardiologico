// Identidade visual do DECI: paleta, personagem (blob rosa sorridente) e ícones no mesmo estilo.
// O contorno do personagem foi traçado do ícone original (40 pontos, normalizados na caixa do blob).
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class DeciCores {
  static const creme = Color(0xFFFEF1EC);
  static const creme2 = Color(0xFFFDEBE8);
  static const brilho = Color(0xFFFCE1DF);
  static const rosaClaro = Color(0xFFFCA8B2);
  static const rosa = Color(0xFFFD8398);
  static const coral = Color(0xFFFD406E);
  static const coralEscuro = Color(0xFFD62B57);
  static const marrom = Color(0xFF371215);
  static const lingua = Color(0xFFFB8C9A);
  static const rosaPalido = Color(0xFFFDE0E4);
}

// ------------------------------------------------------------------ contorno
const _contorno = [
  Offset(0.993, 0.499), Offset(1.002, 0.579), Offset(0.989, 0.659), Offset(0.959, 0.733), Offset(0.914, 0.798),
  Offset(0.858, 0.850), Offset(0.798, 0.894), Offset(0.731, 0.921), Offset(0.669, 0.954), Offset(0.602, 0.983),
  Offset(0.531, 0.998), Offset(0.457, 1.001), Offset(0.383, 0.989), Offset(0.315, 0.954), Offset(0.259, 0.901),
  Offset(0.219, 0.834), Offset(0.177, 0.775), Offset(0.112, 0.728), Offset(0.049, 0.667), Offset(0.010, 0.588),
  Offset(0.001, 0.499), Offset(0.015, 0.415), Offset(0.049, 0.330), Offset(0.098, 0.262), Offset(0.160, 0.209),
  Offset(0.232, 0.177), Offset(0.300, 0.157), Offset(0.357, 0.132), Offset(0.409, 0.096), Offset(0.465, 0.054),
  Offset(0.531, 0.023), Offset(0.604, 0.005), Offset(0.682, -0.001), Offset(0.763, 0.010), Offset(0.838, 0.046),
  Offset(0.898, 0.105), Offset(0.937, 0.182), Offset(0.957, 0.266), Offset(0.970, 0.345), Offset(0.975, 0.423),
];

/// Curva fechada suave (Catmull-Rom) passando pelos pontos do contorno.
List<Offset> _amostrarContorno(int n) {
  final p = _contorno;
  final m = p.length;
  final saida = <Offset>[];
  for (var k = 0; k < n; k++) {
    final t = k / n * m;
    final i = t.floor();
    final u = t - i;
    final p0 = p[(i - 1 + m) % m], p1 = p[i % m], p2 = p[(i + 1) % m], p3 = p[(i + 2) % m];
    final u2 = u * u, u3 = u2 * u;
    saida.add((p0 * (-u3 + 2 * u2 - u) + p1 * (3 * u3 - 5 * u2 + 2) + p2 * (-3 * u3 + 4 * u2 + u) + p3 * (u3 - u2)) * 0.5);
  }
  return saida;
}

/// Um batimento estilizado (P, QRS, T), x em 0..1, y em torno de 0 (negativo = para cima).
double _ecg(double x) {
  double g(double c, double a, double s) => a * math.exp(-math.pow(x - c, 2) / (2 * s * s));
  return -(g(0.30, 0.10, 0.025) + g(0.445, -0.10, 0.008) + g(0.47, 0.62, 0.010) + g(0.495, -0.20, 0.009) + g(0.66, 0.17, 0.040));
}

const int _nPontos = 240;
final List<Offset> _blob = _amostrarContorno(_nPontos);
// O contorno começa à direita (0°) e gira no sentido horário pela parte de baixo. Para virar a linha do ECG,
// a metade de cima (da esquerda para a direita) e a de baixo (de volta) colapsam sobre o mesmo traçado.
final int _iEsquerda = () {
  var best = 0;
  for (var i = 1; i < _blob.length; i++) {
    if (_blob[i].dx < _blob[best].dx) best = i;
  }
  return best;
}();

/// Posição (no espaço da caixa do blob, 0..1) do i-ésimo ponto quando vira ECG.
Offset _pontoEcg(int i, double largura) {
  final rel = (i - _iEsquerda + _nPontos) % _nPontos; // 0 = extremo esquerdo, sentido horário (por cima)
  final metade = _nPontos / 2;
  final x = rel <= metade ? rel / metade : (_nPontos - rel) / metade; // vai e volta
  final xx = 0.5 + (x - 0.5) * largura;
  return Offset(xx, 0.55 + _ecg(x) * 0.9);
}

// ------------------------------------------------------------------ personagem
/// O personagem do DECI. [rosto] 0..1 (opacidade dos olhos e boca), [morph] 0..1 (vira um traçado de ECG),
/// [larguraEcg] largura final do ECG em múltiplos da largura do blob, [brilho] liga o halo rosado.
class MascotePainter extends CustomPainter {
  MascotePainter({this.rosto = 1, this.morph = 0, this.larguraEcg = 2.2, this.brilho = true, this.pulso});
  final double rosto, morph, larguraEcg;
  final bool brilho;
  final double? pulso; // 0..1: posição do ponto luminoso que percorre o ECG

  @override
  void paint(Canvas canvas, Size size) {
    // caixa do blob centralizada, proporção do original (1,074 : 1)
    final h = math.min(size.height, size.width / 1.074);
    final w = h * 1.074;
    final o = Offset((size.width - w) / 2, (size.height - h) / 2);
    Offset aTela(Offset p) => o + Offset(p.dx * w, p.dy * h);

    final m = Curves.easeInOutCubic.transform(morph.clamp(0, 1));
    final pts = <Offset>[
      for (var i = 0; i < _nPontos; i++) aTela(Offset.lerp(_blob[i], _pontoEcg(i, larguraEcg), m)!),
    ];
    final path = Path()..addPolygon(pts, true);
    final caixa = Rect.fromLTWH(o.dx, o.dy, w, h);
    final gradiente = ui.Gradient.linear(
      caixa.topLeft + Offset(w * 0.15, h * 0.05),
      caixa.bottomRight - Offset(w * 0.1, h * 0.05),
      const [DeciCores.rosaClaro, DeciCores.rosa, DeciCores.coral],
      const [0.0, 0.45, 1.0],
    );

    // halo rosado em volta (como no ícone)
    if (brilho && m < 1) {
      canvas.drawPath(
        path,
        Paint()
          ..color = DeciCores.coral.withValues(alpha: 0.22 * (1 - m))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 0.08),
      );
    }
    // corpo: preenchido, some durante a transformação
    final preenchimento = (1 - m * 1.4).clamp(0.0, 1.0);
    if (preenchimento > 0) {
      canvas.saveLayer(caixa.inflate(w), Paint()..color = Colors.white.withValues(alpha: preenchimento));
      canvas.drawPath(path, Paint()..shader = gradiente);
      canvas.restore();
    }
    // traço: aparece conforme vira ECG
    if (m > 0) {
      final traco = Paint()
        ..shader = ui.Gradient.linear(Offset(o.dx - w * (larguraEcg - 1) / 2, 0), Offset(o.dx + w * (1 + (larguraEcg - 1) / 2), 0),
            const [DeciCores.rosa, DeciCores.coral, DeciCores.coralEscuro], const [0, .5, 1])
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * (0.012 + 0.03 * m)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final linha = Path()..addPolygon(pts, m < 0.98);
      canvas.saveLayer(caixa.inflate(w * larguraEcg), Paint()..color = Colors.white.withValues(alpha: (m * 1.6).clamp(0, 1)));
      canvas.drawPath(linha, traco);
      canvas.restore();
    }

    // rosto
    final a = (rosto * (1 - m * 3)).clamp(0.0, 1.0);
    if (a > 0) {
      final marrom = DeciCores.marrom.withValues(alpha: a);
      final olho = Paint()
        ..color = marrom
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.042
        ..strokeCap = StrokeCap.round;
      for (final cx in [0.31, 0.677]) {
        final c = aTela(Offset(cx, 0.505));
        canvas.drawArc(Rect.fromCenter(center: c, width: w * 0.2, height: h * 0.17), math.pi * 1.08, math.pi * 0.84, false, olho);
      }
      // boca em "D": topo quase reto, fundo arredondado, língua clara
      final b0 = aTela(const Offset(0.385, 0.565)), b1 = aTela(const Offset(0.602, 0.565));
      final fundo = aTela(const Offset(0.4935, 0.70));
      final boca = Path()
        ..moveTo(b0.dx, b0.dy)
        ..quadraticBezierTo((b0.dx + b1.dx) / 2, b0.dy + h * 0.012, b1.dx, b1.dy)
        ..cubicTo(b1.dx, b1.dy + h * 0.09, fundo.dx + w * 0.07, fundo.dy, fundo.dx, fundo.dy)
        ..cubicTo(fundo.dx - w * 0.07, fundo.dy, b0.dx, b0.dy + h * 0.09, b0.dx, b0.dy)
        ..close();
      canvas.drawPath(boca, Paint()..color = marrom);
      canvas.save();
      canvas.clipPath(boca);
      canvas.drawOval(
        Rect.fromCenter(center: aTela(const Offset(0.4935, 0.69)), width: w * 0.16, height: h * 0.09),
        Paint()..color = DeciCores.lingua.withValues(alpha: a),
      );
      canvas.restore();
      canvas.drawPath(
        boca,
        Paint()
          ..color = marrom
          ..style = PaintingStyle.stroke
          ..strokeWidth = h * 0.028
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // ponto luminoso percorrendo o ECG, como num monitor
    if (pulso != null && m > 0.95) {
      final x = pulso!.clamp(0.0, 1.0);
      final p = aTela(Offset(0.5 + (x - 0.5) * larguraEcg, 0.55 + _ecg(x) * 0.9));
      canvas.drawCircle(p, h * 0.07, Paint()
        ..color = DeciCores.coral.withValues(alpha: .35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 0.04));
      canvas.drawCircle(p, h * 0.028, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant MascotePainter old) =>
      old.rosto != rosto || old.morph != morph || old.pulso != pulso || old.larguraEcg != larguraEcg;
}

class Mascote extends StatelessWidget {
  const Mascote({super.key, this.tamanho = 120, this.brilho = true});
  final double tamanho;
  final bool brilho;
  @override
  Widget build(BuildContext context) => SizedBox(
      width: tamanho, height: tamanho / 1.074, child: CustomPaint(painter: MascotePainter(brilho: brilho)));
}

// ------------------------------------------------------------------ ícones
enum DeciGlifo {
  ecg, pasta, pessoa, bluetooth, busca, play, stop, pdf, lixeira, compartilhar, sair, chip, alerta, info,
  coracao, salvar, voltar, simulador, ajustes, dados, limpar, fechar, cadeado,
}

/// Ícone no estilo do DECI: blob rosa com traços marrons arredondados.
/// [blob] false = só o traço (para botões e textos).
class DeciIcone extends StatelessWidget {
  const DeciIcone(this.glifo, {super.key, this.tamanho = 24, this.blob = false, this.ativo = true, this.cor});
  final DeciGlifo glifo;
  final double tamanho;
  final bool blob, ativo;
  final Color? cor;

  @override
  Widget build(BuildContext context) {
    final c = cor ?? IconTheme.of(context).color ?? DeciCores.marrom;
    return SizedBox.square(
      dimension: tamanho,
      child: CustomPaint(painter: _IconePainter(glifo, blob, ativo, blob ? DeciCores.marrom : c)),
    );
  }
}

class _IconePainter extends CustomPainter {
  _IconePainter(this.g, this.blob, this.ativo, this.cor);
  final DeciGlifo g;
  final bool blob, ativo;
  final Color cor;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    if (blob) {
      // mini blob com o mesmo contorno do personagem
      final w = s, h = s / 1.074;
      final o = Offset(0, (s - h) / 2);
      final path = Path()..addPolygon([for (final p in _amostrarContorno(48)) o + Offset(p.dx * w, p.dy * h)], true);
      canvas.drawPath(
        path,
        Paint()
          ..shader = ativo
              ? ui.Gradient.linear(o, o + Offset(w, h), const [DeciCores.rosaClaro, DeciCores.rosa, DeciCores.coral], const [0, .5, 1])
              : null
          ..color = DeciCores.rosaPalido,
      );
      canvas.translate(s * 0.2, s * 0.2);
      canvas.scale(0.6);
    }
    final t = Paint()
      ..color = cor
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * (blob ? 0.13 : 0.095)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final f = Paint()..color = cor;
    Offset p(double x, double y) => Offset(x * s, y * s);
    Path linha(List<List<double>> xy) {
      final path = Path()..moveTo(xy[0][0] * s, xy[0][1] * s);
      for (final q in xy.skip(1)) {
        path.lineTo(q[0] * s, q[1] * s);
      }
      return path;
    }

    void arco(double cx, double cy, double r, double ini, double varre) =>
        canvas.drawArc(Rect.fromCircle(center: p(cx, cy), radius: r * s), ini, varre, false, t);
    RRect rr(double l, double tp, double r, double b, double raio) =>
        RRect.fromLTRBR(l * s, tp * s, r * s, b * s, Radius.circular(raio * s));

    switch (g) {
      case DeciGlifo.ecg:
        canvas.drawPath(linha([[.06, .55], [.3, .55], [.38, .4], [.46, .7], [.55, .18], [.64, .82], [.71, .55], [.94, .55]]), t);
      case DeciGlifo.coracao:
        canvas.drawPath(
            Path()
              ..moveTo(.5 * s, .84 * s)
              ..cubicTo(.1 * s, .58 * s, .02 * s, .3 * s, .27 * s, .2 * s)
              ..cubicTo(.4 * s, .15 * s, .48 * s, .25 * s, .5 * s, .32 * s)
              ..cubicTo(.52 * s, .25 * s, .6 * s, .15 * s, .73 * s, .2 * s)
              ..cubicTo(.98 * s, .3 * s, .9 * s, .58 * s, .5 * s, .84 * s),
            t);
      case DeciGlifo.pasta:
        canvas.drawPath(linha([[.1, .78], [.1, .24], [.38, .24], [.47, .34], [.9, .34], [.9, .78], [.1, .78]]), t);
      case DeciGlifo.pessoa:
        // rosto sorridente do personagem
        arco(.5, .5, .38, 0, math.pi * 2);
        arco(.36, .47, .08, math.pi * 1.1, math.pi * .8);
        arco(.64, .47, .08, math.pi * 1.1, math.pi * .8);
        arco(.5, .55, .13, math.pi * .15, math.pi * .7);
      case DeciGlifo.bluetooth:
        canvas.drawPath(linha([[.28, .32], [.7, .66], [.5, .86], [.5, .14], [.7, .34], [.28, .68]]), t);
      case DeciGlifo.busca:
        arco(.43, .43, .26, 0, math.pi * 2);
        canvas.drawLine(p(.63, .63), p(.86, .86), t);
      case DeciGlifo.play:
        canvas.drawPath(linha([[.32, .18], [.32, .82], [.82, .5], [.32, .18]]), t);
      case DeciGlifo.stop:
        canvas.drawRRect(rr(.22, .22, .78, .78, .1), t);
      case DeciGlifo.pdf:
        canvas.drawPath(linha([[.22, .1], [.6, .1], [.8, .3], [.8, .9], [.22, .9], [.22, .1]]), t);
        canvas.drawPath(linha([[.34, .62], [.42, .62], [.48, .48], [.54, .74], [.6, .62], [.68, .62]]), t..strokeWidth *= .8);
      case DeciGlifo.lixeira:
        canvas.drawLine(p(.16, .26), p(.84, .26), t);
        canvas.drawPath(linha([[.38, .26], [.38, .14], [.62, .14], [.62, .26]]), t);
        canvas.drawPath(linha([[.24, .26], [.3, .88], [.7, .88], [.76, .26]]), t);
      case DeciGlifo.compartilhar:
        canvas.drawPath(linha([[.5, .62], [.5, .12]]), t);
        canvas.drawPath(linha([[.3, .3], [.5, .12], [.7, .3]]), t);
        canvas.drawPath(linha([[.24, .48], [.18, .48], [.18, .88], [.82, .88], [.82, .48], [.76, .48]]), t);
      case DeciGlifo.sair:
        canvas.drawPath(linha([[.5, .14], [.18, .14], [.18, .86], [.5, .86]]), t);
        canvas.drawLine(p(.42, .5), p(.88, .5), t);
        canvas.drawPath(linha([[.72, .32], [.88, .5], [.72, .68]]), t);
      case DeciGlifo.chip:
        canvas.drawRRect(rr(.26, .26, .74, .74, .1), t);
        for (final v in [.4, .6]) {
          canvas.drawLine(p(v, .1), p(v, .26), t);
          canvas.drawLine(p(v, .74), p(v, .9), t);
          canvas.drawLine(p(.1, v), p(.26, v), t);
          canvas.drawLine(p(.74, v), p(.9, v), t);
        }
      case DeciGlifo.alerta:
        canvas.drawPath(linha([[.5, .12], [.9, .84], [.1, .84], [.5, .12]]), t);
        canvas.drawLine(p(.5, .4), p(.5, .58), t);
        canvas.drawCircle(p(.5, .71), s * .045, f);
      case DeciGlifo.info:
        arco(.5, .5, .38, 0, math.pi * 2);
        canvas.drawLine(p(.5, .46), p(.5, .7), t);
        canvas.drawCircle(p(.5, .32), s * .045, f);
      case DeciGlifo.salvar:
        canvas.drawPath(linha([[.18, .52], [.4, .74], [.82, .28]]), t);
      case DeciGlifo.voltar:
        canvas.drawPath(linha([[.62, .18], [.3, .5], [.62, .82]]), t);
      case DeciGlifo.simulador:
        canvas.drawRRect(rr(.12, .2, .88, .74, .1), t);
        canvas.drawPath(linha([[.2, .5], [.36, .5], [.44, .32], [.54, .62], [.6, .5], [.8, .5]]), t..strokeWidth *= .8);
        canvas.drawLine(p(.38, .88), p(.62, .88), t);
      case DeciGlifo.ajustes:
        for (final (y, x) in [(.26, .64), (.5, .36), (.74, .58)]) {
          canvas.drawLine(p(.14, y), p(.86, y), t);
          canvas.drawCircle(p(x, y), s * .085, Paint()..color = blob ? Colors.transparent : Colors.white);
          canvas.drawCircle(p(x, y), s * .085, t);
        }
      case DeciGlifo.dados:
        canvas.drawOval(Rect.fromLTRB(.18 * s, .12 * s, .82 * s, .32 * s), t);
        canvas.drawPath(linha([[.18, .22], [.18, .78]]), t);
        canvas.drawPath(linha([[.82, .22], [.82, .78]]), t);
        canvas.drawArc(Rect.fromLTRB(.18 * s, .4 * s, .82 * s, .6 * s), 0, math.pi, false, t);
        canvas.drawArc(Rect.fromLTRB(.18 * s, .68 * s, .82 * s, .88 * s), 0, math.pi, false, t);
      case DeciGlifo.limpar:
      case DeciGlifo.fechar:
        canvas.drawLine(p(.24, .24), p(.76, .76), t);
        canvas.drawLine(p(.76, .24), p(.24, .76), t);
      case DeciGlifo.cadeado:
        canvas.drawRRect(rr(.2, .44, .8, .88, .1), t);
        arco(.5, .44, .2, math.pi, math.pi);
        canvas.drawLine(p(.3, .44), p(.3, .4), t);
        canvas.drawLine(p(.7, .44), p(.7, .4), t);
    }
  }

  @override
  bool shouldRepaint(covariant _IconePainter old) => old.g != g || old.ativo != ativo || old.cor != cor;
}
