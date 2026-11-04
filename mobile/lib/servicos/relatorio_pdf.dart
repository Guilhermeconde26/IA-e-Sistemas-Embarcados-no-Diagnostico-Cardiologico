// Relatório da sessão em PDF (A4), com os traçados desenhados em vetor.
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../ui/componentes.dart' show formatarData, formatarHora, sexos;
import '../ui/tema.dart' show descricaoClasse;
import 'relatorio.dart';

const _verde = PdfColor.fromInt(0xFFF2456F); // destaque coral do DECI
const _verdeEscuro = PdfColor.fromInt(0xFFC42452);
const _verdeClaro = PdfColor.fromInt(0xFFFDE0E4);
const _suave = PdfColor.fromInt(0xFF8A6669);
const _linha = PdfColor.fromInt(0xFFF6DCD8);
const _grade = PdfColor.fromInt(0xFFFBE6E4);
const _gradeForte = PdfColor.fromInt(0xFFF4C7C6);
const _traco = PdfColor.fromInt(0xFF4A1820);
const _coresClasse = {
  'N': PdfColor.fromInt(0xFF2E9E6B),
  'S': PdfColor.fromInt(0xFFD08A12),
  'V': PdfColor.fromInt(0xFFB3261E),
  'F': PdfColor.fromInt(0xFF7E57C2),
};

Future<Uint8List> gerarPdf(DadosRelatorio d) async {
  final logo = pw.MemoryImage((await rootBundle.load('assets/img/ufop-logo.png')).buffer.asUint8List());
  final mascote = pw.MemoryImage((await rootBundle.load('assets/img/deci-mascote.png')).buffer.asUint8List());
  final s = d.sessao;
  final doc = pw.Document(title: 'DECI - Sessão ${s['id']}', author: 'DECI');
  const pequeno = pw.TextStyle(fontSize: 8.5, color: _suave);

  pw.Widget kpi(String rotulo, String valor) => pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.only(right: 6),
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(color: _verdeClaro, borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(rotulo.toUpperCase(), style: const pw.TextStyle(fontSize: 7, color: _suave)),
            pw.SizedBox(height: 2),
            pw.Text(valor, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          ]),
        ),
      );

  final paciente = [
    if (s['patient_id'] != null) 'Prontuário: ${s['patient_id']}',
    if (s['patient_age'] != null) 'Idade: ${s['patient_age']} anos',
    if (s['patient_sex'] != null) 'Sexo: ${sexos[s['patient_sex']]}',
  ].join('   ');

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 32),
    header: (c) => pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 6),
      margin: const pw.EdgeInsets.only(bottom: 12),
      decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _verde, width: 2))),
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Row(children: [
          pw.Image(mascote, height: 24),
          pw.SizedBox(width: 6),
          pw.RichText(text: pw.TextSpan(children: [
            pw.TextSpan(text: 'DECI', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, letterSpacing: 1)),
            const pw.TextSpan(text: '  Diagnóstico de Eletrocardiograma Instantâneo', style: pw.TextStyle(fontSize: 9, color: _suave)),
          ])),
        ]),
        pw.Text('Emitido em ${formatarData(DateTime.now().toUtc().toIso8601String())}', style: pequeno),
      ]),
    ),
    footer: (c) => pw.Column(children: [
      pw.Container(
        padding: const pw.EdgeInsets.all(6),
        decoration: pw.BoxDecoration(color: _verdeClaro, borderRadius: pw.BorderRadius.circular(4)),
        child: pw.Text('Trabalho científico. As classificações são geradas por um modelo de inteligência artificial e '
            'podem conter erros. Os resultados não substituem a avaliação de um profissional de saúde.',
            style: const pw.TextStyle(fontSize: 7.5, color: _verdeEscuro)),
      ),
      pw.SizedBox(height: 6),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
        pw.Image(logo, height: 26),
        pw.SizedBox(width: 6),
        pw.Expanded(
          child: pw.Text('Departamento de Engenharia de Controle e Automação — Universidade Federal de Ouro Preto (UFOP)\n'
              'Guilherme Conde · guilherme.conde@aluno.ufop.edu.br   ·   Adrielle Santana · Adrielle@ufop.edu.br',
              style: const pw.TextStyle(fontSize: 7, color: _suave)),
        ),
        pw.Text('Página ${c.pageNumber}/${c.pagesCount}', style: pequeno),
      ]),
    ]),
    build: (c) => [
      pw.Text('Sessão #${s['id']}${s['simulada'] == 1 ? ' (simulada)' : ''}',
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
      pw.Text(formatarData(s['inicio'] as String?), style: pequeno),
      pw.SizedBox(height: 10),
      pw.Text((s['patient'] as String?) ?? 'Paciente não identificado',
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
      if (paciente.isNotEmpty) pw.Text(paciente, style: const pw.TextStyle(fontSize: 9.5)),
      if ((s['notes'] as String?)?.isNotEmpty == true)
        pw.Padding(padding: const pw.EdgeInsets.only(top: 3), child: pw.Text('Observações: ${s['notes']}', style: const pw.TextStyle(fontSize: 9.5))),
      pw.SizedBox(height: 12),
      pw.Row(children: [
        kpi('BPM médio', d.bpmMedio?.toStringAsFixed(1) ?? '--'),
        kpi('Classe predominante', (s['classe_final'] as String?) ?? '--'),
        kpi('Medições válidas', '${d.validas.length}/${d.medicoes.length}'),
        kpi('SDNN médio', d.sdnnMedio == null ? '--' : '${d.sdnnMedio!.toStringAsFixed(0)} ms'),
      ]),
      pw.SizedBox(height: 12),
      pw.Text('Batimentos por classe', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      for (final e in (d.batimentosPorClasse.entries.toList()..sort((a, b) => b.value.compareTo(a.value))))
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
          child: pw.Row(children: [
            pw.SizedBox(width: 16, child: pw.Text(e.key, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _coresClasse[e.key]))),
            pw.SizedBox(width: 170, child: pw.Text(descricaoClasse[e.key] ?? '', style: const pw.TextStyle(fontSize: 8.5))),
            pw.Expanded(
              child: pw.Stack(children: [
                pw.Container(height: 7, decoration: pw.BoxDecoration(color: _grade, borderRadius: pw.BorderRadius.circular(4))),
                pw.Container(
                  height: 7,
                  width: 250.0 * e.value / (d.totalBatimentos == 0 ? 1 : d.totalBatimentos),
                  decoration: pw.BoxDecoration(color: _coresClasse[e.key], borderRadius: pw.BorderRadius.circular(4)),
                ),
              ]),
            ),
            pw.SizedBox(
                width: 60,
                child: pw.Text('${e.value} (${(100 * e.value / d.totalBatimentos).round()}%)',
                    textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 8.5))),
          ]),
        ),
      pw.SizedBox(height: 14),
      pw.Text('Medições', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      for (final m in d.medicoes)
        pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(
                '#${m.id} · ${formatarHora(m.linha['criada'] as String?)} · '
                '${m.erro ?? '${m.bpm?.toStringAsFixed(0)} bpm · classe ${m.classe}'}',
                style: const pw.TextStyle(fontSize: 8.5)),
            pw.SizedBox(height: 2),
            if (m.erro == null) _tracado(m) else pw.SizedBox(height: 2),
          ]),
        ),
    ],
  ));
  return doc.save();
}

/// Traçado de 10 s em papel milimetrado, com a classe de cada batimento acima do pico.
pw.Widget _tracado(MedicaoRelatorio m) {
  const altura = 62.0;
  return pw.Container(
    height: altura,
    decoration: pw.BoxDecoration(border: pw.Border.all(color: _linha, width: .5)),
    child: pw.Stack(children: [
      pw.CustomPaint(
        size: const PdfPoint(double.infinity, altura),
        painter: (canvas, size) {
          final w = size.x, h = size.y;
          final n = m.filtrado.length;
          if (n < 2) return;
          final pxPorS = w / (n / 100);
          for (final (passo, cor) in [(0.04, _grade), (0.2, _gradeForte)]) {
            canvas..setStrokeColor(cor)..setLineWidth(.3);
            for (double t = 0; t * pxPorS <= w; t += passo) {
              canvas..moveTo(t * pxPorS, 0)..lineTo(t * pxPorS, h);
            }
            for (double y = 0; y <= h; y += pxPorS * passo) {
              canvas..moveTo(0, y)..lineTo(w, y);
            }
            canvas.strokePath();
          }
          var lo = m.filtrado.reduce((a, b) => a < b ? a : b), hi = m.filtrado.reduce((a, b) => a > b ? a : b);
          if (hi - lo < 1e-9) hi = lo + 1;
          double x(int i) => i / (n - 1) * w;
          // no PDF o eixo y cresce para cima
          double y(double v) => 3 + (v - lo) / (hi - lo) * (h - 14);
          canvas..setStrokeColor(_traco)..setLineWidth(.8);
          canvas.moveTo(x(0), y(m.filtrado[0]));
          for (var i = 1; i < n; i++) {
            canvas.lineTo(x(i), y(m.filtrado[i]));
          }
          canvas.strokePath();
          for (final r in m.rpeaks) {
            final c = m.classes[r];
            canvas.setFillColor(_coresClasse[c] ?? _suave);
            canvas.drawEllipse(x(r), y(m.filtrado[r]), 1.4, 1.4);
            canvas.fillPath();
          }
        },
      ),
      // rótulos das classes como texto (o canvas do pdf não desenha texto facilmente)
      pw.Positioned.fill(
        child: pw.LayoutBuilder(builder: (c, lim) {
          final w = lim!.maxWidth;
          final n = m.filtrado.length;
          return pw.Stack(children: [
            for (final e in m.classes.entries)
              pw.Positioned(
                left: (e.key / (n - 1) * w - 3).clamp(0, w - 6),
                top: 1,
                child: pw.Text(e.value, style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold, color: _coresClasse[e.value])),
              ),
          ]);
        }),
      ),
    ]),
  );
}
