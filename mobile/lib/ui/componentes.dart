import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'deci_marca.dart';
import 'tema.dart';

/// Largura máxima do conteúdo: no tablet as telas viram uma coluna central legível.
const larguraMaxConteudo = 760.0;

/// Margem lateral que centraliza o conteúdo numa coluna de no máximo [max] (16 no celular).
double margemLateral(double largura, {double max = larguraMaxConteudo}) => math.max(16.0, (largura - max) / 2);

/// ListView com margem 16 no celular e conteúdo centralizado (largura máxima) em telas largas.
class ListaResponsiva extends StatelessWidget {
  const ListaResponsiva({super.key, required this.children, this.larguraMax = larguraMaxConteudo});
  final List<Widget> children;
  final double larguraMax;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, lim) {
        final m = margemLateral(lim.maxWidth, max: larguraMax);
        return ListView(padding: EdgeInsets.fromLTRB(m, 16, m, 16), children: children);
      });
}

class TagClasse extends StatelessWidget {
  const TagClasse(this.classe, {super.key, this.extra = '', this.grande = false});
  final String? classe;
  final String extra;
  final bool grande;

  @override
  Widget build(BuildContext context) {
    if (classe == null) return const Text('—', style: TextStyle(color: Cores.suave));
    final c = corDaClasse(classe);
    return Tooltip(
      message: descricaoClasse[classe] ?? classe!,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: grande ? 14 : 9, vertical: grande ? 4 : 2),
        decoration: BoxDecoration(
          color: Color.alphaBlend(c.withValues(alpha: 0.12), Colors.white),
          border: Border.all(color: Color.alphaBlend(c.withValues(alpha: 0.35), Colors.white)),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text('$classe$extra',
            style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: grande ? 18 : 12.5)),
      ),
    );
  }
}

class Kpi extends StatelessWidget {
  const Kpi({super.key, required this.rotulo, required this.valor, this.sub, this.destaque = false});
  final String rotulo;
  final Widget valor;
  final String? sub;
  final bool destaque;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: destaque ? Cores.destaqueClaro : Cores.painel,
        border: Border.all(color: destaque ? Cores.destaque : Cores.linha),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(rotulo.toUpperCase(),
            style: const TextStyle(fontSize: 10.5, letterSpacing: .6, color: Cores.suave, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        DefaultTextStyle(
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Cores.texto), child: valor),
        if (sub != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(sub!, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, color: Cores.suave)),
          ),
      ]),
    );
  }
}

/// Linha de indicadores com a altura do mais alto (em vez de uma grade de altura fixa).
class LinhaKpis extends StatelessWidget {
  const LinhaKpis(this.itens, {super.key});
  final List<Widget> itens;
  @override
  Widget build(BuildContext context) => IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < itens.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: itens[i]),
          ],
        ]),
      );
}

class Secao extends StatelessWidget {
  const Secao({super.key, required this.titulo, required this.filho, this.acao});
  final String titulo;
  final Widget filho;
  final Widget? acao;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(titulo, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600))),
            ?acao,
          ]),
          const SizedBox(height: 12),
          filho,
        ]),
      ),
    );
  }
}

class Caixa extends StatelessWidget {
  const Caixa(this.texto, {super.key, this.icone = DeciGlifo.info, this.tipo = 'info'});
  final String texto;
  final DeciGlifo icone;
  final String tipo; // info | aviso | erro

  @override
  Widget build(BuildContext context) {
    final (fundo, cor) = switch (tipo) {
      'aviso' => (Cores.avisoClaro, Cores.aviso),
      'erro' => (const Color(0xFFFDEEEE), Cores.perigo),
      _ => (Cores.destaqueClaro, Cores.destaqueEscuro),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: fundo, borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        DeciIcone(icone, tamanho: 18, cor: cor),
        const SizedBox(width: 8),
        Expanded(child: Text(texto, style: TextStyle(color: cor, fontSize: 13.5))),
      ]),
    );
  }
}

/// Logo oficial da UFOP (painel com emblema vazado) pintada no verde do app.
class LogoUfop extends StatelessWidget {
  const LogoUfop({super.key, this.altura = 40});
  final double altura;
  @override
  Widget build(BuildContext context) =>
      Image.asset('assets/img/ufop-logo.png', height: altura, semanticLabel: 'Logo da UFOP');
}


String formatarData(String? iso, {bool comHora = true}) {
  if (iso == null) return '--';
  final d = DateTime.parse(iso).toLocal();
  String dois(int v) => v.toString().padLeft(2, '0');
  final data = '${dois(d.day)}/${dois(d.month)}/${d.year}';
  return comHora ? '$data ${dois(d.hour)}:${dois(d.minute)}' : data;
}

String formatarHora(String? iso) {
  if (iso == null) return '--';
  final d = DateTime.parse(iso).toLocal();
  String dois(int v) => v.toString().padLeft(2, '0');
  return '${dois(d.hour)}:${dois(d.minute)}:${dois(d.second)}';
}

const sexos = {'F': 'Feminino', 'M': 'Masculino', 'O': 'Outro'};
