import 'dart:convert';

import 'package:flutter/material.dart';

import '../main.dart';
import '../pipeline/pipeline_ecg.dart' as pipe;
import '../ui/componentes.dart';
import '../ui/grafico_ecg.dart';
import '../ui/deci_marca.dart';
import '../ui/tema.dart';

class TelaDetalheMedicao extends StatefulWidget {
  const TelaDetalheMedicao({super.key, required this.medicaoId});
  final int medicaoId;
  @override
  State<TelaDetalheMedicao> createState() => _TelaDetalheMedicaoState();
}

class _TelaDetalheMedicaoState extends State<TelaDetalheMedicao> {
  Map<String, Object?>? _m;
  List<Map<String, Object?>> _bats = [];
  List<double> _filtrado = const [];
  List<int> _rpeaks = const [];
  int? _destaque;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_m == null) _carregar();
  }

  Future<void> _carregar() async {
    final banco = Servicos.of(context).banco;
    final r = await banco.db.query('medicoes', where: 'id = ?', whereArgs: [widget.medicaoId]);
    if (r.isEmpty) return;
    final m = r.first;
    final sinal = (jsonDecode(m['sinal'] as String) as List).cast<int>();
    List<double> filtrado = const [];
    try {
      filtrado = pipe.preparar([for (final a in sinal) a * 3.3 / 4095]);
    } on pipe.ErroSinal {
      filtrado = [for (final a in sinal) a * 3.3 / 4095];
    }
    final bats = await banco.batimentos(widget.medicaoId);
    setState(() {
      _m = m;
      _filtrado = filtrado;
      _rpeaks = m['rpeaks'] == null ? const [] : (jsonDecode(m['rpeaks'] as String) as List).cast<int>();
      _bats = bats.map((b) => Map<String, Object?>.of(b)).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = Servicos.of(context);
    final admin = s.operador.admin;
    final m = _m;
    if (m == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final vfc = m['vfc'] == null ? const {} : jsonDecode(m['vfc'] as String) as Map;
    final classes = {for (final b in _bats) b['r_sample'] as int: (b['true_label'] ?? b['pred_label']) as String};
    return Scaffold(
      appBar: AppBar(
        title: Text('Medição #${m['id']}'),
        actions: [
          if (admin)
            IconButton(
              tooltip: 'Excluir medição',
              icon: const DeciIcone(DeciGlifo.lixeira, cor: Cores.perigo),
              onPressed: () async {
                final ok = await confirmar(context, 'Excluir a medição #${m['id']}?',
                    'A medição e seus batimentos serão apagados. Se for a última da sessão, a sessão também será.');
                if (!ok || !context.mounted) return;
                await s.banco.excluirMedicao(m['id'] as int);
                if (context.mounted) Navigator.pop(context, true);
              },
            ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(formatarData(m['criada'] as String?), style: const TextStyle(color: Cores.suave)),
        const SizedBox(height: 10),
        GraficoEcg(sinal: _filtrado, rpeaks: _rpeaks, classePorPico: classes, altura: 230, destaque: _destaque),
        const SizedBox(height: 12),
        if (m['erro'] != null)
          Caixa('Erro: ${m['erro']}', tipo: 'aviso')
        else
          Wrap(spacing: 14, runSpacing: 6, children: [
            Text('${(m['bpm'] as num?)?.toStringAsFixed(1) ?? '--'} bpm', style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('SDNN ${vfc['sdnn_ms'] ?? '--'} ms'),
            Text('RMSSD ${vfc['rmssd_ms'] ?? '--'} ms'),
          ]),
        if (admin && _bats.isNotEmpty) ...[
          const SizedBox(height: 14),
          Row(children: [
            const Expanded(child: Text('Rotular todos os batimentos como:', style: TextStyle(fontSize: 13))),
            for (final c in descricaoClasse.keys)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: InkWell(
                  onTap: () async {
                    await s.banco.rotularMedicao(m['id'] as int, c);
                    _carregar();
                  },
                  child: TagClasse(c),
                ),
              ),
          ]),
        ],
        const SizedBox(height: 14),
        Card(
          child: Column(children: [
            for (var i = 0; i < _bats.length; i++) _linhaBatimento(i, _bats[i], admin),
            if (_bats.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('Nenhum batimento extraído.')),
          ]),
        ),
        if (admin)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text('Rótulos revisados viram dados de treino (Operador → Exportar dataset).',
                style: TextStyle(color: Cores.suave, fontSize: 12)),
          ),
      ]),
    );
  }

  Widget _linhaBatimento(int i, Map<String, Object?> b, bool admin) {
    final r = b['r_sample'] as int;
    final conf = ((b['confidence'] as num?) ?? 0) * 100;
    return ListTile(
      dense: true,
      selected: _destaque == r,
      selectedTileColor: Cores.destaqueClaro,
      onTap: () => setState(() => _destaque = r),
      leading: Text('${i + 1}', style: const TextStyle(color: Cores.suave)),
      title: Row(children: [
        TagClasse(b['pred_label'] as String?),
        const SizedBox(width: 8),
        Text('${conf.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 12, color: Cores.suave)),
      ]),
      subtitle: Text('t ${(r / pipe.fs).toStringAsFixed(2)} s · RR ${(b['rr_interval'] as num).toStringAsFixed(3)} s · '
          '${(b['heart_rate'] as num).toStringAsFixed(0)} bpm'),
      trailing: admin
          ? DropdownButton<String?>(
              value: b['true_label'] as String?,
              hint: const Text('revisar', style: TextStyle(fontSize: 12.5)),
              underline: const SizedBox(),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('—')),
                for (final c in descricaoClasse.keys) DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (v) async {
                await Servicos.of(context).banco.rotular(b['id'] as int, v);
                setState(() => b['true_label'] = v);
              },
            )
          : null,
    );
  }
}

Future<bool> confirmar(BuildContext context, String titulo, String texto, {String ok = 'Excluir'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(titulo),
      content: Text(texto),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Cores.perigo),
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}
