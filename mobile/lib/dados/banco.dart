// Banco SQLite no próprio celular.
//   sessoes   -> uma sessão de medição de um paciente
//   medicoes  -> cada janela de 10 s: sinal bruto (ADC), picos R, BPM, classe, distribuição, VFC
//   batimentos-> as 10 features + classe prevista + rótulo revisado (dados de treino)
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../pipeline/pipeline_ecg.dart' show nomesFeatures;

class Paciente {
  final String nome;
  final String? prontuario;
  final int? idade;
  final String? sexo; // F, M, O
  const Paciente(this.nome, {this.prontuario, this.idade, this.sexo});

  Map<String, Object?> toMap() => {'patient': nome, 'patient_id': prontuario, 'patient_age': idade, 'patient_sex': sexo};
  static Paciente? deMap(Map<String, Object?> m) => (m['patient'] as String?)?.isNotEmpty == true
      ? Paciente(m['patient'] as String,
          prontuario: m['patient_id'] as String?, idade: m['patient_age'] as int?, sexo: m['patient_sex'] as String?)
      : null;
}

class Banco {
  Banco._(this.db);
  final Database db;

  static Future<Banco> abrir() async {
    final caminho = p.join(await getDatabasesPath(), 'icecg.db');
    final db = await openDatabase(caminho, version: 1, onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
      await db.execute('''CREATE TABLE sessoes (
        id INTEGER PRIMARY KEY AUTOINCREMENT, dispositivo TEXT NOT NULL, inicio TEXT NOT NULL,
        patient TEXT, patient_id TEXT, patient_age INTEGER, patient_sex TEXT, notes TEXT,
        simulada INTEGER NOT NULL DEFAULT 0)''');
      await db.execute('''CREATE TABLE medicoes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL REFERENCES sessoes(id) ON DELETE CASCADE,
        criada TEXT NOT NULL, fs INTEGER NOT NULL, sinal TEXT NOT NULL, rpeaks TEXT, bpm REAL,
        classe TEXT, distribuicao TEXT, vfc TEXT, erro TEXT, modelo TEXT)''');
      await db.execute('''CREATE TABLE batimentos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        measurement_id INTEGER NOT NULL REFERENCES medicoes(id) ON DELETE CASCADE,
        r_sample INTEGER NOT NULL, ${nomesFeatures.map((f) => '$f REAL').join(', ')},
        pred_label TEXT, confidence REAL, true_label TEXT)''');
      await db.execute('CREATE INDEX idx_med_sessao ON medicoes(session_id)');
      await db.execute('CREATE INDEX idx_bat_med ON batimentos(measurement_id)');
    });
    return Banco._(db);
  }

  // ---------------- sessões
  Future<int> novaSessao(String dispositivo, Paciente? paciente, {bool simulada = false}) => db.insert('sessoes', {
        'dispositivo': dispositivo,
        'inicio': DateTime.now().toUtc().toIso8601String(),
        'simulada': simulada ? 1 : 0,
        ...?paciente?.toMap(),
      });

  Future<List<Map<String, Object?>>> listarSessoes({String? busca}) {
    final filtro = (busca == null || busca.isEmpty) ? '' : 'WHERE s.patient LIKE ? OR s.patient_id LIKE ? OR s.id = ?';
    return db.rawQuery('''
      SELECT s.*, COUNT(m.id) AS n_medicoes, ROUND(AVG(m.bpm), 1) AS bpm_medio, SUM(m.erro IS NOT NULL) AS n_erros,
        (SELECT classe FROM medicoes WHERE session_id = s.id AND classe IS NOT NULL
         GROUP BY classe ORDER BY COUNT(*) DESC LIMIT 1) AS classe_final
      FROM sessoes s LEFT JOIN medicoes m ON m.session_id = s.id $filtro
      GROUP BY s.id ORDER BY s.id DESC''', filtro.isEmpty ? [] : ['%$busca%', '%$busca%', int.tryParse(busca!) ?? -1]);
  }

  Future<Map<String, Object?>?> sessao(int id) async {
    final r = await listarSessoes();
    return r.where((s) => s['id'] == id).firstOrNull;
  }

  Future<void> atualizarSessao(int id, Map<String, Object?> campos) => db.update('sessoes', campos, where: 'id = ?', whereArgs: [id]);

  Future<void> excluirSessao(int id) async {
    await db.delete('sessoes', where: 'id = ?', whereArgs: [id]);
    await _ajustarNumeracao();
  }

  /// Apaga a medição; se a sessão ficar vazia, apaga a sessão também (devolve true nesse caso).
  Future<bool> excluirMedicao(int id) async {
    final m = await db.query('medicoes', columns: ['session_id'], where: 'id = ?', whereArgs: [id]);
    if (m.isEmpty) return false;
    final sid = m.first['session_id'] as int;
    await db.delete('medicoes', where: 'id = ?', whereArgs: [id]);
    final resta = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM medicoes WHERE session_id = ?', [sid])) ?? 0;
    if (resta == 0) await db.delete('sessoes', where: 'id = ?', whereArgs: [sid]);
    await _ajustarNumeracao();
    return resta == 0;
  }

  /// O AUTOINCREMENT nunca reaproveita números; o contador volta para o maior id existente.
  Future<void> _ajustarNumeracao() async {
    for (final t in ['sessoes', 'medicoes', 'batimentos']) {
      await db.rawUpdate("UPDATE sqlite_sequence SET seq = (SELECT COALESCE(MAX(id), 0) FROM $t) WHERE name = '$t'");
    }
  }

  // ---------------- medições
  Future<int> salvarMedicao({
    required int sessionId,
    required List<int> sinal,
    List<int>? rpeaks,
    double? bpm,
    String? classe,
    Map<String, int>? distribuicao,
    Map<String, double>? vfc,
    String? erro,
    String? modelo,
    List<({int r, List<double> f, String classe, double conf})> batimentos = const [],
  }) async {
    return db.transaction((tx) async {
      final mid = await tx.insert('medicoes', {
        'session_id': sessionId,
        'criada': DateTime.now().toUtc().toIso8601String(),
        'fs': 100,
        'sinal': jsonEncode(sinal),
        'rpeaks': rpeaks == null ? null : jsonEncode(rpeaks),
        'bpm': bpm,
        'classe': classe,
        'distribuicao': distribuicao == null ? null : jsonEncode(distribuicao),
        'vfc': vfc == null ? null : jsonEncode(vfc),
        'erro': erro,
        'modelo': modelo,
      });
      final lote = tx.batch();
      for (final b in batimentos) {
        lote.insert('batimentos', {
          'measurement_id': mid,
          'r_sample': b.r,
          for (var i = 0; i < nomesFeatures.length; i++) nomesFeatures[i]: b.f[i],
          'pred_label': b.classe,
          'confidence': b.conf,
        });
      }
      await lote.commit(noResult: true);
      return mid;
    });
  }

  Future<List<Map<String, Object?>>> medicoesDaSessao(int sid) =>
      db.query('medicoes', where: 'session_id = ?', whereArgs: [sid], orderBy: 'id');

  Future<List<Map<String, Object?>>> batimentos(int mid) =>
      db.query('batimentos', where: 'measurement_id = ?', whereArgs: [mid], orderBy: 'r_sample');

  Future<void> rotular(int batimentoId, String? classe) =>
      db.update('batimentos', {'true_label': classe}, where: 'id = ?', whereArgs: [batimentoId]);

  Future<void> rotularMedicao(int mid, String? classe) =>
      db.update('batimentos', {'true_label': classe}, where: 'measurement_id = ?', whereArgs: [mid]);

  // ---------------- dataset
  Future<Map<String, Object?>> estatisticas() async {
    final r = await db.rawQuery('''SELECT
      (SELECT COUNT(*) FROM sessoes WHERE simulada = 0) AS sessoes,
      (SELECT COUNT(*) FROM sessoes WHERE simulada = 1) AS simuladas,
      (SELECT COUNT(*) FROM medicoes m JOIN sessoes s ON s.id = m.session_id WHERE s.simulada = 0) AS medicoes,
      (SELECT COUNT(*) FROM batimentos b JOIN medicoes m ON m.id = b.measurement_id JOIN sessoes s ON s.id = m.session_id
         WHERE s.simulada = 0) AS batimentos,
      (SELECT COUNT(*) FROM batimentos b JOIN medicoes m ON m.id = b.measurement_id JOIN sessoes s ON s.id = m.session_id
         WHERE s.simulada = 0 AND b.true_label IS NOT NULL) AS revisados''');
    return r.first;
  }

  /// CSV no formato de ml/treinar.py (features + label + record). Sessões simuladas ficam fora.
  Future<String> exportarCsv({required bool somenteRevisados}) async {
    final linhas = await db.rawQuery('''
      SELECT ${nomesFeatures.map((f) => 'b.$f').join(', ')}, b.r_sample,
        COALESCE(b.true_label, b.pred_label) AS label, 'app-' || m.session_id || '-' || m.id AS record,
        b.pred_label, b.confidence, (b.true_label IS NOT NULL) AS revisado
      FROM batimentos b JOIN medicoes m ON m.id = b.measurement_id JOIN sessoes s ON s.id = m.session_id
      WHERE s.simulada = 0 ${somenteRevisados ? 'AND b.true_label IS NOT NULL' : ''} ORDER BY b.id''');
    final cab = [...nomesFeatures, 'r_sample', 'label', 'record', 'pred_label', 'confidence', 'revisado'];
    final sb = StringBuffer()..writeln(cab.join(','));
    for (final l in linhas) {
      sb.writeln(cab.map((c) => l[c] ?? '').join(','));
    }
    return sb.toString();
  }
}
