// Modo paciente (padrão ao abrir o app) x administrador (PIN). O PIN é guardado só como
// SHA-256 com sal, nas preferências do próprio celular.
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Operador extends ChangeNotifier {
  Operador(this._prefs);
  final SharedPreferences _prefs;

  static Future<Operador> carregar() async => Operador(await SharedPreferences.getInstance());

  bool admin = false;

  bool get temPin => _prefs.getString('pin_hash') != null;
  int get medicoesPorSessao => _prefs.getInt('medicoes_por_sessao') ?? 6;

  String _hash(String pin, String sal) => sha256.convert(utf8.encode('$sal:$pin')).toString();

  /// Primeiro acesso: cria o PIN. Depois: confere.
  bool entrar(String pin) {
    if (!temPin) {
      definirPin(pin);
    } else if (_hash(pin, _prefs.getString('pin_sal')!) != _prefs.getString('pin_hash')) {
      return false;
    }
    admin = true;
    notifyListeners();
    return true;
  }

  void definirPin(String pin) {
    final r = Random.secure();
    final sal = base64Url.encode(List<int>.generate(16, (_) => r.nextInt(256)));
    _prefs.setString('pin_sal', sal);
    _prefs.setString('pin_hash', _hash(pin, sal));
  }

  void sair() {
    admin = false;
    notifyListeners();
  }

  Future<void> setMedicoesPorSessao(int n) async {
    await _prefs.setInt('medicoes_por_sessao', n);
    notifyListeners();
  }
}
