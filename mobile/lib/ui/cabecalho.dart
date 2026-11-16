// Marca do DECI e indicador do ECG, usados no topo das telas.
import 'package:flutter/material.dart';

import '../ble/ecg_ble.dart';
import '../main.dart';
import '../servicos/monitor.dart';
import 'deci_marca.dart';
import 'tema.dart';

class MarcaDeci extends StatelessWidget {
  const MarcaDeci({super.key});
  @override
  Widget build(BuildContext context) => const Row(mainAxisSize: MainAxisSize.min, children: [
        Mascote(tamanho: 38, brilho: false),
        SizedBox(width: 10),
        Flexible(
          child: Text('DECI',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: Cores.texto),
              overflow: TextOverflow.fade, softWrap: false),
        ),
      ]);
}

/// Indicador do ECG no topo: rosa = recebendo sinal do ESP, âmbar = simulador, cinza = desconectado.
class PilulaEcg extends StatelessWidget {
  const PilulaEcg({super.key});
  @override
  Widget build(BuildContext context) {
    final s = Servicos.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([s.ble, s.monitor]),
      builder: (context, _) {
        final m = s.monitor, ble = s.ble;
        final (texto, cor, fundo, ponto) = switch (m.fonte) {
          Fonte.ble => (ble.nomeConectado ?? 'ECG', Cores.destaqueEscuro, Cores.destaqueClaro, Cores.destaque),
          Fonte.simulador => ('Simulador', Cores.aviso, Cores.avisoClaro, Cores.aviso),
          Fonte.nenhuma => ('ECG offline', Cores.suave, Colors.white, Cores.linhaForte),
        };
        return Padding(
          padding: const EdgeInsets.only(right: 12),
          child: InkWell(
            borderRadius: BorderRadius.circular(99),
            onTap: m.fonte == Fonte.ble ? () => _detalhesBle(context, ble) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: fundo, borderRadius: BorderRadius.circular(99), border: Border.all(color: Cores.linhaForte)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                DeciIcone(DeciGlifo.chip, tamanho: 16, cor: cor),
                const SizedBox(width: 5),
                Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: ponto)),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 110),
                  child: Text(texto, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cor)),
                ),
              ]),
            ),
          ),
        );
      },
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
