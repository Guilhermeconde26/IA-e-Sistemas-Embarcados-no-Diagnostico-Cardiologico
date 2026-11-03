import 'package:flutter/material.dart';

import '../ble/ecg_ble.dart';
import '../dados/banco.dart';
import '../main.dart';
import '../servicos/monitor.dart';
import '../ui/componentes.dart';
import '../ui/grafico_ecg.dart';
import '../ui/tema.dart';
import 'tela_detalhe_medicao.dart';

class TelaMedicao extends StatelessWidget {
  const TelaMedicao({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Servicos.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const _Marca(),
        actions: [
          ListenableBuilder(listenable: s.ble, builder: (_, _) => _PilulaEcg(s.monitor, s.ble)),
          const SizedBox(width: 12),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([s.monitor, s.ble]),
        builder: (context, _) {
          final m = s.monitor;
          return ListView(padding: const EdgeInsets.all(16), children: [
            if (m.fonte == Fonte.nenhuma) ...[const _CartaoConectar(), const SizedBox(height: 14)],
            const _CartaoPaciente(),
            const SizedBox(height: 14),
            if (m.aviso != null) ...[Caixa(m.aviso!, tipo: 'aviso', icone: Icons.warning_amber), const SizedBox(height: 14)],
            if (s.ble.eletrodoSolto && m.fonte == Fonte.ble) ...[
              const Caixa('Eletrodo solto — confira a colocação dos eletrodos.', tipo: 'erro', icone: Icons.link_off),
              const SizedBox(height: 14),
            ],
            _Indicadores(m),
            const SizedBox(height: 14),
            Secao(
              titulo: 'Eletrocardiograma ao vivo',
              acao: m.fonte != Fonte.nenhuma
                  ? Text(m.nomeFonte, style: const TextStyle(color: Cores.suave, fontSize: 12.5))
                  : null,
              filho: GraficoEcg(
                sinal: m.monitor,
                cursor: m.fonte == Fonte.nenhuma ? null : m.cursor,
                rotulos: false,
                altura: 200,
                mensagemVazio: 'Conecte o ECG para ver o sinal',
              ),
            ),
            if (m.ultima != null) ...[const SizedBox(height: 14), _UltimaMedicao(m.ultima!)],
            if (m.daSessao.length > 1) ...[const SizedBox(height: 14), _FaixaSessao(m)],
            const SizedBox(height: 18),
            const Rodape(),
          ]);
        },
      ),
    );
  }
}

class _Marca extends StatelessWidget {
  const _Marca();
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: Cores.verdeClaro, borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.monitor_heart, color: Cores.verde, size: 20),
        ),
        const SizedBox(width: 10),
        const Flexible(
          child: Text.rich(TextSpan(children: [
            TextSpan(text: 'IC ', style: TextStyle(fontWeight: FontWeight.w800)),
            TextSpan(text: 'ECG', style: TextStyle(fontWeight: FontWeight.w800, color: Cores.verdeEscuro)),
          ]), style: TextStyle(fontSize: 19), overflow: TextOverflow.fade, softWrap: false),
        ),
      ]);
}

/// Indicador do ECG no topo: verde = recebendo sinal, cinza = desconectado.
class _PilulaEcg extends StatelessWidget {
  const _PilulaEcg(this.m, this.ble);
  final Monitor m;
  final EcgBle ble;
  @override
  Widget build(BuildContext context) {
    final (texto, cor, fundo) = switch (m.fonte) {
      Fonte.ble => (ble.nomeConectado ?? 'ECG', Cores.verdeEscuro, Cores.verdeClaro),
      Fonte.simulador => ('Simulador', Cores.aviso, Cores.avisoClaro),
      Fonte.nenhuma => ('ECG offline', Cores.suave, Colors.white),
    };
    return InkWell(
      borderRadius: BorderRadius.circular(99),
      onTap: m.fonte == Fonte.ble ? () => _detalhesBle(context, ble) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: fundo, borderRadius: BorderRadius.circular(99), border: Border.all(color: Cores.linhaForte)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.memory, size: 16, color: cor),
          const SizedBox(width: 5),
          Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle,
              color: m.fonte == Fonte.nenhuma ? Cores.linhaForte : (m.fonte == Fonte.ble ? Cores.verde : Cores.aviso))),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 110),
            child: Text(texto, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cor)),
          ),
        ]),
      ),
    );
  }

  void _detalhesBle(BuildContext context, EcgBle ble) {
    final total = ble.pacotesRecebidos + ble.pacotesPerdidos;
    final perda = total == 0 ? 0 : ble.pacotesPerdidos * 100 / total;
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(ble.nomeConectado ?? 'ECG'),
        content: Text('Firmware v${ble.versaoFirmware ?? '?'}\n'
            'Pacotes recebidos: ${ble.pacotesRecebidos}\n'
            'Pacotes perdidos: ${ble.pacotesPerdidos} (${perda.toStringAsFixed(1)}%)\n'
            'Eletrodos: ${ble.eletrodoSolto ? 'soltos' : 'ok'}'),
        actions: [
          TextButton(onPressed: () { ble.desconectar(); Navigator.pop(c); }, child: const Text('Desconectar')),
          FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK')),
        ],
      ),
    );
  }
}

class _CartaoConectar extends StatelessWidget {
  const _CartaoConectar();
  @override
  Widget build(BuildContext context) {
    final ble = Servicos.of(context).ble;
    final ocupado = ble.estado == EstadoBle.procurando || ble.estado == EstadoBle.conectando;
    return Secao(
      titulo: 'Conectar ao ECG',
      filho: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Ligue o ECG e mantenha o celular por perto. A conexão é por Bluetooth — '
            'não precisa de Wi-Fi nem internet.', style: TextStyle(color: Cores.suave, fontSize: 13.5)),
        if (ble.erro != null) ...[const SizedBox(height: 10), Caixa(ble.erro!, tipo: 'erro', icone: Icons.bluetooth_disabled)],
        const SizedBox(height: 12),
        for (final d in ble.encontrados)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton.icon(
              onPressed: ocupado && ble.estado == EstadoBle.conectando ? null : () => ble.conectar(d),
              icon: const Icon(Icons.bluetooth),
              label: Row(children: [
                Expanded(child: Text(d.nome)),
                Text('${d.rssi} dBm', style: const TextStyle(color: Cores.suave, fontSize: 12)),
              ]),
            ),
          ),
        if (ble.estado == EstadoBle.procurando && ble.encontrados.isEmpty)
          const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('Procurando…', textAlign: TextAlign.center)),
        FilledButton.icon(
          onPressed: ocupado ? null : ble.procurar,
          icon: ocupado
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.bluetooth_searching),
          label: Text(switch (ble.estado) {
            EstadoBle.procurando => 'Procurando…',
            EstadoBle.conectando => 'Conectando…',
            _ => ble.encontrados.isEmpty ? 'Procurar ECG' : 'Procurar de novo',
          }),
        ),
      ]),
    );
  }
}

class _CartaoPaciente extends StatefulWidget {
  const _CartaoPaciente();
  @override
  State<_CartaoPaciente> createState() => _CartaoPacienteState();
}

class _CartaoPacienteState extends State<_CartaoPaciente> {
  final _nome = TextEditingController(), _pront = TextEditingController(), _idade = TextEditingController();
  String? _sexo;

  @override
  void dispose() {
    _nome.dispose();
    _pront.dispose();
    _idade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = Servicos.of(context).monitor;
    if (m.medindo) {
      final p = m.paciente;
      return Secao(
        titulo: 'Medindo',
        acao: TextButton(onPressed: m.encerrarSessao, child: const Text('Encerrar')),
        filho: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              backgroundColor: Cores.verdeClaro,
              child: Text(_iniciais(p?.nome ?? '?'), style: const TextStyle(color: Cores.verdeEscuro, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p?.nome ?? 'Paciente não identificado', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5)),
                Text(_meta(p), style: const TextStyle(color: Cores.suave, fontSize: 12.5)),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          Text('Medição ${m.medicoesFeitas + 1} de ${m.medicoesPorSessao} — fique parado e respire normalmente',
              style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
                value: (m.medicoesFeitas + m.progressoBloco) / m.medicoesPorSessao,
                minHeight: 8,
                backgroundColor: Cores.painel2,
                color: Cores.verde),
          ),
        ]),
      );
    }
    final semFonte = m.fonte == Fonte.nenhuma;
    return Secao(
      titulo: 'Paciente',
      filho: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: _nome, textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nome completo')),
        const SizedBox(height: 10),
        TextField(controller: _pront, decoration: const InputDecoration(labelText: 'Prontuário / identificação (opcional)')),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(controller: _idade, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Idade'))),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _sexo,
              decoration: const InputDecoration(labelText: 'Sexo'),
              items: [for (final e in sexos.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _sexo = v),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: semFonte
              ? null
              : () {
                  final nome = _nome.text.trim();
                  if (nome.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informe o nome do paciente.')));
                    return;
                  }
                  m.iniciarSessao(Paciente(nome,
                      prontuario: _pront.text.trim().isEmpty ? null : _pront.text.trim(),
                      idade: int.tryParse(_idade.text.trim()),
                      sexo: _sexo));
                  FocusScope.of(context).unfocus();
                },
          icon: const Icon(Icons.play_arrow),
          label: Text(semFonte ? 'Conecte o ECG para medir' : 'Iniciar medição'),
        ),
        const SizedBox(height: 6),
        Text('Serão ${m.medicoesPorSessao} medições de 10 s (${m.medicoesPorSessao * 10 ~/ 60} min '
            '${m.medicoesPorSessao * 10 % 60} s).',
            textAlign: TextAlign.center, style: const TextStyle(color: Cores.suave, fontSize: 12)),
      ]),
    );
  }

  String _iniciais(String n) =>
      n.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).take(2).map((s) => s[0].toUpperCase()).join();
  String _meta(Paciente? p) {
    if (p == null) return '';
    final partes = [
      if (p.prontuario != null) 'Prontuário ${p.prontuario}',
      if (p.idade != null) '${p.idade} anos',
      if (p.sexo != null) sexos[p.sexo]!,
    ];
    return partes.isEmpty ? 'Sem dados adicionais' : partes.join(' · ');
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
          valor: u?.classe == null ? const Text('--') : Padding(padding: const EdgeInsets.only(top: 4), child: TagClasse(u!.classe, grande: true)),
          sub: u?.classe == null ? (u?.erro ?? 'aguardando') : descricaoClasse[u!.classe],
        ),
        Kpi(rotulo: 'Medições', valor: Text('${m.medicoesFeitas}/${m.medicoesPorSessao}'),
            sub: m.medindo ? '${(m.progressoBloco * 10).floor()} de 10 s' : (m.medicoesFeitas > 0 ? 'concluída' : '')),
    ]);
  }
}

class _UltimaMedicao extends StatelessWidget {
  const _UltimaMedicao(this.u);
  final MedicaoClassificada u;
  @override
  Widget build(BuildContext context) {
    return Secao(
      titulo: 'Última medição (10 s)',
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
      titulo: 'Medições desta sessão',
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
                decoration: BoxDecoration(border: Border.all(color: i == 0 ? Cores.verde : Cores.linha), borderRadius: BorderRadius.circular(10)),
                child: Column(children: [
                  Expanded(child: GraficoEcg(sinal: u.filtrado, rpeaks: u.rpeaks, classePorPico: u.classePorPico,
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
