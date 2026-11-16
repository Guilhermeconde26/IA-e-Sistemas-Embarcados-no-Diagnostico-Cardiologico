// Aba ADM: modo administrador, informações do projeto, como o sistema funciona e exportação do dataset.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../main.dart';
import '../ui/componentes.dart';
import '../ui/deci_marca.dart';
import '../ui/tema.dart';

class TelaAdm extends StatelessWidget {
  const TelaAdm({super.key});

  @override
  Widget build(BuildContext context) {
    final op = Servicos.of(context).operador;
    return Scaffold(
      appBar: AppBar(title: const Text('ADM')),
      body: ListenableBuilder(
        listenable: op,
        builder: (context, _) => ListaResponsiva(children: [
          const _Modo(),
          const SizedBox(height: 14),
          const _SobreProjeto(),
          const SizedBox(height: 14),
          const _ComoFunciona(),
          if (op.admin) ...[const SizedBox(height: 14), const _Dataset()],
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- modo
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

  @override
  Widget build(BuildContext context) {
    final op = Servicos.of(context).operador;
    return Secao(
      titulo: 'Modo de operação',
      filho: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          DeciIcone(op.admin ? DeciGlifo.pessoa : DeciGlifo.cadeado, tamanho: 40, blob: true, ativo: op.admin),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(op.admin ? 'Administrador' : 'Paciente', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              Text(
                op.admin
                    ? 'Acesso aos resultados, PDF, exclusões, revisão de rótulos e dataset.'
                    : 'Faz medições e simulações. Os resultados ficam protegidos pelo PIN.',
                style: const TextStyle(fontSize: 12.5, color: Cores.suave),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        if (op.admin)
          OutlinedButton.icon(
              onPressed: op.sair,
              icon: const DeciIcone(DeciGlifo.sair, tamanho: 20),
              label: const Text('Mudar para modo paciente'))
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
}

// ---------------------------------------------------------------- sobre
class _SobreProjeto extends StatelessWidget {
  const _SobreProjeto();
  @override
  Widget build(BuildContext context) {
    const suave = TextStyle(fontSize: 13, color: Cores.suave, height: 1.4);
    return Secao(
      titulo: 'Sobre o projeto',
      filho: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Mascote(tamanho: 56, brilho: false),
          SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('DECI', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
              Text('Diagnóstico de Eletrocardiograma Instantâneo', style: suave),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        const Text('Projeto de pesquisa em inteligência artificial e sistemas embarcados aplicados ao diagnóstico '
            'cardiológico: um ECG de baixo custo (ESP32-S3 + AD8232) e um app que classifica os batimentos no próprio celular.',
            style: TextStyle(fontSize: 13.5, height: 1.4)),
        const SizedBox(height: 14),
        Row(children: [
          const LogoUfop(altura: 46),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Departamento de Engenharia de Controle e Automação',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              Text('Universidade Federal de Ouro Preto — UFOP', style: suave),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        const Text('AUTORES', style: TextStyle(fontSize: 11, letterSpacing: .6, color: Cores.suave, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const _Autor('Guilherme Conde', 'guilherme.conde@aluno.ufop.edu.br'),
        const _Autor('Adrielle Santana', 'Adrielle@ufop.edu.br'),
        const SizedBox(height: 12),
        const Caixa('Trabalho científico. As classificações são geradas por um modelo de inteligência artificial e '
            'podem conter erros. Os resultados não substituem a avaliação de um profissional de saúde.',
            icone: DeciGlifo.info),
      ]),
    );
  }
}

class _Autor extends StatelessWidget {
  const _Autor(this.nome, this.email);
  final String nome, email;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(nome, style: const TextStyle(fontWeight: FontWeight.w600)),
          SelectableText(email, style: const TextStyle(color: Cores.destaqueEscuro, fontSize: 13)),
        ]),
      );
}

// ---------------------------------------------------------------- como funciona
class _ComoFunciona extends StatelessWidget {
  const _ComoFunciona();
  @override
  Widget build(BuildContext context) {
    final modelo = Servicos.of(context).modelo;
    final passos = [
      (DeciGlifo.chip, 'Aquisição', 'O AD8232 capta o sinal do coração e o ESP32-S3 o digitaliza a 100 amostras por segundo.'),
      (DeciGlifo.bluetooth, 'Bluetooth', 'As amostras chegam ao celular em tempo real, em pacotes de 100 ms. Não precisa de Wi-Fi nem internet.'),
      (DeciGlifo.ecg, 'Filtro e picos R', 'Cada janela de 10 s passa por um filtro de 0,5 a 40 Hz e por um detector de picos R '
          '(Pan-Tompkins), que acerta 98,9% dos batimentos do MIT-BIH.'),
      (DeciGlifo.dados, 'Características', 'De cada batimento saem 10 medidas: intervalo RR, frequência, amplitude do R e '
          'a forma da onda em torno dele (média, desvio, assimetria, curtose, energia espectral).'),
      (DeciGlifo.coracao, 'Classificação', 'Uma Random Forest com ${modelo.nArvores} árvores, treinada com '
          '${modelo.nBatimentosTreino} batimentos do MIT-BIH, classifica cada batimento nas classes AAMI: '
          'N (normal), S (supraventricular), V (ventricular) e F (fusão).'),
      (DeciGlifo.pasta, 'Registro', 'Tudo fica num banco de dados no próprio celular. O administrador revisa os rótulos, '
          'gera relatórios em PDF e exporta os dados para treinar novos modelos.'),
    ];
    return Secao(
      titulo: 'Como o sistema funciona',
      filho: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < passos.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              DeciIcone(passos[i].$1, tamanho: 38, blob: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${i + 1}. ${passos[i].$2}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(passos[i].$3, style: const TextStyle(fontSize: 13, height: 1.38, color: Cores.suave)),
                ]),
              ),
            ]),
          ),
        const Divider(height: 18),
        const Text('Desempenho em pacientes que o modelo nunca viu', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const _Metrica('N', 'precisão 95% · sensibilidade 97%'),
        const _Metrica('V', 'precisão 79% · sensibilidade 77%'),
        const _Metrica('S', 'ainda fraco (sensibilidade 6%)'),
        const _Metrica('F', 'ainda fraco (sensibilidade 3%)'),
        const SizedBox(height: 8),
        Text('Modelo treinado em ${formatarData(modelo.treinadoEm)}.',
            style: const TextStyle(fontSize: 12, color: Cores.suave)),
      ]),
    );
  }
}

class _Metrica extends StatelessWidget {
  const _Metrica(this.classe, this.texto);
  final String classe, texto;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(width: 40, child: TagClasse(classe)),
          Expanded(child: Text(texto, style: const TextStyle(fontSize: 13))),
        ]),
      );
}

// ---------------------------------------------------------------- dataset
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
    final arq = File('${dir.path}/deci_dataset${revisados ? '_revisados' : ''}.csv');
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
        FilledButton.icon(
            onPressed: () => _exportar(true),
            icon: const DeciIcone(DeciGlifo.compartilhar, tamanho: 20),
            label: const Text('Exportar só revisados')),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: () => _exportar(false), child: const Text('Exportar todos (rótulo previsto)')),
        const SizedBox(height: 6),
        const Text('Use os revisados para treinar: os previstos repetem os erros do modelo atual.',
            style: TextStyle(color: Cores.suave, fontSize: 12)),
      ]),
    );
  }
}
