// Simulador de arritmias: escolhe o ritmo, vê o ECG ao vivo e confere o que o modelo classificou.
import 'package:flutter/material.dart';

import '../main.dart';
import '../servicos/simulacao.dart';
import '../servicos/simulador.dart';
import '../ui/componentes.dart';
import '../ui/deci_marca.dart';
import '../ui/grafico_ecg.dart';
import '../ui/tema.dart';

const _nomesGrupo = {
  GrupoRitmo.sinusal: 'Ritmo sinusal',
  GrupoRitmo.extrassistoles: 'Extrassístoles',
  GrupoRitmo.taquiarritmias: 'Taquiarritmias',
  GrupoRitmo.bloqueios: 'Bloqueios',
};

class TelaSimulador extends StatefulWidget {
  const TelaSimulador({super.key});
  @override
  State<TelaSimulador> createState() => _TelaSimuladorState();
}

class _TelaSimuladorState extends State<TelaSimulador> {
  Simulacao? _sim;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sim ??= Simulacao(Servicos.of(context).modelo);
  }

  @override
  void dispose() {
    _sim?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sim = _sim!;
    return Scaffold(
      appBar: AppBar(title: const Text('Simular arritmias')),
      body: ListenableBuilder(
        listenable: sim,
        builder: (context, _) => ListaResponsiva(
          children: [
            Secao(titulo: 'Ritmo', filho: _Ritmos(sim)),
            const SizedBox(height: 14),
            _Parametros(sim),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: sim.rodando ? sim.parar : sim.iniciar,
              icon: DeciIcone(sim.rodando ? DeciGlifo.stop : DeciGlifo.play, tamanho: 22),
              label: Text(sim.rodando ? 'Parar simulação' : 'Iniciar simulação'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 56), shape: const StadiumBorder()),
            ),
            const SizedBox(height: 14),
            Secao(
              titulo: 'ECG simulado ao vivo',
              acao: sim.rodando
                  ? Text(
                      'próxima análise em ${(10 - sim.progresso * 10).ceil()} s',
                      style: const TextStyle(color: Cores.suave, fontSize: 12.5),
                    )
                  : null,
              filho: GraficoEcg(
                sinal: sim.monitor,
                cursor: sim.rodando ? sim.cursor : null,
                rotulos: false,
                altura: 190,
                mensagemVazio: 'Escolha um ritmo e toque em Iniciar',
              ),
            ),
            if (sim.ultima != null) ...[const SizedBox(height: 14), _Janela(sim.ultima!)],
            if (sim.total > 0) ...[const SizedBox(height: 14), _Desempenho(sim)],
            const SizedBox(height: 10),
            const Text(
              'Sinais sintéticos para teste e ensino. Nada aqui é gravado no banco de dados.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Cores.suave, fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _Ritmos extends StatelessWidget {
  const _Ritmos(this.sim);
  final Simulacao sim;

  @override
  Widget build(BuildContext context) {
    final r = sim.ritmo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final g in GrupoRitmo.values) ...[
          Text(
            _nomesGrupo[g]!.toUpperCase(),
            style: const TextStyle(fontSize: 11, letterSpacing: .6, color: Cores.suave, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final x in Ritmo.values.where((x) => x.grupo == g))
                // nomes longos não podem passar da largura da tela (celular estreito ou fonte grande)
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: (MediaQuery.sizeOf(context).width - 64).clamp(120, 600)),
                  child: ChoiceChip(
                    label: Text(x.nome, overflow: TextOverflow.ellipsis),
                    selected: r == x,
                    onSelected: (_) => sim.escolher(x),
                    showCheckmark: false,
                    // cor explícita por estado (sem isso o M3 mistura o rosa com branco e o texto some)
                    color: WidgetStateProperty.resolveWith(
                      (e) => e.contains(WidgetState.selected) ? Cores.destaque : Colors.white,
                    ),
                    labelStyle: TextStyle(
                      fontSize: 13,
                      color: r == x ? Colors.white : Cores.texto,
                      fontWeight: r == x ? FontWeight.w700 : FontWeight.w500,
                    ),
                    side: BorderSide(color: r == x ? Cores.destaque : Cores.linhaForte),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Cores.painel2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Cores.linha),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r.nome, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 4),
              Text(r.descricao, style: const TextStyle(fontSize: 13, height: 1.35)),
              const SizedBox(height: 8),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 4,
                children: [
                  const Text('O modelo deve ver: ', style: TextStyle(fontSize: 12.5, color: Cores.suave)),
                  for (final c in ['N', 'S', 'V', 'F'].where(r.classesEsperadas.contains))
                    Padding(padding: const EdgeInsets.only(right: 4), child: TagClasse(c)),
                ],
              ),
              if (r.soRitmo) ...[
                const SizedBox(height: 8),
                const Text(
                  'O modelo classifica cada batimento (N, S, V, F), não o ritmo. Aqui os batimentos são N; '
                  'a arritmia aparece na irregularidade do RR e nas pausas.',
                  style: TextStyle(fontSize: 12, color: Cores.suave, height: 1.35),
                ),
              ],
              if (r.classesEsperadas.contains('S') || r.classesEsperadas.contains('F')) ...[
                const SizedBox(height: 8),
                const Caixa(
                  'Limitação conhecida: o modelo atual quase não reconhece batimentos S e F '
                  '(também em pacientes reais do MIT-BIH).',
                  tipo: 'aviso',
                  icone: DeciGlifo.alerta,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Parametros extends StatelessWidget {
  const _Parametros(this.sim);
  final Simulacao sim;

  @override
  Widget build(BuildContext context) {
    final nivel = switch (sim.ruido) {
      < 0.02 => 'baixo',
      < 0.06 => 'médio',
      _ => 'alto',
    };
    return Secao(
      titulo: 'Parâmetros',
      filho: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sim.ritmo.usaBpm) ...[
            Text('Frequência: ${sim.bpm.round()} bpm'),
            Slider(
              value: sim.bpm.clamp(30, 180),
              min: 30,
              max: 180,
              divisions: 30,
              onChanged: (v) => sim.ajustar(bpm: v),
              onChangeEnd: (_) => sim.rodando ? sim.iniciar() : null,
            ),
          ] else
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'A frequência é definida pelo próprio ritmo.',
                style: TextStyle(color: Cores.suave, fontSize: 13),
              ),
            ),
          Text('Ruído: $nivel'),
          Slider(
            value: sim.ruido,
            min: 0.005,
            max: 0.12,
            onChanged: (v) => sim.ajustar(ruido: v),
            onChangeEnd: (_) => sim.rodando ? sim.iniciar() : null,
          ),
        ],
      ),
    );
  }
}

class _Janela extends StatelessWidget {
  const _Janela(this.j);
  final JanelaSimulada j;

  @override
  Widget build(BuildContext context) {
    final dist = <String, int>{};
    for (final c in j.previsto.values) {
      dist[c] = (dist[c] ?? 0) + 1;
    }
    final irregular = (j.cvRR ?? 0) > 0.1;
    return Secao(
      titulo: 'Última análise (10 s)',
      acao: Wrap(spacing: 4, children: [for (final e in dist.entries) TagClasse(e.key, extra: ' ${e.value}')]),
      filho: j.erro != null
          ? Caixa(j.erro!, tipo: 'aviso')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GraficoEcg(
                  sinal: j.filtrado,
                  rpeaks: j.rpeaks,
                  classePorPico: j.previsto,
                  errados: j.errados,
                  altura: 190,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${j.bpm?.toStringAsFixed(0) ?? '--'} bpm',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'RR ${irregular ? 'irregular' : 'regular'} (variação ${((j.cvRR ?? 0) * 100).toStringAsFixed(0)}%)',
                      style: TextStyle(color: irregular ? Cores.aviso : Cores.suave),
                    ),
                    if (j.errados.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Cores.perigo, width: 2),
                            ),
                          ),
                          Text(
                            '  modelo errou (${j.errados.length})',
                            style: const TextStyle(color: Cores.perigo, fontSize: 12.5),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _Desempenho extends StatelessWidget {
  const _Desempenho(this.sim);
  final Simulacao sim;

  @override
  Widget build(BuildContext context) {
    final pct = 100 * sim.acertos / sim.total;
    return Secao(
      titulo: 'Desempenho do modelo nesta simulação',
      filho: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${sim.acertos} de ${sim.total} batimentos corretos (${pct.toStringAsFixed(0)}%)',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          for (final c in ['N', 'S', 'V', 'F'].where(sim.confusao.containsKey))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(width: 44, child: TagClasse(c)),
                  const Text('previstos: ', style: TextStyle(color: Cores.suave, fontSize: 12.5)),
                  Expanded(
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final e in (sim.confusao[c]!.entries.toList()..sort((a, b) => b.value.compareTo(a.value))))
                          TagClasse(e.key, extra: ' ${e.value}'),
                      ],
                    ),
                  ),
                  Text(
                    '${(100 * (sim.confusao[c]![c] ?? 0) / sim.confusao[c]!.values.fold(0, (a, b) => a + b)).round()}%',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
