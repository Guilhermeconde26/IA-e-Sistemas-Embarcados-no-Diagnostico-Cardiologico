"""
Banco de dados SQLite.

sessions      -> um ciclo do ESP32 (por padrão 10 medições de 10 s) + parecer da IA
measurements  -> cada janela de 10 s: sinal bruto, sinal filtrado, picos R, resultado
beats         -> cada batimento: as 10 features + rótulo previsto + rótulo revisado (true_label)

A tabela beats tem as mesmas colunas do ecg_features.csv do MIT-BIH, então o export
pode ser concatenado direto ao dataset original para treinar um novo modelo.
"""
import json
import sqlite3
import threading
from datetime import datetime, timezone

from processing import FEATURE_COLS

SCHEMA = f"""
CREATE TABLE IF NOT EXISTS sessions (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id     TEXT NOT NULL,
    started_at    TEXT NOT NULL,
    last_at       TEXT NOT NULL,
    patient       TEXT,
    notes         TEXT,
    parecer       TEXT,
    parecer_model TEXT,
    parecer_at    TEXT
);
CREATE TABLE IF NOT EXISTS measurements (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id    INTEGER NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    created_at    TEXT NOT NULL,
    fs            INTEGER NOT NULL,
    raw_signal    TEXT NOT NULL,
    filtered      TEXT,
    rpeaks        TEXT,
    bpm           REAL,
    classe        TEXT,
    distribuicao  TEXT,
    hrv           TEXT,
    error         TEXT,
    model_version TEXT
);
CREATE TABLE IF NOT EXISTS beats (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    measurement_id INTEGER NOT NULL REFERENCES measurements(id) ON DELETE CASCADE,
    r_sample       INTEGER NOT NULL,
    {', '.join(f'{c} REAL' for c in FEATURE_COLS)},
    pred_label     TEXT,
    confidence     REAL,
    true_label     TEXT
);
CREATE TABLE IF NOT EXISTS config (
    chave TEXT PRIMARY KEY,
    valor TEXT
);
CREATE INDEX IF NOT EXISTS idx_meas_session ON measurements(session_id);
CREATE INDEX IF NOT EXISTS idx_beats_meas ON beats(measurement_id);
"""


# Identificação do paciente (colunas de sessions). "patient" é o nome.
CAMPOS_PACIENTE = {'patient': 'TEXT', 'patient_id': 'TEXT', 'patient_age': 'INTEGER', 'patient_sex': 'TEXT'}


def agora():
    return datetime.now(timezone.utc).isoformat(timespec='seconds')


class Database:
    def __init__(self, path):
        self.conn = sqlite3.connect(path, check_same_thread=False)
        self.conn.row_factory = sqlite3.Row
        self.conn.execute('PRAGMA foreign_keys = ON')
        self.conn.executescript(SCHEMA)
        self._migrar()
        self._ajustar_numeracao()  # corrige bancos que já tinham "buracos" no fim da numeração
        self.conn.commit()
        self.lock = threading.Lock()

    def _migrar(self):
        """Adiciona colunas novas em bancos criados por versões anteriores."""
        existentes = {r['name'] for r in self.conn.execute('PRAGMA table_info(sessions)')}
        for col, tipo in CAMPOS_PACIENTE.items():
            if col not in existentes:
                self.conn.execute(f'ALTER TABLE sessions ADD COLUMN {col} {tipo}')
        self.conn.commit()

    # ---------- configuração (paciente atual, etc.) ----------
    def config_get(self, chave, padrao=None):
        row = self.conn.execute('SELECT valor FROM config WHERE chave = ?', (chave,)).fetchone()
        return json.loads(row['valor']) if row else padrao

    def config_set(self, chave, valor):
        with self.lock:
            self.conn.execute('INSERT OR REPLACE INTO config (chave, valor) VALUES (?, ?)',
                              (chave, json.dumps(valor)))
            self.conn.commit()

    # ---------- sessões ----------
    def sessao_para_medicao(self, device_id, gap_s, paciente=None, forcar_nova=False):
        """Reaproveita a sessão aberta do dispositivo se a última medição foi há menos de gap_s segundos.
        Uma sessão nova recebe os dados do paciente atual."""
        row = self.conn.execute(
            'SELECT id, last_at FROM sessions WHERE device_id = ? ORDER BY id DESC LIMIT 1',
            (device_id,)).fetchone()
        now = agora()
        if row and not forcar_nova:
            delta = (datetime.fromisoformat(now) - datetime.fromisoformat(row['last_at'])).total_seconds()
            if delta <= gap_s:
                self.conn.execute('UPDATE sessions SET last_at = ? WHERE id = ?', (now, row['id']))
                return row['id']
        p = {k: (paciente or {}).get(k) for k in CAMPOS_PACIENTE}
        cur = self.conn.execute(
            f'INSERT INTO sessions (device_id, started_at, last_at, {", ".join(p)}) VALUES (?, ?, ?{", ?" * len(p)})',
            (device_id, now, now, *p.values()))
        return cur.lastrowid

    def listar_sessoes(self, busca=None, limit=500):
        filtro, params = '', []
        if busca:
            filtro = "WHERE s.patient LIKE ? OR s.patient_id LIKE ? OR CAST(s.id AS TEXT) = ?"
            params = [f'%{busca}%', f'%{busca}%', busca]
        rows = self.conn.execute(f"""
            SELECT s.*, COUNT(m.id) AS n_medicoes, (s.device_id = 'simulador') AS simulada,
                   ROUND(AVG(m.bpm), 1) AS bpm_medio,
                   SUM(m.error IS NOT NULL) AS n_erros
            FROM sessions s LEFT JOIN measurements m ON m.session_id = s.id {filtro}
            GROUP BY s.id ORDER BY s.id DESC LIMIT ?""", (*params, limit)).fetchall()
        sessoes = [dict(r) for r in rows]
        for s in sessoes:
            s['classe_final'] = self._classe_final(s['id'])
        return sessoes

    def _classe_final(self, session_id):
        row = self.conn.execute("""
            SELECT classe, COUNT(*) n FROM measurements
            WHERE session_id = ? AND classe IS NOT NULL
            GROUP BY classe ORDER BY n DESC LIMIT 1""", (session_id,)).fetchone()
        return row['classe'] if row else None

    def obter_sessao(self, session_id):
        s = self.conn.execute('SELECT * FROM sessions WHERE id = ?', (session_id,)).fetchone()
        if not s:
            return None
        s = dict(s)
        s['classe_final'] = self._classe_final(session_id)
        meds = self.conn.execute(
            'SELECT id FROM measurements WHERE session_id = ? ORDER BY id', (session_id,)).fetchall()
        s['medicoes'] = [self.obter_medicao(m['id'], incluir_sinal=False) for m in meds]
        return s

    def atualizar_sessao(self, session_id, **campos):
        permitidos = {*CAMPOS_PACIENTE, 'notes', 'parecer', 'parecer_model', 'parecer_at'}
        campos = {k: v for k, v in campos.items() if k in permitidos}
        if not campos:
            return
        sets = ', '.join(f'{k} = ?' for k in campos)
        with self.lock:
            self.conn.execute(f'UPDATE sessions SET {sets} WHERE id = ?', (*campos.values(), session_id))
            self.conn.commit()

    def _ajustar_numeracao(self):
        """O AUTOINCREMENT do SQLite nunca reaproveita números: depois de apagar tudo, a próxima
        sessão continuaria em #8, #9... Aqui o contador volta para o maior id que ainda existe,
        então a próxima numeração continua de onde os registros restantes param (ou do 1)."""
        for tabela in ('sessions', 'measurements', 'beats'):
            self.conn.execute(f"UPDATE sqlite_sequence SET seq = (SELECT COALESCE(MAX(id), 0) FROM {tabela}) "
                              f"WHERE name = '{tabela}'")

    def excluir_sessao(self, session_id):
        with self.lock:
            self.conn.execute('DELETE FROM sessions WHERE id = ?', (session_id,))
            self._ajustar_numeracao()
            self.conn.commit()

    def excluir_medicao(self, mid):
        """Apaga a medição; se a sessão ficar vazia, apaga a sessão também. Devolve True nesse caso."""
        with self.lock:
            sid = self.sessao_da_medicao(mid)
            self.conn.execute('DELETE FROM measurements WHERE id = ?', (mid,))
            vazia = sid is not None and not self.conn.execute(
                'SELECT 1 FROM measurements WHERE session_id = ? LIMIT 1', (sid,)).fetchone()
            if vazia:
                self.conn.execute('DELETE FROM sessions WHERE id = ?', (sid,))
            self._ajustar_numeracao()
            self.conn.commit()
        return vazia

    def ultima_sessao_id(self):
        return self.conn.execute('SELECT MAX(id) FROM sessions').fetchone()[0]

    def sessao_da_medicao(self, mid):
        row = self.conn.execute('SELECT session_id FROM measurements WHERE id = ?', (mid,)).fetchone()
        return row['session_id'] if row else None

    # ---------- medições ----------
    def salvar_medicao(self, device_id, gap_s, fs, raw, resultado=None, erro=None, model_version=None,
                       paciente=None, forcar_nova=False):
        with self.lock:
            session_id = self.sessao_para_medicao(device_id, gap_s, paciente, forcar_nova)
            r = resultado or {}
            cur = self.conn.execute("""
                INSERT INTO measurements (session_id, created_at, fs, raw_signal, filtered, rpeaks,
                                          bpm, classe, distribuicao, hrv, error, model_version)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""", (
                session_id, agora(), fs, json.dumps(list(raw)),
                json.dumps(r['filtered']) if r.get('filtered') else None,
                json.dumps(r['rpeaks']) if r.get('rpeaks') else None,
                r.get('bpm'), r.get('classe'),
                json.dumps(r.get('distribuicao') or {}), json.dumps(r.get('hrv') or {}),
                erro, model_version))
            mid = cur.lastrowid
            for b in r.get('beats', []):
                f = b['features']
                self.conn.execute(f"""
                    INSERT INTO beats (measurement_id, r_sample, {', '.join(FEATURE_COLS)}, pred_label, confidence)
                    VALUES (?, ?, {', '.join('?' * len(FEATURE_COLS))}, ?, ?)""",
                    (mid, b['r_sample'], *[f[c] for c in FEATURE_COLS], b['pred_label'], b['confidence']))
            self.conn.commit()
        return session_id, mid

    def obter_medicao(self, mid, incluir_sinal=True):
        m = self.conn.execute('SELECT * FROM measurements WHERE id = ?', (mid,)).fetchone()
        if not m:
            return None
        m = dict(m)
        for k in ('raw_signal', 'filtered', 'rpeaks', 'distribuicao', 'hrv'):
            if not incluir_sinal and k in ('raw_signal', 'filtered'):
                m.pop(k)
                continue
            m[k] = json.loads(m[k]) if m[k] else None
        m['beats'] = [dict(b) for b in self.conn.execute(
            'SELECT id, r_sample, rr_interval, heart_rate, pred_label, confidence, true_label '
            'FROM beats WHERE measurement_id = ? ORDER BY r_sample', (mid,))]
        return m

    def ultima_medicao_id(self):
        row = self.conn.execute('SELECT MAX(id) AS id FROM measurements').fetchone()
        return row['id']

    # ---------- rotulagem ----------
    def rotular_batimentos(self, beat_ids, label):
        with self.lock:
            self.conn.executemany('UPDATE beats SET true_label = ? WHERE id = ?',
                                  [(label, b) for b in beat_ids])
            self.conn.commit()

    def rotular_medicao(self, mid, label):
        with self.lock:
            self.conn.execute('UPDATE beats SET true_label = ? WHERE measurement_id = ?', (label, mid))
            self.conn.commit()

    # ---------- dataset ----------
    # Só dados reais entram no dataset: sessões do simulador ficam de fora
    REAIS = "m.session_id IN (SELECT id FROM sessions WHERE device_id != 'simulador')"

    def estatisticas(self):
        q = lambda sql: self.conn.execute(sql).fetchone()[0]
        bm = f'FROM beats b JOIN measurements m ON m.id = b.measurement_id WHERE {self.REAIS}'
        por_classe = self.conn.execute(f"""
            SELECT COALESCE(b.true_label, b.pred_label) AS label,
                   COUNT(*) AS total, SUM(b.true_label IS NOT NULL) AS revisados
            {bm} GROUP BY label ORDER BY total DESC""").fetchall()
        return {
            'sessoes': q("SELECT COUNT(*) FROM sessions WHERE device_id != 'simulador'"),
            'sessoes_simuladas': q("SELECT COUNT(*) FROM sessions WHERE device_id = 'simulador'"),
            'medicoes': q(f'SELECT COUNT(*) FROM measurements m WHERE {self.REAIS}'),
            'medicoes_com_erro': q(f'SELECT COUNT(*) FROM measurements m WHERE {self.REAIS} AND m.error IS NOT NULL'),
            'batimentos': q(f'SELECT COUNT(*) {bm}'),
            'batimentos_revisados': q(f'SELECT COUNT(*) {bm} AND b.true_label IS NOT NULL'),
            'por_classe': [dict(r) for r in por_classe],
        }

    def exportar_batimentos(self, somente_revisados):
        extra = 'AND b.true_label IS NOT NULL' if somente_revisados else ''
        return self.conn.execute(f"""
            SELECT {', '.join('b.' + c for c in FEATURE_COLS)}, b.r_sample,
                   COALESCE(b.true_label, b.pred_label) AS label,
                   'app-' || m.session_id || '-' || m.id AS record, m.fs,
                   b.pred_label, b.confidence, (b.true_label IS NOT NULL) AS revisado
            FROM beats b JOIN measurements m ON m.id = b.measurement_id
            WHERE {self.REAIS} {extra}
            ORDER BY b.id""").fetchall()

    def exportar_sinais(self):
        return self.conn.execute(f"""
            SELECT m.id, m.session_id, m.created_at, m.fs, m.classe, m.bpm, m.raw_signal
            FROM measurements m WHERE {self.REAIS} ORDER BY m.id""").fetchall()
