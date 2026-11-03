"""Avalia o modelo_rf.json exatamente como o app faz (mesma regra das árvores do sklearn:
feature convertida para float32 e comparada com <= limiar; probabilidade = média das folhas)."""
import json

import numpy as np


class ModeloRF:
    def __init__(self, caminho):
        d = json.loads(open(caminho, encoding='utf-8').read())
        self.classes = d['classes']
        self.arvores = d['arvores']

    def proba(self, x):
        x32 = np.asarray(x, dtype=np.float32)
        soma = np.zeros(len(self.classes))
        for t in self.arvores:
            no = 0
            while t['feature'][no] != -1:
                no = t['esq'][no] if x32[t['feature'][no]] <= np.float32(t['limiar'][no]) else t['dir'][no]
            soma += t['probs'][no]
        return soma / len(self.arvores)

    def prever(self, x):
        p = self.proba(x)
        i = int(np.argmax(p))
        return self.classes[i], float(p[i]), p
