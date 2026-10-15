"""
IC ECG — servidor do aplicativo.

Substitui o server.py original: o endpoint POST /classify continua idêntico para o ESP32
(recebe {"signal": [...]} e devolve {"classe", "bpm"}), mas agora cada medição também é
salva no banco e transmitida ao painel web via WebSocket.

Rodar:  uvicorn main:app --host 0.0.0.0 --port 8000      (dentro da pasta backend)
Painel: http://localhost:8000
"""
import asyncio
import csv
import io
import json
import os
import random
import secrets
from datetime import datetime, timezone
from pathlib import Path

import joblib
from dotenv import load_dotenv
from fastapi import Depends, FastAPI, Header, HTTPException, Request, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

BASE = Path(__file__).resolve().parent
load_dotenv(BASE.parent / '.env')

from database import Database  # noqa: E402
from parecer import ParecerError, gerar_parecer  # noqa: E402
from processing import FEATURE_COLS, ProcessingError, descricoes_classes, processar  # noqa: E402
from simulador import gerar_sinal  # noqa: E402

FS = int(os.getenv('ECG_FS', '100'))
SESSION_GAP_S = int(os.getenv('SESSION_GAP_S', '25'))  # ESP espera 30 s entre ciclos
MODELO_PATH = Path(os.getenv('MODELO_PATH', BASE / 'models' / 'rf_ecg_model.pkl'))
ENCODER_PATH = Path(os.getenv('LABEL_ENCODER_PATH', BASE / 'models' / 'label_encoder.pkl'))
DB_PATH = Path(os.getenv('DB_PATH', BASE.parent / 'data' / 'cardio.db'))

DB_PATH.parent.mkdir(parents=True, exist_ok=True)
db = Database(str(DB_PATH))

modelo = le = None
model_version = None
if MODELO_PATH.exists() and ENCODER_PATH.exists():
    modelo = joblib.load(MODELO_PATH)
    le = joblib.load(ENCODER_PATH)
    model_version = f'{MODELO_PATH.name}@{datetime.fromtimestamp(MODELO_PATH.stat().st_mtime):%Y-%m-%d %H:%M}'
    print(f'[IC ECG] Modelo carregado: {model_version}')
else:
    print(f'[IC ECG] AVISO: modelo não encontrado em {MODELO_PATH} — as medições serão salvas sem classificação.')

# AAMI (N/S/V/F) ou os símbolos do MIT-BIH, conforme o modelo carregado
CLASSES = descricoes_classes(list(le.classes_) if le is not None else None)

app = FastAPI(title='IC ECG')


# ================= Operador: admin x paciente =================
# Modo paciente (padrão): só acompanha as medições do ESP32 e se identifica.
# Modo admin: senha do .env (ADMIN_SENHA) -> token enviado no cabeçalho X-Admin-Token.
ADMIN_SENHA = os.getenv('ADMIN_SENHA', 'admin')
tokens_admin: set[str] = set()


def eh_admin(x_admin_token: str | None = Header(None)) -> bool:
    return bool(x_admin_token) and x_admin_token in tokens_admin


def exigir_admin(admin: bool = Depends(eh_admin)):
    if not admin:
        raise HTTPException(403, 'Disponível apenas no modo administrador')


class LoginInput(BaseModel):
    senha: str


@app.post('/api/auth/login')
def login(body: LoginInput):
    if not secrets.compare_digest(body.senha.encode(), ADMIN_SENHA.encode()):
        raise HTTPException(401, 'Senha incorreta')
    token = secrets.token_urlsafe(24)
    tokens_admin.add(token)
    return {'token': token}


@app.post('/api/auth/logout')
def logout(x_admin_token: str | None = Header(None)):
    tokens_admin.discard(x_admin_token)
    return {'ok': True}


@app.get('/api/auth/status')
def auth_status(admin: bool = Depends(eh_admin)):
    return {'admin': admin, 'senha_padrao': ADMIN_SENHA == 'admin'}


# ================= WebSocket (painel ao vivo) =================
class Hub:
    def __init__(self):
        self.clients: set[WebSocket] = set()

    async def broadcast(self, msg):
        for ws in list(self.clients):
            try:
                await ws.send_json(msg)
            except Exception:
                self.clients.discard(ws)


hub = Hub()


@app.websocket('/ws')
async def ws_endpoint(ws: WebSocket):
    await ws.accept()
    hub.clients.add(ws)
    try:
        while True:
            await ws.receive_text()  # mantém a conexão; o painel não envia nada
    except WebSocketDisconnect:
        hub.clients.discard(ws)


# ================= Endpoint do ESP32 =================
class ECGInput(BaseModel):
    signal: list[float]
    device_id: str = 'esp32'  # opcional — o firmware atual não envia


async def registrar_medicao(sinal, device_id):
    """Processa, salva e avisa o painel. Usado pelo ESP32 e pelo simulador."""
    resultado, erro = None, None
    try:
        resultado = await asyncio.to_thread(processar, sinal, FS, modelo, le)
        if resultado['classe'] is None:
            erro = 'Modelo não carregado'
    except ProcessingError as e:
        erro = str(e)
    except Exception as e:  # nunca derrubar o ESP por um erro inesperado
        erro = f'Erro interno: {e}'

    paciente = db.config_get('paciente_atual')
    forcar_nova = db.config_get('forcar_nova', False)
    session_id, mid = db.salvar_medicao(device_id, SESSION_GAP_S, FS, sinal, resultado, erro, model_version,
                                        paciente, forcar_nova)
    if forcar_nova:
        db.config_set('forcar_nova', False)
    await hub.broadcast({'type': 'measurement', 'session_id': session_id, 'measurement_id': mid})
    return resultado, erro


# Último contato de cada ESP. O firmware não mantém conexão aberta: ele faz um POST por medição
# (a cada ~10 s) e pausa 30 s entre ciclos, então "conectado" = enviou algo há pouco tempo.
dispositivos: dict[str, dict] = {}


@app.get('/api/dispositivos')
def listar_dispositivos():
    agora = datetime.now(timezone.utc)
    return [{**d, 'segundos_desde': round((agora - d['ultimo']).total_seconds(), 1),
             'ultimo': d['ultimo'].isoformat(timespec='seconds')}
            for d in sorted(dispositivos.values(), key=lambda d: d['ultimo'], reverse=True)]


@app.post('/classify')
async def classify(data: ECGInput, request: Request):
    # Atrás do ngrok o IP real do ESP chega no X-Forwarded-For
    ip = (request.headers.get('x-forwarded-for') or (request.client.host if request.client else '?')).split(',')[0].strip()
    d = dispositivos.setdefault(data.device_id, {'device_id': data.device_id, 'medicoes': 0})
    d.update(ip=ip, ultimo=datetime.now(timezone.utc), via_ngrok='x-forwarded-for' in request.headers)
    d['medicoes'] += 1

    resultado, erro = await registrar_medicao(data.signal, data.device_id)
    d['ultimo_erro'] = erro

    # Resposta curta: o ESP32 lê em um DynamicJsonDocument(256)
    if resultado is None or resultado['classe'] is None:
        return {'erro': erro}
    return {'classe': resultado['classe'], 'bpm': resultado['bpm']}


# ================= Simulador (botão do painel) =================
SIM_DEVICE = 'simulador'  # sessões próprias; ficam fora do dataset de treino
sim_state = {'rodando': False}


class SimInput(BaseModel):
    bpm: float = Field(72, ge=30, le=200)
    ruido: float = Field(0.02, ge=0, le=0.5)
    medicoes: int = Field(3, ge=1, le=10)
    intervalo: float = Field(1.0, ge=0, le=15)


async def _rodar_simulacao(p: SimInput):
    try:
        for i in range(p.medicoes):
            await hub.broadcast({'type': 'sim', 'status': 'gerando', 'atual': i + 1, 'total': p.medicoes})
            bpm = p.bpm + random.uniform(-4, 4)
            sinal = await asyncio.to_thread(gerar_sinal, bpm, p.ruido, FS)
            await registrar_medicao(sinal, SIM_DEVICE)
            if i < p.medicoes - 1:
                await asyncio.sleep(p.intervalo)
    finally:
        sim_state['rodando'] = False
        await hub.broadcast({'type': 'sim', 'status': 'fim'})


@app.post('/api/simulate', dependencies=[Depends(exigir_admin)])
async def simulate(p: SimInput):
    if sim_state['rodando']:
        raise HTTPException(409, 'Já existe uma simulação em andamento')
    sim_state['rodando'] = True
    asyncio.create_task(_rodar_simulacao(p))
    return {'ok': True}


# ================= Paciente atual (aba Medição) =================
class PacienteInput(BaseModel):
    patient: str = Field(min_length=1, max_length=120)
    patient_id: str | None = Field(None, max_length=60)
    patient_age: int | None = Field(None, ge=0, le=130)
    patient_sex: str | None = Field(None, pattern='^(F|M|O)$')


@app.get('/api/paciente')
def paciente_atual():
    return {'paciente': db.config_get('paciente_atual'),
            'nova_sessao_pendente': db.config_get('forcar_nova', False)}


@app.post('/api/paciente')
async def definir_paciente(body: PacienteInput):
    """Identifica o paciente; a próxima medição do ESP32 abre uma sessão nova para ele."""
    db.config_set('paciente_atual', body.model_dump())
    db.config_set('forcar_nova', True)
    await hub.broadcast({'type': 'paciente'})
    return paciente_atual()


@app.delete('/api/paciente')
async def limpar_paciente():
    db.config_set('paciente_atual', None)
    db.config_set('forcar_nova', True)
    await hub.broadcast({'type': 'paciente'})
    return paciente_atual()


# ================= API do painel =================
@app.get('/api/info')
def info():
    return {
        'fs': FS,
        'modelo': model_version,
        'classes': CLASSES,
        'parecer_disponivel': bool(os.getenv('ANTHROPIC_API_KEY')),
        'clientes_ao_vivo': len(hub.clients),
        'simulando': sim_state['rodando'],
    }


@app.get('/api/sessions', dependencies=[Depends(exigir_admin)])
def sessions(busca: str | None = None):
    return db.listar_sessoes(busca)


@app.get('/api/sessions/{sid}')
def session(sid: int, admin: bool = Depends(eh_admin)):
    # No modo paciente só a sessão em andamento (a mais recente) pode ser vista
    if not admin and sid != db.ultima_sessao_id():
        raise HTTPException(403, 'Disponível apenas no modo administrador')
    s = db.obter_sessao(sid)
    if not s:
        raise HTTPException(404, 'Sessão não encontrada')
    return s


class SessionUpdate(BaseModel):
    patient: str | None = Field(None, max_length=120)
    patient_id: str | None = Field(None, max_length=60)
    patient_age: int | None = Field(None, ge=0, le=130)
    patient_sex: str | None = Field(None, pattern='^(F|M|O)$')
    notes: str | None = None


@app.patch('/api/sessions/{sid}', dependencies=[Depends(exigir_admin)])
def update_session(sid: int, body: SessionUpdate):
    db.atualizar_sessao(sid, **body.model_dump(exclude_none=True))
    return db.obter_sessao(sid)


@app.delete('/api/sessions/{sid}', dependencies=[Depends(exigir_admin)])
def delete_session(sid: int):
    db.excluir_sessao(sid)
    return {'ok': True}


@app.post('/api/sessions/{sid}/parecer', dependencies=[Depends(exigir_admin)])
async def parecer(sid: int):
    s = db.obter_sessao(sid)
    if not s:
        raise HTTPException(404, 'Sessão não encontrada')
    try:
        texto, model = await asyncio.to_thread(gerar_parecer, s, CLASSES)
    except ParecerError as e:
        raise HTTPException(503, str(e))
    db.atualizar_sessao(sid, parecer=texto, parecer_model=model,
                        parecer_at=datetime.now(timezone.utc).isoformat(timespec='seconds'))
    return db.obter_sessao(sid)


@app.get('/api/measurements/latest')
def latest():
    mid = db.ultima_medicao_id()
    return db.obter_medicao(mid) if mid else None


@app.get('/api/measurements/{mid}')
def measurement(mid: int, admin: bool = Depends(eh_admin)):
    if not admin and db.sessao_da_medicao(mid) != db.ultima_sessao_id():
        raise HTTPException(403, 'Disponível apenas no modo administrador')
    m = db.obter_medicao(mid)
    if not m:
        raise HTTPException(404, 'Medição não encontrada')
    return m


@app.delete('/api/measurements/{mid}', dependencies=[Depends(exigir_admin)])
def delete_measurement(mid: int):
    sessao_excluida = db.excluir_medicao(mid)  # sessão que fica vazia é apagada junto
    return {'ok': True, 'sessao_excluida': sessao_excluida}


class LabelInput(BaseModel):
    label: str | None  # None = remover revisão
    beat_ids: list[int] | None = None  # vazio = todos os batimentos da medição


@app.post('/api/measurements/{mid}/label', dependencies=[Depends(exigir_admin)])
def label(mid: int, body: LabelInput):
    if body.label is not None and body.label not in CLASSES:
        raise HTTPException(400, 'Classe inválida')
    if body.beat_ids:
        db.rotular_batimentos(body.beat_ids, body.label)
    else:
        db.rotular_medicao(mid, body.label)
    return db.obter_medicao(mid, incluir_sinal=False)


# ================= Dataset =================
@app.get('/api/dataset/stats', dependencies=[Depends(exigir_admin)])
def dataset_stats():
    return db.estatisticas()


def _csv_response(header, rows, nome):
    buf = io.StringIO()
    w = csv.writer(buf)
    w.writerow(header)
    w.writerows(rows)
    buf.seek(0)
    return StreamingResponse(iter([buf.getvalue()]), media_type='text/csv',
                             headers={'Content-Disposition': f'attachment; filename="{nome}"'})


@app.get('/api/dataset/features.csv', dependencies=[Depends(exigir_admin)])
def export_features(somente_revisados: bool = False):
    """Mesmo formato do ecg_features.csv (+ colunas extras) — pronto para o rf.py."""
    rows = db.exportar_batimentos(somente_revisados)
    header = FEATURE_COLS + ['r_sample', 'label', 'record', 'fs', 'pred_label', 'confidence', 'revisado']
    return _csv_response(header, [tuple(r) for r in rows], 'app_ecg_features.csv')


@app.get('/api/dataset/signals.jsonl', dependencies=[Depends(exigir_admin)])
def export_signals():
    """Sinais brutos de todas as medições (para treinar modelos que usam o sinal direto, ex.: CNN)."""
    def gen():
        for r in db.exportar_sinais():
            d = dict(r)
            d['raw_signal'] = json.loads(d['raw_signal'])
            yield json.dumps(d) + '\n'
    return StreamingResponse(gen(), media_type='application/x-ndjson',
                             headers={'Content-Disposition': 'attachment; filename="app_ecg_signals.jsonl"'})


# ================= Frontend =================
FRONT = BASE.parent / 'frontend'
app.mount('/static', StaticFiles(directory=FRONT), name='static')


@app.middleware('http')
async def sem_cache_no_front(request, call_next):
    # Sem isso o navegador reaproveita um app.js antigo depois de uma atualização
    response = await call_next(request)
    if request.url.path == '/' or request.url.path.startswith('/static/'):
        response.headers['Cache-Control'] = 'no-cache'
    return response


@app.get('/')
def index():
    return FileResponse(FRONT / 'index.html')
