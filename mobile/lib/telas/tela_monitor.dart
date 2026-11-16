// Monitor da sessão em andamento: traçado ao vivo, resultado de cada janela de 10 s e resumo no fim.
// Voltar não interrompe a medição (a tela inicial mostra "Ver medição").
import 'package:flutter/material.dart';

import '../dados/banco.dart';
import '../main.dart';
import '../servicos/monitor.dart';
import '../ui/cabecalho.dart';
import '../ui/componentes.dart';
import '../ui/deci_marca.dart';
import '../ui/grafico_ecg.dart';
import '../ui/tema.dart';
import 'tela_detalhe_medicao.dart';
import 'tela_relatorio.dart';

class TelaMonitor extends StatelessWidget {
  const TelaMonitor({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Servicos.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Monitor'), actions: const [PilulaEcg()]),
      body: ListenableBuilder(
        listenable: Listenable.merge([s.monitor, s.ble]),
        builder: (context, _) {
          final m = s.monitor;
          final concluida = !m.medindo && m.sessaoConcluida != null;
          return ListaResponsiva(children: [
            _Cabecalho(m),
            const SizedBox(height: 14),
            if (concluida) ...[_Resumo(m), const SizedBox(height: 14)],
            if (m.aviso != null) ...[Caixa(m.aviso!, tipo: 'aviso', icone: DeciGlifo.alerta), const SizedBox(height: 14)],
            if (s.ble.eletrodoSolto && m.fonte == Fonte.ble) ...[
              const Caixa('Eletrodo solto — confira a colocação dos eletrodos.', tipo: 'erro', icone: DeciGlifo.alerta),
              const SizedBox(height: 14),
            ],
            _Indicadores(m),
            const SizedBox(height: 14),
            Secao(
              titulo: 'Eletrocardiograma ao vivo',
              acao: m.fonte != Fonte.nenhuma ? Text(m.nomeFonte, style: const TextStyle(color: Cores.suave, fontSize: 12.5)) : null,
              filho: GraficoEcg(
                sinal: m.monitor,
                cursor: m.fonte == Fonte.nenhuma ? null : m.cursor,
                rotulos: false,
                altura: 200,
                mensagemVazio: 'Sem sinal do ECG',
              ),
            ),
            if (m.ultima != null) ...[const SizedBox(height: 14), _UltimaMedicao(m.ultima!)],
            if (m.daSessao.length > 1) ...[const SizedBox(height: 14), _FaixaSessao(m)],
            const SizedBox(height: 14),
            const Text('Trabalho científico: as classificações podem conter erros e não substituem a avaliação '
                'de um profissional de saúde.',
                textAlign: TextAlign.center, style: TextStyle(color: Cores.suave, fontSize: 11.5)),
          ]);
        },
      ),
    );
  }
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho(this.m);
  final Monitor m;

  @override
  Widget build(BuildContext context) {
    final p = m.paciente;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: Cores.destaqueClaro,
              child: Text(_iniciais(p?.nome ?? '?'),
                  style: const TextStyle(color: Cores.destaqueEscuro, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p?.nome ?? 'Paciente não identificado', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                Text(_meta(p), style: const TextStyle(color: Cores.suave, fontSize: 12.5)),
              ]),
            ),
            if (m.medindo) TextButton(onPressed: m.encerrarSessao, child: const Text('Encerrar')),
          ]),
          const SizedBox(height: 14),
          Text(
            m.medindo
                ? 'Medição ${m.medicoesFeitas + 1} de ${m.medicoesPorSessao} — fique parado e respire normalmente'
                : 'Medição concluída',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: m.medindo ? (m.medicoesFeitas + m.progressoBloco) / m.medicoesPorSessao : 1,
              minHeight: 8,
              backgroundColor: Cores.painel2,
            ),
          ),
        ]),
      ),
    );
  }

  static String _iniciais(String n) =>
      n.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).take(2).map((s) => s[0].toUpperCase()).join();
  static String _meta(Paciente? p) {
    if (p == null) return '';
    final partes = [
      if (p.prontuario != null) 'Prontuário ${p.prontuario}',
      if (p.idade != null) '${p.idade} anos',
      if (p.sexo != null) sexos[p.sexo]!,
    ];
    return partes.isEmpty ? 'Sem dados adicionais' : partes.join(' · ');
  }
}

class _Resumo extends StatelessWidget {
  const _Resumo(this.m);
  final Monitor m;
  @override
  Widget build(BuildContext context) {
    final admin = Servicos.of(context).operador.admin;
    final contagem = <String, int>{};
    for (final u in m.daSessao) {
      u.distribuicao.forEach((c, n) => contagem[c] = (contagem[c] ?? 0) + n);
    }
    final bpms = m.daSessao.map((u) => u.bpm).whereType<double>().toList();
    final bpm = bpms.isEmpty ? null : bpms.reduce((a, b) => a + b) / bpms.length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Cores.destaqueClaro,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Cores.destaque.withValues(alpha: .4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Row(children: [
          Mascote(tamanho: 44, brilho: false),
          SizedBox(width: 12),
          Expanded(child: Text('Medição concluída!', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 10),
        Text('${m.daSessao.length} janelas de 10 s · BPM médio ${bpm?.toStringAsFixed(0) ?? '--'}'),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final e in (contagem.entries.toList()..sort((a, b) => b.value.compareTo(a.value))))
            TagClasse(e.key, extra: ' ${e.value}'),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          if (admin)
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(backgroundColor: Colors.white),
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => TelaRelatorio(sessaoId: m.sessaoConcluida!))),
                child: const Text('Ver relatório'),
              ),
            ),
          if (admin) const SizedBox(width: 10),
          Expanded(child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Concluir'))),
        ]),
      ]),
    );
  }
}

class _Indicadores extends StatelessWidget {
  const _Indicadores(this.m);
  final Monitor m;
  @override
  Widget build(BuildContext context) {
    final u = m.ultima;
    return LinhaKpis([
      Kpi(rotulo: 'Frequência', destaque: true, valor: Text(u?.bpm?.toStringAsFixed(0) ?? '--'), sub: 'bpm'),
      Kpi(
        rotulo: 'Classe',
        valor: u?.classe == null
            ? const Text('--')
            : Padding(padding: const EdgeInsets.only(top: 4), child: TagClasse(u!.classe, grande: true)),
        sub: u?.classe == null ? (u?.erro ?? 'aguardando') : descricaoClasse[u!.classe],
      ),
      Kpi(
        rotulo: 'Janelas',
        valor: Text('${m.medicoesFeitas}/${m.medicoesPorSessao}'),
        sub: m.medindo ? '${(m.progressoBloco * 10).floor()} de 10 s' : 'concluída',
      ),
    ]);
  }
}

class _UltimaMedicao extends StatelessWidget {
  const _UltimaMedicao(this.u);
  final MedicaoClassificada u;
  @override
  Widget build(BuildContext context) {
    return Secao(
      titulo: 'Última janela (10 s)',
      acao: Wrap(spacing: 4, children: [for (final e in u.distribuicao.entries) TagClasse(e.key, extra: ' ${e.value}')]),
      filho: u.erro != null
          ? Caixa(u.erro!, tipo: 'aviso')
          : InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TelaDetalheMedicao(medicaoId: u.id))),
              child: GraficoEcg(sinal: u.filtrado, rpeaks: u.rpeaks, classePorPico: u.classePorPico, altura: 190),
            ),
    );
  }
}

class _FaixaSessao extends StatelessWidget {
  const _FaixaSessao(this.m);
  final Monitor m;
  @override
  Widget build(BuildContext context) {
    final lista = m.daSessao.reversed.toList();
    return Secao(
      titulo: 'Janelas desta sessão',
      filho: SizedBox(
        height: 86,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: lista.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final u = lista[i];
            return InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TelaDetalheMedicao(medicaoId: u.id))),
              child: Container(
                width: 150,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    border: Border.all(color: i == 0 ? Cores.destaque : Cores.linha), borderRadius: BorderRadius.circular(10)),
                child: Column(children: [
                  Expanded(
                      child: GraficoEcg(sinal: u.filtrado, rpeaks: u.rpeaks, classePorPico: u.classePorPico,
                          grade: false, rotulos: false, altura: 48, mensagemVazio: u.erro ?? '')),
                  const SizedBox(height: 4),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(u.bpm == null ? 'erro' : '${u.bpm!.toStringAsFixed(0)} bpm', style: const TextStyle(fontSize: 11.5)),
                    TagClasse(u.classe),
                  ]),
                ]),
              ),
            );
          },
        ),
      ),
    );
  }
}
