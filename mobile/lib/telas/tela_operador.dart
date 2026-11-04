import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../main.dart';
import '../servicos/monitor.dart';
import '../ui/componentes.dart';
import '../ui/deci_marca.dart';
import '../ui/tema.dart';

class TelaOperador extends StatelessWidget {
  const TelaOperador({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Servicos.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Operador', style: TextStyle(fontWeight: FontWeight.w700))),
      body: ListenableBuilder(
        listenable: Listenable.merge([s.operador, s.monitor]),
        builder: (context, _) => ListView(padding: const EdgeInsets.all(16), children: [
          const _Modo(),
          if (s.operador.admin) ...[
            const SizedBox(height: 14),
            const _Simulador(),
            const SizedBox(height: 14),
            const _Configuracoes(),
            const SizedBox(height: 14),
            const _Dataset(),
            const SizedBox(height: 14),
            const _Sistema(),
          ],
          const SizedBox(height: 18),
          const Rodape(),
        ]),
      ),
    );
  }
}

class _Modo extends StatefulWidget {
  const _Modo();
  @override
  State<_Modo> createState() => _ModoState();
}

class _ModoState extends State<_Modo> {
  final _pin = TextEditingController();
  String? _erro;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final op = Servicos.of(context).operador;
    Widget opcao(String titulo, String texto, bool atual) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: atual ? Cores.destaqueClaro : Colors.white,
              border: Border.all(color: atual ? Cores.destaque : Cores.linhaForte),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(texto, style: const TextStyle(fontSize: 12, color: Cores.suave)),
            ]),
          ),
        );
    return Secao(
      titulo: 'Modo de operação',
      filho: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            opcao('Paciente', 'Só realiza medições com o ECG. Sem acesso aos resultados.', !op.admin),
            const SizedBox(width: 10),
            opcao('Administrador', 'Resultados, PDF, exclusões, revisão de rótulos, simulador e dataset.', op.admin),
          ]),
        ),
        const SizedBox(height: 14),
        if (op.admin)
          OutlinedButton.icon(onPressed: op.sair, icon: const DeciIcone(DeciGlifo.sair, tamanho: 20), label: const Text('Mudar para modo paciente'))
        else ...[
          TextField(
            controller: _pin,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 8,
            decoration: InputDecoration(
              labelText: op.temPin ? 'PIN do administrador' : 'Crie um PIN de administrador (4 a 8 dígitos)',
              errorText: _erro,
              counterText: '',
            ),
            onSubmitted: (_) => _entrar(),
          ),
          const SizedBox(height: 10),
          FilledButton(onPressed: _entrar, child: Text(op.temPin ? 'Entrar como administrador' : 'Criar PIN e entrar')),
        ],
      ]),
    );
  }

  void _entrar() {
    final op = Servicos.of(context).operador;
    final pin = _pin.text.trim();
    if (!RegExp(r'^\d{4,8}$').hasMatch(pin)) {
      setState(() => _erro = 'Use de 4 a 8 dígitos.');
      return;
    }
    if (!op.entrar(pin)) {
      setState(() => _erro = 'PIN incorreto.');
      return;
    }
    _pin.clear();
    setState(() => _erro = null);
    FocusScope.of(context).unfocus();
  }
}

class _Simulador extends StatefulWidget {
  const _Simulador();
  @override
  State<_Simulador> createState() => _SimuladorState();
}

class _SimuladorState extends State<_Simulador> {
  double _bpm = 72;
  double _ruido = 0.03;
  bool _extras = false;

  @override
  Widget build(BuildContext context) {
    final m = Servicos.of(context).monitor;
    final ativo = m.fonte == Fonte.simulador;
    return Secao(
      titulo: 'Simulador de ECG',
      filho: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Gera um ECG sintético em tempo real, como se viesse do ESP, para testar o app. '
            'Sessões simuladas ficam marcadas e não entram no dataset de treino.',
            style: TextStyle(color: Cores.suave, fontSize: 12.5)),
        const SizedBox(height: 8),
        Text('Frequência: ${_bpm.round()} bpm'),
        Slider(value: _bpm, min: 40, max: 160, divisions: 24, onChanged: ativo ? null : (v) => setState(() => _bpm = v)),
        Text('Ruído: ${switch (_ruido) { < 0.02 => 'baixo', < 0.06 => 'médio', _ => 'alto' }}'),
        Slider(value: _ruido, min: 0.01, max: 0.12, onChanged: ativo ? null : (v) => setState(() => _ruido = v)),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Incluir extrassístoles ventriculares'),
          value: _extras,
          onChanged: ativo ? null : (v) => setState(() => _extras = v),
        ),
        const SizedBox(height: 6),
        ativo
            ? OutlinedButton.icon(onPressed: m.pararSimulador, icon: const DeciIcone(DeciGlifo.stop, tamanho: 20), label: const Text('Parar simulador'))
            : FilledButton.icon(
                onPressed: () {
                  m.iniciarSimulador(bpm: _bpm, ruido: _ruido, extrassistoles: _extras);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Simulador ligado. Vá para a aba Medição e inicie uma medição.')));
                },
                icon: const DeciIcone(DeciGlifo.play, tamanho: 20),
                label: const Text('Ligar simulador'),
              ),
      ]),
    );
  }
}

class _Configuracoes extends StatelessWidget {
  const _Configuracoes();
  @override
  Widget build(BuildContext context) {
    final s = Servicos.of(context);
    final n = s.operador.medicoesPorSessao;
    return Secao(
      titulo: 'Medições por sessão',
      filho: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$n medições de 10 s (${n * 10 ~/ 60} min ${n * 10 % 60} s)'),
        Slider(
          value: n.toDouble(),
          min: 1,
          max: 30,
          divisions: 29,
          label: '$n',
          onChanged: s.monitor.medindo
              ? null
              : (v) {
                  s.operador.setMedicoesPorSessao(v.round());
                  s.monitor.medicoesPorSessao = v.round();
                },
        ),
      ]),
    );
  }
}

class _Dataset extends StatefulWidget {
  const _Dataset();
  @override
  State<_Dataset> createState() => _DatasetState();
}

class _DatasetState extends State<_Dataset> {
  Map<String, Object?>? _st;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    Servicos.of(context).banco.estatisticas().then((v) => mounted ? setState(() => _st = v) : null);
  }

  Future<void> _exportar(bool revisados) async {
    final csv = await Servicos.of(context).banco.exportarCsv(somenteRevisados: revisados);
    final dir = await getTemporaryDirectory();
    final arq = File('${dir.path}/icecg_dataset${revisados ? '_revisados' : ''}.csv');
    await arq.writeAsString(csv);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(arq.path, mimeType: 'text/csv')],
      subject: 'DECI — dataset de batimentos',
      text: 'Colunas compatíveis com ml/treinar.py',
    ));
  }

  @override
  Widget build(BuildContext context) {
    final st = _st;
    return Secao(
      titulo: 'Dataset para treino',
      filho: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(st == null
            ? 'Carregando…'
            : '${st['sessoes']} sessões reais (${st['simuladas']} simuladas, fora do dataset) · '
                '${st['medicoes']} medições · ${st['batimentos']} batimentos · ${st['revisados']} revisados'),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: () => _exportar(true), icon: const DeciIcone(DeciGlifo.compartilhar, tamanho: 20), label: const Text('Exportar só revisados')),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: () => _exportar(false), child: const Text('Exportar todos (rótulo previsto)')),
        const SizedBox(height: 6),
        const Text('Use os revisados para treinar: os previstos repetem os erros do modelo atual.',
            style: TextStyle(color: Cores.suave, fontSize: 12)),
      ]),
    );
  }
}

class _Sistema extends StatelessWidget {
  const _Sistema();
  @override
  Widget build(BuildContext context) {
    final s = Servicos.of(context);
    Widget linha(String a, String b) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(width: 120, child: Text(a, style: const TextStyle(color: Cores.suave))),
            Expanded(child: Text(b)),
          ]),
        );
    return Secao(
      titulo: 'Sistema',
      filho: Column(children: [
        linha('Modelo', 'Random Forest, ${s.modelo.nArvores} árvores'),
        linha('Classes', s.modelo.classes.join(', ')),
        linha('Treinado em', formatarData(s.modelo.treinadoEm)),
        linha('Batimentos', '${s.modelo.nBatimentosTreino} (MIT-BIH a 100 Hz)'),
        linha('ECG', s.ble.conectado ? '${s.ble.nomeConectado} · firmware v${s.ble.versaoFirmware ?? '?'}' : 'desconectado'),
      ]),
    );
  }
}
