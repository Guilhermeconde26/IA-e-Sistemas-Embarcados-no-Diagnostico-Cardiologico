import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../main.dart';
import '../servicos/relatorio.dart';
import '../servicos/relatorio_pdf.dart';
import '../ui/componentes.dart';
import '../ui/grafico_ecg.dart';
import '../ui/deci_marca.dart';
import '../ui/tema.dart';
import 'tela_detalhe_medicao.dart';

class TelaRelatorio extends StatefulWidget {
  const TelaRelatorio({super.key, required this.sessaoId});
  final int sessaoId;
  @override
  State<TelaRelatorio> createState() => _TelaRelatorioState();
}

class _TelaRelatorioState extends State<TelaRelatorio> {
  DadosRelatorio? _d;
  final _nome = TextEditingController(), _pront = TextEditingController(), _idade = TextEditingController();
  final _obs = TextEditingController();
  String? _sexo;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_d == null) _carregar();
  }

  @override
  void dispose() {
    for (final c in [_nome, _pront, _idade, _obs]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _carregar() async {
    final d = await DadosRelatorio.carregar(Servicos.of(context).banco, widget.sessaoId);
    if (!mounted) return;
    if (d == null) {
      Navigator.pop(context); // sessão apagada
      return;
    }
    final s = d.sessao;
    _nome.text = (s['patient'] as String?) ?? '';
    _pront.text = (s['patient_id'] as String?) ?? '';
    _idade.text = s['patient_age']?.toString() ?? '';
    _obs.text = (s['notes'] as String?) ?? '';
    setState(() {
      _d = d;
      _sexo = s['patient_sex'] as String?;
    });
  }

  Future<void> _salvar() async {
    await Servicos.of(context).banco.atualizarSessao(widget.sessaoId, {
      'patient': _nome.text.trim().isEmpty ? null : _nome.text.trim(),
      'patient_id': _pront.text.trim().isEmpty ? null : _pront.text.trim(),
      'patient_age': int.tryParse(_idade.text.trim()),
      'patient_sex': _sexo,
      'notes': _obs.text.trim().isEmpty ? null : _obs.text.trim(),
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dados do paciente salvos.')));
    _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final s = d.sessao;
    return Scaffold(
      appBar: AppBar(
        title: Text('Sessão #${s['id']}'),
        actions: [
          IconButton(
            tooltip: 'Gerar PDF',
            icon: const DeciIcone(DeciGlifo.pdf, tamanho: 26, cor: Cores.destaqueEscuro),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _TelaPdf(d))),
          ),
          IconButton(
            tooltip: 'Excluir sessão',
            icon: const DeciIcone(DeciGlifo.lixeira, cor: Cores.perigo),
            onPressed: () async {
              final ok = await confirmar(context, 'Excluir a sessão #${s['id']}?',
                  'A sessão e todas as suas medições serão apagadas. Isso não pode ser desfeito.');
              if (!ok || !context.mounted) return;
              await Servicos.of(context).banco.excluirSessao(widget.sessaoId);
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('${formatarData(s['inicio'] as String?)}${s['simulada'] == 1 ? ' · simulada' : ''} · ${s['dispositivo']}',
            style: const TextStyle(color: Cores.suave)),
        const SizedBox(height: 12),
        LinhaKpis([
            Kpi(rotulo: 'BPM médio', destaque: true, valor: Text(d.bpmMedio?.toStringAsFixed(1) ?? '--')),
            Kpi(
                rotulo: 'Classe predominante',
                valor: Padding(padding: const EdgeInsets.only(top: 2), child: TagClasse(s['classe_final'] as String?, grande: true))),
        ]),
        const SizedBox(height: 10),
        LinhaKpis([
            Kpi(rotulo: 'Medições válidas', valor: Text('${d.validas.length}/${d.medicoes.length}')),
            Kpi(rotulo: 'SDNN médio', valor: Text(d.sdnnMedio == null ? '--' : '${d.sdnnMedio!.toStringAsFixed(0)} ms')),
        ]),
        const SizedBox(height: 14),
        Secao(titulo: 'Batimentos por classe', filho: _Barras(d)),
        const SizedBox(height: 14),
        Secao(
          titulo: 'Identificação do paciente',
          filho: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: _nome, decoration: const InputDecoration(labelText: 'Nome')),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: _pront, decoration: const InputDecoration(labelText: 'Prontuário'))),
              const SizedBox(width: 10),
              SizedBox(width: 90, child: TextField(controller: _idade, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Idade'))),
            ]),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _sexo,
              decoration: const InputDecoration(labelText: 'Sexo'),
              items: [for (final e in sexos.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _sexo = v),
            ),
            const SizedBox(height: 10),
            TextField(controller: _obs, maxLines: 2, decoration: const InputDecoration(labelText: 'Observações')),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _salvar, child: const Text('Salvar alterações')),
          ]),
        ),
        const SizedBox(height: 14),
        Secao(
          titulo: 'Medições',
          filho: Column(children: [
            for (final m in d.medicoes)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => TelaDetalheMedicao(medicaoId: m.id)));
                    _carregar(); // pode ter sido excluída ou revisada
                  },
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text('#${m.id} · ${formatarHora(m.linha['criada'] as String?)}', style: const TextStyle(fontSize: 12.5)),
                      const Spacer(),
                      Text(m.erro ?? '${m.bpm?.toStringAsFixed(0)} bpm  ',
                          style: TextStyle(fontSize: 12.5, color: m.erro == null ? Cores.texto : Cores.aviso)),
                      if (m.erro == null) TagClasse(m.classe),
                    ]),
                    const SizedBox(height: 4),
                    GraficoEcg(sinal: m.filtrado, rpeaks: m.rpeaks, classePorPico: m.classes, altura: 80, rotulos: false),
                  ]),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        const Rodape(),
      ]),
    );
  }
}

class _Barras extends StatelessWidget {
  const _Barras(this.d);
  final DadosRelatorio d;
  @override
  Widget build(BuildContext context) {
    final total = d.totalBatimentos;
    if (total == 0) return const Text('Sem batimentos classificados.', style: TextStyle(color: Cores.suave));
    final itens = d.batimentosPorClasse.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Column(children: [
      for (final e in itens)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            SizedBox(width: 40, child: TagClasse(e.key)),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(value: e.value / total, minHeight: 10,
                    backgroundColor: Cores.painel2, color: corDaClasse(e.key)),
              ),
            ),
            SizedBox(width: 78, child: Text('${e.value} (${(100 * e.value / total).round()}%)',
                textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5, color: Cores.suave))),
          ]),
        ),
    ]);
  }
}

/// Pré-visualização do PDF com os botões de imprimir e compartilhar do pacote printing.
class _TelaPdf extends StatelessWidget {
  const _TelaPdf(this.d);
  final DadosRelatorio d;
  @override
  Widget build(BuildContext context) {
    final nome = 'DECI - Sessao ${d.sessao['id']}${d.sessao['patient'] != null ? ' - ${d.sessao['patient']}' : ''}.pdf';
    return Scaffold(
      appBar: AppBar(title: const Text('Relatório em PDF')),
      body: PdfPreview(
        build: (_) => gerarPdf(d),
        pdfFileName: nome,
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
      ),
    );
  }
}
