// Comunicação BLE com o ESP32 (firmware/ECGv3_ble). Protocolo descrito no cabeçalho do .ino.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

final Guid uuidServico = Guid('a3c87500-8ed3-4bdf-8a39-a01bebede295');
final Guid uuidEcg = Guid('a3c87501-8ed3-4bdf-8a39-a01bebede295');
final Guid uuidStatus = Guid('a3c87502-8ed3-4bdf-8a39-a01bebede295');
const String prefixoNome = 'IC-ECG';

enum EstadoBle { desligado, procurando, conectando, conectado, desconectado }

class DispositivoEncontrado {
  final BluetoothDevice device;
  final String nome;
  final int rssi;
  DispositivoEncontrado(this.device, this.nome, this.rssi);
}

/// Faz a ponte entre o ESP e o app: entrega amostras do ADC (0..4095) em [amostras].
class EcgBle extends ChangeNotifier {
  EstadoBle estado = EstadoBle.desligado;
  String? nomeConectado;
  String? erro;
  bool eletrodoSolto = false;
  int? versaoFirmware;
  int pacotesPerdidos = 0;
  int pacotesRecebidos = 0;
  DateTime? ultimoPacote;
  List<DispositivoEncontrado> encontrados = [];

  final _amostras = StreamController<List<int>>.broadcast();
  Stream<List<int>> get amostras => _amostras.stream;

  BluetoothDevice? _device;
  int? _ultimoSeq;
  final List<StreamSubscription> _subs = [];
  StreamSubscription? _subScan;
  bool _desconexaoPedida = false;

  bool get conectado => estado == EstadoBle.conectado;

  Future<bool> bluetoothLigado() async {
    if (!await FlutterBluePlus.isSupported) {
      erro = 'Este celular não tem Bluetooth LE.';
      notifyListeners();
      return false;
    }
    final st = await FlutterBluePlus.adapterState.first;
    return st == BluetoothAdapterState.on;
  }

  Future<void> procurar() async {
    erro = null;
    encontrados = [];
    if (!await bluetoothLigado()) {
      try {
        await FlutterBluePlus.turnOn(); // Android pede para o usuário ligar
      } catch (_) {
        erro = 'Ligue o Bluetooth do celular para encontrar o ECG.';
        notifyListeners();
        return;
      }
    }
    estado = EstadoBle.procurando;
    notifyListeners();
    await _subScan?.cancel();
    _subScan = FlutterBluePlus.scanResults.listen((rs) {
      final lista = <DispositivoEncontrado>[];
      for (final r in rs) {
        final nome = r.advertisementData.advName.isNotEmpty ? r.advertisementData.advName : r.device.platformName;
        final ehEcg = nome.startsWith(prefixoNome) || r.advertisementData.serviceUuids.contains(uuidServico);
        if (ehEcg) lista.add(DispositivoEncontrado(r.device, nome.isEmpty ? 'IC-ECG' : nome, r.rssi));
      }
      lista.sort((a, b) => b.rssi.compareTo(a.rssi));
      encontrados = lista;
      notifyListeners();
    });
    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
      await FlutterBluePlus.isScanning.where((s) => !s).first;
    } catch (e) {
      erro = 'Não foi possível procurar: $e';
    }
    if (estado == EstadoBle.procurando) estado = EstadoBle.desligado;
    notifyListeners();
  }

  Future<void> conectar(DispositivoEncontrado d) async {
    await FlutterBluePlus.stopScan();
    _desconexaoPedida = false;
    estado = EstadoBle.conectando;
    erro = null;
    notifyListeners();
    try {
      // License.nonprofit: projeto de pesquisa em instituição de ensino (ver LICENSE do flutter_blue_plus)
      await d.device.connect(license: License.nonprofit, timeout: const Duration(seconds: 15), mtu: 247);
      _device = d.device;
      nomeConectado = d.nome;
      _subs.add(d.device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected && estado == EstadoBle.conectado) {
          estado = EstadoBle.desconectado;
          erro = _desconexaoPedida ? null : 'Conexão com o ECG perdida.';
          _limpar();
          notifyListeners();
        }
      }));
      final servicos = await d.device.discoverServices();
      final svc = servicos.where((s) => s.uuid == uuidServico).firstOrNull;
      if (svc == null) throw Exception('O dispositivo não tem o serviço do IC ECG (firmware v3?).');
      final chEcg = svc.characteristics.firstWhere((c) => c.uuid == uuidEcg);
      final chStatus = svc.characteristics.firstWhere((c) => c.uuid == uuidStatus);

      _subs.add(chStatus.onValueReceived.listen(_lerStatus));
      _lerStatus(await chStatus.read());
      await chStatus.setNotifyValue(true);

      _ultimoSeq = null;
      pacotesPerdidos = 0;
      pacotesRecebidos = 0;
      _subs.add(chEcg.onValueReceived.listen(_lerPacote));
      await chEcg.setNotifyValue(true);
      estado = EstadoBle.conectado;
    } catch (e) {
      erro = 'Falha ao conectar: $e';
      estado = EstadoBle.desligado;
      await _device?.disconnect();
      _limpar();
    }
    notifyListeners();
  }

  void _lerStatus(List<int> v) {
    if (v.length < 3) return;
    eletrodoSolto = (v[0] & 1) == 1;
    versaoFirmware = v[2];
    notifyListeners();
  }

  void _lerPacote(List<int> v) {
    // uint16 seq + N x uint16 (little-endian)
    if (v.length < 4 || v.length.isOdd) return;
    final seq = v[0] | (v[1] << 8);
    if (_ultimoSeq != null) {
      final esperado = (_ultimoSeq! + 1) & 0xFFFF;
      if (seq != esperado) pacotesPerdidos += (seq - esperado) & 0xFFFF;
    }
    _ultimoSeq = seq;
    pacotesRecebidos++;
    ultimoPacote = DateTime.now();
    final amostras = <int>[for (var i = 2; i + 1 < v.length; i += 2) v[i] | (v[i + 1] << 8)];
    _amostras.add(amostras);
  }

  Future<void> desconectar() async {
    _desconexaoPedida = true;
    await _device?.disconnect();
    estado = EstadoBle.desligado;
    _limpar();
    notifyListeners();
  }

  void _limpar() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _device = null;
    eletrodoSolto = false;
  }

  @override
  void dispose() {
    _subScan?.cancel();
    _limpar();
    _amostras.close();
    super.dispose();
  }
}
