import 'package:flutter/material.dart';

import '../main.dart';
import '../ui/componentes.dart';
import '../ui/tema.dart';
import 'tela_detalhe_medicao.dart' show confirmar;
import 'tela_relatorio.dart';

class TelaResultados extends StatefulWidget {
  const TelaResultados({super.key});
  @override
  State<TelaResultados> createState() => _TelaResultadosState();
}

class _TelaResultadosState extends State<TelaResultados> {
  final _busca = TextEditingController();
  List<Map<String, Object?>> _sessoes = [];
  bool _carregando = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _carregar();
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    final r = await Servicos.of(context).banco.listarSessoes(busca: _busca.text.trim());
    if (mounted) setState(() { _sessoes = r; _carregando = false; });
  }

  @override
  Widget build(BuildContext context) {
    // recarrega quando uma medição nova é salva
    final monitor = Servicos.of(context).monitor;
    return Scaffold(
      appBar: AppBar(title: const Text('Resultados', style: TextStyle(fontWeight: FontWeight.w700))),
      body: ListenableBuilder(
        listenable: monitor,
        builder: (context, _) {
          if (monitor.daSessao.length != _ultimoTotal) {
            _ultimoTotal = monitor.daSessao.length;
            WidgetsBinding.instance.addPostFrameCallback((_) => _carregar());
          }
          return RefreshIndicator(
            onRefresh: _carregar,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              TextField(
                controller: _busca,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _carregar(),
                decoration: InputDecoration(
                  hintText: 'Buscar paciente, prontuário ou nº',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _busca.text.isEmpty
                      ? null
                      : IconButton(icon: const Icon(Icons.clear), onPressed: () { _busca.clear(); _carregar(); }),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              if (_carregando)
                const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()))
              else if (_sessoes.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(30),
                  child: Text(_busca.text.isEmpty ? 'Nenhuma sessão registrada ainda.' : 'Nenhuma sessão encontrada.',
                      textAlign: TextAlign.center, style: const TextStyle(color: Cores.suave)),
                )
              else
                for (final s in _sessoes) Padding(padding: const EdgeInsets.only(bottom: 10), child: _cartao(s)),
            ]),
          );
        },
      ),
    );
  }

  int _ultimoTotal = 0;

  Widget _cartao(Map<String, Object?> s) {
    final simulada = s['simulada'] == 1;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => TelaRelatorio(sessaoId: s['id'] as int)));
          _carregar();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('#${s['id']}', style: const TextStyle(color: Cores.suave, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text((s['patient'] as String?) ?? 'Não identificado',
                        overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  ),
                  if (simulada) ...[const SizedBox(width: 6), const _Selo('simulada')],
                ]),
                const SizedBox(height: 4),
                Text('${formatarData(s['inicio'] as String?)} · ${s['n_medicoes']} medições'
                    '${(s['n_erros'] as int? ?? 0) > 0 ? ' (${s['n_erros']} com erro)' : ''}'
                    ' · ${s['bpm_medio'] ?? '--'} bpm',
                    style: const TextStyle(color: Cores.suave, fontSize: 12.5)),
              ]),
            ),
            TagClasse(s['classe_final'] as String?),
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v != 'excluir') return;
                final ok = await confirmar(context, 'Excluir a sessão #${s['id']}?',
                    'A sessão e todas as suas medições serão apagadas. Isso não pode ser desfeito.');
                if (!ok) return;
                if (!mounted) return;
                await Servicos.of(context).banco.excluirSessao(s['id'] as int);
                _carregar();
              },
              itemBuilder: (_) => const [PopupMenuItem(value: 'excluir', child: Text('Excluir sessão'))],
            ),
          ]),
        ),
      ),
    );
  }
}

class _Selo extends StatelessWidget {
  const _Selo(this.texto);
  final String texto;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        decoration: BoxDecoration(color: Cores.avisoClaro, borderRadius: BorderRadius.circular(99)),
        child: Text(texto, style: const TextStyle(color: Cores.aviso, fontSize: 10.5, fontWeight: FontWeight.w600)),
      );
}
