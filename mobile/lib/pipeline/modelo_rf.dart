// Random Forest exportado por ml/treinar.py (assets/modelo_rf.json).
// Mesma regra do sklearn: a feature vira float32 e vai para a esquerda se <= limiar;
// a probabilidade é a média das folhas de todas as árvores.
import 'dart:convert';
import 'dart:typed_data';

class _Arvore {
  final Int32List feature, esq, dir;
  final Float32List limiar;
  final List<List<double>?> probs;
  _Arvore(this.feature, this.limiar, this.esq, this.dir, this.probs);
}

class Previsao {
  final String classe;
  final double confianca;
  final List<double> probs;
  Previsao(this.classe, this.confianca, this.probs);
}

class ModeloRF {
  final List<String> classes;
  final String treinadoEm;
  final int nBatimentosTreino;
  final List<_Arvore> _arvores;
  ModeloRF._(this.classes, this.treinadoEm, this.nBatimentosTreino, this._arvores);

  factory ModeloRF.deJson(String texto) {
    final d = jsonDecode(texto) as Map<String, dynamic>;
    if (d['formato'] != 'icecg-rf-v1') throw FormatException('Formato de modelo desconhecido: ${d['formato']}');
    final arvores = <_Arvore>[];
    for (final t in d['arvores'] as List) {
      final m = t as Map<String, dynamic>;
      arvores.add(_Arvore(
        Int32List.fromList((m['feature'] as List).cast<int>()),
        Float32List.fromList([for (final v in m['limiar'] as List) (v as num).toDouble()]),
        Int32List.fromList((m['esq'] as List).cast<int>()),
        Int32List.fromList((m['dir'] as List).cast<int>()),
        [for (final p in m['probs'] as List) p == null ? null : [for (final v in p as List) (v as num).toDouble()]],
      ));
    }
    return ModeloRF._((d['classes'] as List).cast<String>(), d['treinado_em'] as String? ?? '',
        d['n_batimentos_treino'] as int? ?? 0, arvores);
  }

  int get nArvores => _arvores.length;

  Previsao prever(List<double> x) {
    final x32 = Float32List.fromList(x); // conversão para float32, como o sklearn faz
    final soma = List<double>.filled(classes.length, 0);
    for (final t in _arvores) {
      var no = 0;
      while (t.feature[no] != -1) {
        no = x32[t.feature[no]] <= t.limiar[no] ? t.esq[no] : t.dir[no];
      }
      final p = t.probs[no]!;
      for (var c = 0; c < soma.length; c++) {
        soma[c] += p[c];
      }
    }
    var melhor = 0;
    for (var c = 0; c < soma.length; c++) {
      soma[c] /= _arvores.length;
      if (soma[c] > soma[melhor]) melhor = c;
    }
    return Previsao(classes[melhor], soma[melhor], soma);
  }
}
