// Nova medição: conectar o ECG, conferir o sinal, identificar o paciente e escolher a duração.
import 'package:flutter/material.dart';

import '../ble/ecg_ble.dart';
import '../dados/banco.dart';
import '../main.dart';
import '../servicos/monitor.dart';
import '../servicos/qualidade_sinal.dart';
import '../ui/cabecalho.dart';
import '../ui/componentes.dart';
import '../ui/deci_marca.dart';
import '../ui/grafico_ecg.dart';
import '../ui/tema.dart';
import 'tela_monitor.dart';

class TelaNovaMedicao extends StatefulWidget {
  const TelaNovaMedicao({super.key});
  @override
  State<TelaNovaMedicao> createState() => _TelaNovaMedicaoState();
}

class _TelaNovaMedicaoState extends State<TelaNovaMedicao> {
  final _nome = TextEditingController(), _pront = TextEditingController(), _idade = TextEditingController();
  String? _sexo;
  int? _medicoes;

  static const _duracoes = [3, 6, 12, 18]; // medições de 10 s

  @override
  void dispose() {
    _nome.dispose();
    _pront.dispose();
    _idade.dispose();
    super.dispose();
  }

  Future<void> _iniciar() async {
    final s = Servicos.of(context);
    final nome = _nome.text.trim();
    if (nome.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informe o nome do paciente.')));
      return;
    }
    final n = _medicoes ?? s.operador.medicoesPorSessao;
    await s.operador.setMedicoesPorSessao(n);
    await s.monitor.iniciarSessao(
        Paciente(nome,
            prontuario: _pront.text.trim().isEmpty ? null : _pront.text.trim(),
            idade: int.tryParse(_idade.text.trim()),
            sexo: _sexo),
        medicoes: n);
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const TelaMonitor()));
  }

  @override
  Widget build(BuildContext context) {
    final s = Servicos.of(context);
    final n = _medicoes ?? s.operador.medicoesPorSessao;
    return Scaffold(
      appBar: AppBar(title: const Text('Nova medição'), actions: const [PilulaEcg()]),
      body: ListenableBuilder(
        listenable: Listenable.merge([s.ble, s.monitor, s.operador]),
        builder: (context, _) {
          final conectado = s.monitor.fonte != Fonte.nenhuma;
          final q = conectado ? avaliarSinal(s.monitor.monitor, s.monitor.cursor, eletrodoSolto: s.ble.eletrodoSolto) : null;
          return ListaResponsiva(children: [
            _Passo(numero: 1, titulo: 'Conectar o ECG', feito: conectado, filho: const _Conexao()),
            const SizedBox(height: 14),
            _Passo(
              numero: 2,
              titulo: 'Conferir o sinal',
              feito: q?.nivel == NivelSinal.bom,
              filho: _PreviaSinal(s.monitor, q),
            ),
            const SizedBox(height: 14),
            _Passo(
              numero: 3,
              titulo: 'Paciente',
              feito: _nome.text.trim().isNotEmpty,
              filho: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(
                  controller: _nome,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nome completo'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                TextField(controller: _pront, decoration: const InputDecoration(labelText: 'Prontuário / identificação (opcional)')),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: TextField(controller: _idade, keyboardType: TextInputType.number,
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
              ]),
            ),
            const SizedBox(height: 14),
            _Passo(
              numero: 4,
              titulo: 'Duração',
              feito: true,
              filho: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final d in _duracoes)
                  ChoiceChip(
                    label: Text(_rotuloDuracao(d)),
                    selected: n == d,
                    onSelected: (_) => setState(() => _medicoes = d),
                    selectedColor: Cores.destaqueClaro,
                    labelStyle: TextStyle(
                        color: n == d ? Cores.destaqueEscuro : Cores.texto, fontWeight: n == d ? FontWeight.w700 : FontWeight.w500),
                    side: BorderSide(color: n == d ? Cores.destaque : Cores.linhaForte),
                    showCheckmark: false,
                  ),
              ]),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: conectado ? _iniciar : null,
              icon: const DeciIcone(DeciGlifo.ecg, tamanho: 22),
              label: Text(conectado ? 'Iniciar ECG' : 'Conecte o ECG para começar'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 56), shape: const StadiumBorder()),
            ),
            if (q != null && q.nivel == NivelSinal.ruim)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('O sinal ainda não está bom — a medição pode sair com erros. Ajuste os eletrodos antes de iniciar.',
                    textAlign: TextAlign.center, style: TextStyle(color: Cores.perigo, fontSize: 12.5)),
              ),
            const SizedBox(height: 8),
            Text('${n * 10 ~/ 60 > 0 ? '${n * 10 ~/ 60} min ' : ''}${n * 10 % 60 > 0 ? '${n * 10 % 60} s ' : ''}'
                'de registro · o paciente deve ficar parado e respirar normalmente',
                textAlign: TextAlign.center, style: const TextStyle(color: Cores.suave, fontSize: 12.5)),
          ]);
        },
      ),
    );
  }

  String _rotuloDuracao(int n) => n * 10 < 60 ? '${n * 10} s' : '${n * 10 ~/ 60} min';
}

class _Passo extends StatelessWidget {
  const _Passo({required this.numero, required this.titulo, required this.feito, required this.filho});
  final int numero;
  final String titulo;
  final bool feito;
  final Widget filho;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, color: feito ? Cores.destaque : Cores.destaqueClaro),
                child: feito
                    ? const DeciIcone(DeciGlifo.salvar, tamanho: 16, cor: Colors.white)
                    : Text('$numero', style: const TextStyle(color: Cores.destaqueEscuro, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 10),
              Text(titulo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 14),
            filho,
          ]),
        ),
      );
}

class _Conexao extends StatelessWidget {
  const _Conexao();

  // Escuta o Bluetooth e o monitor por conta própria: por ser const, este widget não é refeito quando
  // a tela de cima redesenha — sem isto, "Procurando…", a lista de ECGs e os erros nunca apareciam.
  @override
  Widget build(BuildContext context) {
    final s = Servicos.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([s.ble, s.monitor, s.operador]),
      builder: (context, _) => _conteudo(s),
    );
  }

  Widget _conteudo(Servicos s) {
    final ble = s.ble, m = s.monitor;
    if (m.fonte == Fonte.ble) {
      return Row(children: [
        const DeciIcone(DeciGlifo.bluetooth, tamanho: 34, blob: true),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ble.nomeConectado ?? 'ECG', style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(ble.eletrodoSolto ? 'Eletrodo solto — confira os eletrodos' : 'Conectado e recebendo sinal',
                style: TextStyle(color: ble.eletrodoSolto ? Cores.perigo : Cores.suave, fontSize: 12.5)),
          ]),
        ),
        TextButton(onPressed: ble.desconectar, child: const Text('Desconectar')),
      ]);
    }
    if (m.fonte == Fonte.simulador) {
      return Row(children: [
        const DeciIcone(DeciGlifo.simulador, tamanho: 34, blob: true),
        const SizedBox(width: 10),
        const Expanded(child: Text('Usando sinal simulado (a sessão fica marcada como simulada).')),
        TextButton(onPressed: m.pararSimulador, child: const Text('Parar')),
      ]);
    }
    final ocupado = ble.estado == EstadoBle.procurando || ble.estado == EstadoBle.conectando;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Ligue o ECG e deixe o celular por perto. A conexão é por Bluetooth, sem Wi-Fi nem internet.',
          style: TextStyle(color: Cores.suave, fontSize: 13.5)),
      if (ble.erro != null) ...[const SizedBox(height: 10), Caixa(ble.erro!, tipo: 'erro', icone: DeciGlifo.bluetooth)],
      const SizedBox(height: 12),
      for (final d in ble.encontrados)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: OutlinedButton.icon(
            onPressed: ble.estado == EstadoBle.conectando ? null : () => ble.conectar(d),
            icon: const DeciIcone(DeciGlifo.bluetooth, tamanho: 20),
            label: Row(children: [
              Expanded(child: Text(d.nome)),
              Text(d.rssi == null ? 'pareado' : '${d.rssi} dBm', style: const TextStyle(color: Cores.suave, fontSize: 12)),
            ]),
          ),
        ),
      if (ble.estado == EstadoBle.procurando && ble.encontrados.isEmpty)
        const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('Procurando…', textAlign: TextAlign.center)),
      if (ble.nadaEncontrado && ble.estado != EstadoBle.procurando)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Caixa(
            // o total de aparelhos vistos separa "a busca não funciona" de "o ESP não está anunciando"
            ble.vistosPorPerto == 0
                ? 'Nenhum aparelho Bluetooth foi encontrado — a busca não está funcionando neste aparelho. Confira:\n'
                    '• o Bluetooth está ligado;\n'
                    '• o DECI tem a permissão "Dispositivos próximos" (ou "Localização", no Android 11 ou '
                    'anterior) em Configurações > Apps > DECI > Permissões;\n'
                    '• no Android 11 ou anterior, a Localização do aparelho precisa estar ligada.'
                : 'A busca viu ${ble.vistosPorPerto} aparelho(s) Bluetooth, mas nenhum ECG. Confira:\n'
                    '• o ESP está ligado e o display mostra a grade do ECG;\n'
                    '• o ECG não está conectado pelas configurações de Bluetooth do Android nem em outro app '
                    '(se estiver, desconecte ou toque em "Esquecer" e procure de novo);\n'
                    '• o firmware gravado é o ECGv3_ble (o nome anunciado começa com IC-ECG).',
            tipo: 'aviso',
            icone: DeciGlifo.alerta,
          ),
        ),
      FilledButton.icon(
        onPressed: ocupado ? null : ble.procurar,
        icon: ocupado
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const DeciIcone(DeciGlifo.bluetooth, tamanho: 20),
        label: Text(switch (ble.estado) {
          EstadoBle.procurando => 'Procurando…',
          EstadoBle.conectando => 'Conectando…',
          _ => ble.encontrados.isEmpty ? 'Procurar ECG' : 'Procurar de novo',
        }),
      ),
      if (s.operador.admin)
        TextButton(
          onPressed: () => m.iniciarSimulador(),
          child: const Text('Sem ECG? Usar sinal simulado (admin)'),
        ),
    ]);
  }
}

/// Traçado ao vivo + qualidade do sinal, para posicionar os eletrodos antes de começar a gravar.
class _PreviaSinal extends StatelessWidget {
  const _PreviaSinal(this.m, this.q);
  final Monitor m;
  final QualidadeSinal? q;

  @override
  Widget build(BuildContext context) {
    final q = this.q;
    if (q == null) {
      return const Text('Conecte o ECG para ver o sinal ao vivo aqui, antes de começar a gravar.',
          style: TextStyle(color: Cores.suave, fontSize: 13.5));
    }
    final (cor, rotulo) = switch (q.nivel) {
      NivelSinal.bom => (coresClasse['N']!, 'Sinal bom'),
      NivelSinal.regular => (Cores.aviso, 'Sinal aceitável'),
      NivelSinal.ruim => (Cores.perigo, 'Sinal ruim'),
      NivelSinal.aguardando => (Cores.suave, 'Analisando…'),
    };
    final mostrarBpm = q.bpm != null && q.nivel != NivelSinal.ruim;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: cor.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: cor.withValues(alpha: .5)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 9, height: 9, decoration: BoxDecoration(color: cor, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(rotulo, style: TextStyle(color: cor, fontWeight: FontWeight.w700, fontSize: 13)),
          ]),
        ),
        const Spacer(),
        if (mostrarBpm) ...[
          const DeciIcone(DeciGlifo.coracao, tamanho: 18, cor: Cores.destaque),
          const SizedBox(width: 4),
          Text('~${q.bpm!.round()} bpm', style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ]),
      const SizedBox(height: 10),
      GraficoEcg(sinal: m.monitor, cursor: m.cursor, rotulos: false, altura: 160),
      const SizedBox(height: 8),
      Text(q.mensagem, style: TextStyle(color: q.nivel == NivelSinal.bom ? Cores.suave : cor, fontSize: 13)),
      if (m.fonte == Fonte.simulador)
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('(sinal simulado)', style: TextStyle(color: Cores.suave, fontSize: 11.5)),
        ),
    ]);
  }
}
