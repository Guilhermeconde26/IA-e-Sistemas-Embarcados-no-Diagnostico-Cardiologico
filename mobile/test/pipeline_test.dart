// Confere que a pipeline em Dart reproduz a de Python (ml/pipeline_ecg.py) e o modelo JSON.
// golden.json é gerado por: python ml/gerar_golden.py
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ic_ecg/pipeline/modelo_rf.dart';
import 'package:ic_ecg/pipeline/pipeline_ecg.dart';

void main() {
  final golden = jsonDecode(File('test/golden.json').readAsStringSync()) as Map<String, dynamic>;
  final modelo = ModeloRF.deJson(File('assets/modelo_rf.json').readAsStringSync());

  for (final c in golden['casos'] as List) {
    final caso = c as Map<String, dynamic>;
    test(caso['nome'], () {
      final entrada = [for (final v in caso['entrada'] as List) (v as num).toDouble()];
      if (caso.containsKey('erro')) {
        expect(() => processar(entrada), throwsA(predicate((e) => e is ErroSinal && e.mensagem == caso['erro'])));
        return;
      }
      final r = processar(entrada);

      final filtradoPy = (caso['filtrado'] as List).cast<num>();
      var maxErro = 0.0;
      for (var i = 0; i < filtradoPy.length; i++) {
        final e = (r.filtrado[i] - filtradoPy[i]).abs();
        if (e > maxErro) maxErro = e;
      }
      expect(maxErro, lessThan(1e-9), reason: 'sinal filtrado');
      expect(r.rpeaks, equals((caso['rpeaks'] as List).cast<int>()), reason: 'picos R');
      expect(r.usados, equals((caso['usados'] as List).cast<int>()));

      final featsPy = caso['features'] as List;
      for (var i = 0; i < featsPy.length; i++) {
        final linha = (featsPy[i] as List).cast<num>();
        for (var j = 0; j < linha.length; j++) {
          final tol = 1e-6 * (1 + linha[j].abs());
          expect((r.features[i][j] - linha[j]).abs(), lessThan(tol), reason: 'batimento $i, ${nomesFeatures[j]}');
        }
      }

      final classesPy = (caso['classes'] as List).cast<String>();
      final probsPy = caso['probs'] as List;
      for (var i = 0; i < r.features.length; i++) {
        final p = modelo.prever(r.features[i]);
        expect(p.classe, classesPy[i], reason: 'classe do batimento $i');
        final pp = (probsPy[i] as List).cast<num>();
        for (var k = 0; k < pp.length; k++) {
          expect((p.probs[k] - pp[k]).abs(), lessThan(1e-9));
        }
      }
    });
  }
}
