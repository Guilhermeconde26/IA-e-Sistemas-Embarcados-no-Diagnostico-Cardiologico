// IC ECG — painel web
const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const MEDICOES_POR_CICLO = 10; // TOTAL_MEDICOES do firmware

const state = { info: null, admin: false, token: null, paciente: null, pendente: false,
  liveSession: null, liveMeasurement: null, report: null, med: null, anim: null };

// Cores das classes (tons escuros o bastante para fundo branco)
const CLASS_COLORS = { N: '#1f9d55', S: '#c27c0e', V: '#d64545', F: '#8b5cf6', Q: '#64748b',
  A: '#c27c0e', a: '#b45309', L: '#2563eb', R: '#7c3aed', J: '#a16207', j: '#a16207', E: '#b91c1c', e: '#ea580c', '/': '#64748b', f: '#94a3b8' };
const colorOf = (c) => CLASS_COLORS[c] || '#64748b';
const descOf = (c) => (state.info?.classes || {})[c] || c || '';
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (ch) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch]));
const tag = (c, extra = '') => c ? `<span class="tag" style="--c:${colorOf(c)}" title="${esc(descOf(c))}">${esc(c)}${extra}</span>` : '<span class="hint">—</span>';
const fmtDate = (iso) => iso ? new Date(iso).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' }) : '--';
const fmtTime = (iso) => iso ? new Date(iso).toLocaleTimeString('pt-BR') : '--';
const SEXO = { F: 'Feminino', M: 'Masculino', O: 'Outro' };
const simBadge = (s) => s.device_id === 'simulador' ? '<span class="badge">simulada</span>' : '';

/** Diálogo próprio no lugar de confirm()/alert() — navegadores embutidos costumam bloquear os nativos
 *  (o confirm() devolve false na hora e nada acontece). Resolve true se o usuário confirmar. */
function confirmar(titulo, mensagem, { ok = 'Confirmar', perigo = false, soAviso = false } = {}) {
  const dlg = $('#confirm-dialog');
  $('#confirm-title').textContent = titulo;
  $('#confirm-msg').textContent = mensagem;
  $('#confirm-ok').textContent = ok;
  $('#confirm-ok').classList.toggle('danger-fill', perigo);
  $('#confirm-cancel').hidden = soAviso;
  dlg.returnValue = '';
  dlg.showModal();
  $('#confirm-ok').focus();
  return new Promise((resolve) => dlg.addEventListener('close', () => resolve(dlg.returnValue === 'ok'), { once: true }));
}
const aviso = (titulo, mensagem) => confirmar(titulo, mensagem, { ok: 'OK', soAviso: true });

function store(key, val) { try { val == null ? localStorage.removeItem(key) : localStorage.setItem(key, val); } catch {} }
function load(key) { try { return localStorage.getItem(key); } catch { return null; } }

async function api(path, opts = {}) {
  const headers = { 'Content-Type': 'application/json', ...(state.token ? { 'X-Admin-Token': state.token } : {}) };
  const res = await fetch(path, { ...opts, headers });
  if (!res.ok) {
    let msg = res.statusText;
    try { msg = (await res.json()).detail || msg; } catch {}
    if (res.status === 403 && state.admin) await refreshAuth(); // token expirou (servidor reiniciado)
    throw Object.assign(new Error(typeof msg === 'string' ? msg : 'Dados inválidos'), { status: res.status });
  }
  return res.json();
}

// ================= Desenho do ECG =================
const cssVar = (name) => getComputedStyle(document.documentElement).getPropertyValue(name).trim();

function setupCanvas(canvas) {
  const dpr = window.devicePixelRatio || 1;
  const w = canvas.clientWidth, h = canvas.clientHeight;
  if (canvas.width !== Math.round(w * dpr) || canvas.height !== Math.round(h * dpr)) {
    canvas.width = Math.round(w * dpr); canvas.height = Math.round(h * dpr);
  }
  const ctx = canvas.getContext('2d');
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  return { ctx, w, h };
}

const resizeObs = new ResizeObserver((entries) => {
  // durante a varredura o próprio loop de animação redesenha no frame seguinte
  for (const e of entries) if (e.target._ecg) { const [s, fs, o] = e.target._ecg; drawECG(e.target, s, fs, { ...o, progress: 1 }); }
});

/** opts: rpeaks, beatLabels (Map r_sample -> classe), progress (0..1), grid, labels, highlight, lineWidth */
function drawECG(canvas, sig, fs, opts = {}) {
  if (!canvas._ecg) resizeObs.observe(canvas);
  canvas._ecg = [sig, fs, opts];
  const { ctx, w, h } = setupCanvas(canvas);
  if (!w) return;
  const { rpeaks = [], beatLabels = new Map(), progress = 1, grid = true, labels = true, highlight = null, lineWidth = 1.7 } = opts;
  ctx.fillStyle = cssVar('--ecg-bg'); ctx.fillRect(0, 0, w, h);
  if (!sig || !sig.length) {
    if (labels) { ctx.fillStyle = cssVar('--muted'); ctx.font = '14px Inter, system-ui'; ctx.textAlign = 'center';
      ctx.fillText('Aguardando sinal do ECG…', w / 2, h / 2); ctx.textAlign = 'left'; }
    return;
  }
  const dur = sig.length / fs;
  const padTop = labels ? 24 : 4, padBot = labels ? 18 : 4;
  let lo = Infinity, hi = -Infinity;
  for (const v of sig) { if (v < lo) lo = v; if (v > hi) hi = v; }
  const span = (hi - lo) || 1;
  const x = (i) => (i / (sig.length - 1)) * w;
  const y = (v) => padTop + (1 - (v - lo) / span) * (h - padTop - padBot);

  if (grid) { // papel milimetrado: 0,04 s / 0,2 s
    const pxPerS = w / dur;
    for (const [step, color] of [[0.04, cssVar('--ecg-grid')], [0.2, cssVar('--ecg-grid-major')]]) {
      if (pxPerS * step < 4) continue;
      ctx.strokeStyle = color; ctx.lineWidth = 1; ctx.beginPath();
      for (let t = 0; t <= dur + 1e-9; t += step) { const px = Math.round(t * pxPerS) + .5; ctx.moveTo(px, 0); ctx.lineTo(px, h); }
      for (let py = h; py >= 0; py -= pxPerS * step) { const yy = Math.round(py) + .5; ctx.moveTo(0, yy); ctx.lineTo(w, yy); }
      ctx.stroke();
    }
    if (labels) {
      ctx.fillStyle = cssVar('--muted'); ctx.font = '10px Inter, system-ui';
      for (let t = 1; t < dur; t++) ctx.fillText(`${t}s`, t * pxPerS + 3, h - 5);
    }
  }

  const n = Math.max(2, Math.floor(sig.length * progress));
  ctx.strokeStyle = cssVar('--ecg-trace'); ctx.lineWidth = lineWidth; ctx.lineJoin = 'round';
  ctx.beginPath();
  for (let i = 0; i < n; i++) i ? ctx.lineTo(x(i), y(sig[i])) : ctx.moveTo(x(i), y(sig[i]));
  ctx.stroke();
  if (progress < 1) {
    ctx.fillStyle = cssVar('--accent');
    ctx.beginPath(); ctx.arc(x(n - 1), y(sig[n - 1]), 4, 0, Math.PI * 2); ctx.fill();
  }
  for (const r of rpeaks) {
    if (r >= n) continue;
    const lbl = beatLabels.get(r), c = lbl ? colorOf(lbl) : '#94a3b8';
    if (highlight === r) { ctx.fillStyle = 'rgba(76,201,130,.15)'; ctx.fillRect(x(r) - 12, 0, 24, h); }
    ctx.fillStyle = c;
    ctx.beginPath(); ctx.arc(x(r), y(sig[r]), labels ? 3.5 : 2, 0, Math.PI * 2); ctx.fill();
    if (labels && lbl) { ctx.font = '700 12px Inter, system-ui'; ctx.textAlign = 'center'; ctx.fillText(lbl, x(r), 15); ctx.textAlign = 'left'; }
  }
}
const measurementSignal = (m) => m.filtered || m.raw_signal || [];
const beatMap = (m) => new Map((m.beats || []).map((b) => [b.r_sample, b.true_label || b.pred_label]));
const drawMeasurement = (canvas, m, extra = {}) => drawECG(canvas, measurementSignal(m), m.fs, { rpeaks: m.rpeaks || [], beatLabels: beatMap(m), ...extra });

// ================= Navegação =================
function show(view) {
  if (view === 'results' && !state.admin) view = 'measure';
  $$('.view').forEach((v) => v.classList.toggle('active', v.id === `view-${view}`));
  $$('nav button').forEach((b) => b.classList.toggle('active', b.dataset.view === view));
  if (view === 'results') showResultsList();
  if (view === 'operator') loadOperator();
  window.scrollTo(0, 0);
}
$$('nav button').forEach((b) => b.addEventListener('click', () => show(b.dataset.view)));
const activeView = () => $('.view.active')?.id.replace('view-', '');

// ================= Modo admin x paciente =================
function applyMode(status) {
  state.admin = !!status.admin;
  document.body.classList.toggle('is-admin', state.admin);
  $('#mode-pill').textContent = state.admin ? 'Administrador' : 'Modo paciente';
  $('#mode-pill').classList.toggle('admin', state.admin);
  $('#mode-opt-admin').classList.toggle('current', state.admin);
  $('#mode-opt-patient').classList.toggle('current', !state.admin);
  $('#default-pass-alert').hidden = !status.senha_padrao;
  if (!state.admin && activeView() === 'results') show('measure');
}
async function refreshAuth() {
  const st = await fetch('/api/auth/status', { headers: state.token ? { 'X-Admin-Token': state.token } : {} }).then((r) => r.json());
  if (!st.admin && state.token) { state.token = null; store('icecg_token', null); }
  applyMode(st);
}
$('#login-form').addEventListener('submit', async (ev) => {
  ev.preventDefault();
  const senha = new FormData(ev.target).get('senha');
  try {
    const { token } = await api('/api/auth/login', { method: 'POST', body: JSON.stringify({ senha }) });
    state.token = token; store('icecg_token', token);
    ev.target.reset(); $('#login-msg').textContent = '';
    await refreshAuth(); loadOperator();
  } catch (e) { $('#login-msg').innerHTML = `<span class="err">${esc(e.message)}</span>`; }
});
$('#logout-btn').addEventListener('click', async () => {
  await api('/api/auth/logout', { method: 'POST' }).catch(() => {});
  state.token = null; store('icecg_token', null);
  await refreshAuth();
  show('measure');
});

// ================= Medição: paciente =================
async function loadPaciente() {
  const p = await api('/api/paciente');
  state.paciente = p.paciente; state.pendente = p.nova_sessao_pendente;
  renderPaciente();
}
function renderPaciente(editing = false) {
  const p = state.paciente, form = $('#patient-form');
  $('#patient-current').hidden = !p || editing;
  form.hidden = !!p && !editing;
  $('#patient-cancel').hidden = !p;
  if (p) {
    $('#patient-avatar').textContent = p.patient.split(/\s+/).filter(Boolean).slice(0, 2).map((s) => s[0]).join('').toUpperCase();
    $('#patient-name').textContent = p.patient;
    $('#patient-meta').textContent = [p.patient_id && `Prontuário ${p.patient_id}`, p.patient_age != null && `${p.patient_age} anos`, SEXO[p.patient_sex]].filter(Boolean).join(' · ') || 'Sem dados adicionais';
    const box = $('#patient-status');
    const sessaoDoPaciente = state.liveSession && !state.pendente;
    box.className = 'status-box' + (state.pendente ? '' : ' idle');
    box.innerHTML = state.pendente
      ? '<span class="pulse"></span><span>Pronto. Aguardando a primeira medição do ECG…</span>'
      : `<span>${sessaoDoPaciente ? `Sessão #${state.liveSession.id} em andamento` : 'Sessão em andamento'}</span>`;
    if (editing) for (const [k, v] of Object.entries(p)) if (form.elements[k]) form.elements[k].value = v ?? '';
  }
}
$('#patient-form').addEventListener('submit', async (ev) => {
  ev.preventDefault();
  const f = new FormData(ev.target);
  const body = { patient: f.get('patient').trim(), patient_id: f.get('patient_id').trim() || null,
    patient_age: f.get('patient_age') ? +f.get('patient_age') : null, patient_sex: f.get('patient_sex') || null };
  try {
    await api('/api/paciente', { method: 'POST', body: JSON.stringify(body) });
    ev.target.reset();
    await loadPaciente(); resetLive();
  } catch (e) { aviso('Não foi possível identificar o paciente', e.message); }
});
$('#patient-change').addEventListener('click', () => { $('#patient-form').reset(); renderPaciente(true); });
$('#patient-cancel').addEventListener('click', () => renderPaciente(false));
$('#patient-new-session').addEventListener('click', async () => {
  await api('/api/paciente', { method: 'POST', body: JSON.stringify(state.paciente) });
  await loadPaciente(); resetLive();
});

// ================= Medição: monitor =================
function resetLive() {
  cancelAnimationFrame(state.anim);
  state.liveMeasurement = null; state.liveSession = null;
  $('#live-bpm').textContent = '--'; $('#live-classe').innerHTML = '--';
  $('#live-classe-desc').textContent = 'aguardando'; $('#live-hora').textContent = '--'; $('#live-erro').textContent = '';
  $('#live-count').textContent = '0'; $('#live-progress').style.width = '0';
  $('#live-dist').innerHTML = ''; $('#live-session-label').textContent = '';
  $('#live-strip').innerHTML = '<div class="empty">Nenhuma medição ainda.</div>';
  drawECG($('#live-ecg'), [], 100);
  renderPaciente();
}

async function loadLive(measurementId, animate) {
  const m = measurementId ? await api(`/api/measurements/${measurementId}`) : await api('/api/measurements/latest');
  if (!m) return resetLive();
  state.liveMeasurement = m;
  $('#live-bpm').textContent = m.bpm ?? '--';
  $('#live-classe').innerHTML = m.classe ? tag(m.classe) : '--';
  $('#live-classe-desc').textContent = m.classe ? descOf(m.classe) : (m.error ? 'falha na medição' : '');
  $('#live-hora').textContent = fmtTime(m.created_at);
  $('#live-erro').textContent = m.error || '';
  $('#live-dist').innerHTML = Object.entries(m.distribuicao || {}).map(([c, n]) => tag(c, ` ${n}`)).join('');

  const canvas = $('#live-ecg'), sig = measurementSignal(m);
  cancelAnimationFrame(state.anim);
  if (animate && sig.length) { // varredura na duração real da aquisição, como um monitor
    const t0 = performance.now(), dur = Math.min(10000, (sig.length / m.fs) * 1000);
    const step = (t) => {
      const p = Math.min(1, (t - t0) / dur);
      drawMeasurement(canvas, m, { progress: p });
      if (p < 1) state.anim = requestAnimationFrame(step);
    };
    state.anim = requestAnimationFrame(step);
  } else drawMeasurement(canvas, m);
  await loadLiveSession(m.session_id, animate ? m.id : null);
}

async function loadLiveSession(sid, newId) {
  const s = await api(`/api/sessions/${sid}`);
  state.liveSession = s;
  const n = s.medicoes.length;
  $('#live-count').textContent = `${n}/${MEDICOES_POR_CICLO}`;
  $('#live-progress').style.width = `${Math.min(100, (n / MEDICOES_POR_CICLO) * 100)}%`;
  $('#live-session-label').innerHTML = `· sessão #${s.id}${s.patient ? ' · ' + esc(s.patient) : ''}${simBadge(s)}${s.classe_final ? ` · classe predominante ${tag(s.classe_final)}` : ''}`;
  const strip = $('#live-strip');
  strip.innerHTML = '';
  for (const m of s.medicoes.slice().reverse()) {
    const el = document.createElement('div');
    el.className = 'strip-item' + (m.id === newId ? ' new' : '');
    el.innerHTML = `<canvas></canvas><div class="row"><span>${fmtTime(m.created_at)}</span><span>${m.bpm ?? '--'} bpm</span>${m.error ? '<span class="err">erro</span>' : tag(m.classe)}</div>`;
    el.addEventListener('click', () => openMeasurement(m.id));
    strip.appendChild(el);
    api(`/api/measurements/${m.id}`).then((full) => drawMeasurement(el.querySelector('canvas'), full, { grid: false, labels: false, lineWidth: 1.1 })).catch(() => {});
  }
  renderPaciente();
}

// ================= Resultados =================
function showResultsList() {
  $('#results-list').hidden = false; $('#results-report').hidden = true;
  loadSessions();
}
async function loadSessions() {
  const q = $('#results-search').elements.q.value.trim();
  const rows = await api('/api/sessions' + (q ? `?busca=${encodeURIComponent(q)}` : ''));
  const tb = $('#sessions-table tbody');
  tb.innerHTML = rows.length ? '' : `<tr><td colspan="8" class="empty">${q ? 'Nenhuma sessão encontrada.' : 'Nenhuma sessão registrada ainda.'}</td></tr>`;
  for (const s of rows) {
    const tr = document.createElement('tr');
    tr.className = 'click';
    tr.innerHTML = `<td>#${s.id}${simBadge(s)}</td>
      <td><b>${esc(s.patient || 'Não identificado')}</b>${s.patient_id ? `<br><span class="hint">${esc(s.patient_id)}</span>` : ''}</td>
      <td>${fmtDate(s.started_at)}</td>
      <td>${s.n_medicoes}${s.n_erros ? ` <span class="err">(${s.n_erros} erro)</span>` : ''}</td>
      <td>${s.bpm_medio ?? '--'}</td><td>${tag(s.classe_final)}</td><td>${s.parecer ? '<span class="ok">✓ gerado</span>' : '<span class="hint">—</span>'}</td>
      <td class="actions"><button class="btn sm">Abrir</button> <button class="btn sm danger" data-del>Excluir</button></td>`;
    tr.addEventListener('click', (ev) => {
      if (ev.target.closest('[data-del]')) return deleteSession(s.id, s.patient);
      openReport(s.id);
    });
    tb.appendChild(tr);
  }
}
$('#results-search').addEventListener('submit', (ev) => { ev.preventDefault(); loadSessions(); });
$('#results-search').elements.q.addEventListener('search', loadSessions);

async function deleteSession(id, nome) {
  const ok = await confirmar(`Excluir a sessão #${id}?`,
    `${nome ? `Paciente: ${nome}\n` : ''}A sessão e todas as suas medições serão apagadas do banco. Isso não pode ser desfeito.`,
    { ok: 'Excluir', perigo: true });
  if (!ok) return false;
  try {
    await api(`/api/sessions/${id}`, { method: 'DELETE' });
  } catch (e) { aviso('Não foi possível excluir', e.message); return false; }
  if (state.liveSession?.id === id) resetLive();
  loadSessions();
  return true;
}

async function openReport(sid) {
  const s = await api(`/api/sessions/${sid}`);
  state.report = s;
  $('#results-list').hidden = true; $('#results-report').hidden = false;
  window.scrollTo(0, 0);
  $('#report-title').innerHTML = `Sessão #${s.id} <span class="hint" style="font-size:1rem;font-weight:500">${fmtDate(s.started_at)}</span>${simBadge(s)}`;
  const form = $('#report-form');
  for (const k of ['patient', 'patient_id', 'patient_age', 'patient_sex', 'notes']) form.elements[k].value = s[k] ?? '';

  const ok = s.medicoes.filter((m) => !m.error);
  const avg = (arr) => arr.length ? arr.reduce((a, b) => a + b, 0) / arr.length : null;
  const bpm = avg(ok.map((m) => m.bpm).filter(Boolean));
  const sdnn = avg(ok.map((m) => m.hrv?.sdnn_ms).filter((v) => v != null));
  $('#report-kpis').innerHTML = `
    <div class="kpi"><label>BPM médio</label><b>${bpm ? bpm.toFixed(1) : '--'}</b></div>
    <div class="kpi"><label>Classe predominante</label><b>${s.classe_final ? tag(s.classe_final) : '--'}</b><small>${esc(descOf(s.classe_final))}</small></div>
    <div class="kpi"><label>Medições válidas</label><b>${ok.length}/${s.medicoes.length}</b></div>
    <div class="kpi"><label>SDNN médio</label><b>${sdnn != null ? sdnn.toFixed(0) : '--'}<small> ms</small></b></div>`;

  const counts = {};
  for (const m of s.medicoes) for (const b of m.beats) { const c = b.true_label || b.pred_label; if (c) counts[c] = (counts[c] || 0) + 1; }
  const total = Object.values(counts).reduce((a, b) => a + b, 0);
  $('#report-bars').innerHTML = Object.entries(counts).sort((a, b) => b[1] - a[1]).map(([c, n]) =>
    `<div class="bar" title="${esc(descOf(c))}"><span>${tag(c)}</span><div class="track"><div class="fill" style="--c:${colorOf(c)};width:${(n / total) * 100}%"></div></div><span>${n} (${Math.round((n / total) * 100)}%)</span></div>`).join('')
    || '<p class="hint">Sem batimentos classificados.</p>';

  renderParecer(s);
  const meds = $('#report-meds');
  meds.innerHTML = s.medicoes.length ? '' : '<div class="empty">Sessão sem medições.</div>';
  for (const m of s.medicoes) {
    const reviewed = m.beats.filter((b) => b.true_label).length;
    const el = document.createElement('div');
    el.className = 'med';
    el.innerHTML = `<canvas></canvas><div class="row"><span>#${m.id} · ${fmtTime(m.created_at)}</span>
      <span>${m.bpm ?? '--'} bpm</span>${m.error ? `<span class="err">${esc(m.error)}</span>` : tag(m.classe)}</div>
      <div class="row"><span>${Object.entries(m.distribuicao || {}).map(([c, n]) => tag(c, ` ${n}`)).join(' ')}</span>
      ${reviewed ? `<span class="reviewed">✓ ${reviewed}/${m.beats.length} revisados</span>` : ''}</div>`;
    el.addEventListener('click', () => openMeasurement(m.id));
    meds.appendChild(el);
    api(`/api/measurements/${m.id}`).then((full) => drawMeasurement(el.querySelector('canvas'), full, { labels: false, lineWidth: 1.1 }));
  }
}

function renderParecer(s) {
  const box = $('#report-parecer');
  $('#report-parecer-btn').textContent = s.parecer ? 'Gerar novamente' : 'Gerar parecer';
  if (!s.parecer) { box.innerHTML = '<p class="hint">Nenhum parecer gerado ainda.</p>'; return; }
  const html = window.marked && window.DOMPurify ? DOMPurify.sanitize(marked.parse(s.parecer)) : `<pre>${esc(s.parecer)}</pre>`;
  box.innerHTML = `${html}<p class="meta">Gerado por ${esc(s.parecer_model)} em ${fmtDate(s.parecer_at)}</p>`;
}

$('#report-back').addEventListener('click', showResultsList);
$('#report-pdf').addEventListener('click', () => {
  $('#print-date').textContent = `Emitido em ${new Date().toLocaleString('pt-BR')}`;
  const titulo = document.title;
  document.title = `IC ECG - Sessao ${state.report.id}${state.report.patient ? ' - ' + state.report.patient : ''}`; // nome sugerido do PDF
  window.print();
  document.title = titulo;
});
$('#report-form').addEventListener('submit', async (ev) => {
  ev.preventDefault();
  const f = new FormData(ev.target);
  const body = { patient: f.get('patient').trim() || null, patient_id: f.get('patient_id').trim() || null,
    patient_age: f.get('patient_age') ? +f.get('patient_age') : null, patient_sex: f.get('patient_sex') || null, notes: f.get('notes') };
  try {
    await api(`/api/sessions/${state.report.id}`, { method: 'PATCH', body: JSON.stringify(body) });
    $('#report-save').textContent = 'Salvo ✓';
  } catch (e) { $('#report-save').textContent = 'Erro: ' + e.message; }
  setTimeout(() => ($('#report-save').textContent = 'Salvar alterações'), 1800);
});
$('#report-delete').addEventListener('click', async () => {
  if (await deleteSession(state.report.id, state.report.patient)) showResultsList();
});
$('#report-parecer-btn').addEventListener('click', async () => {
  const btn = $('#report-parecer-btn'), box = $('#report-parecer');
  btn.disabled = true; btn.textContent = 'Gerando…';
  box.innerHTML = '<p class="hint">A IA está analisando as medições…</p>';
  try {
    const s = await api(`/api/sessions/${state.report.id}/parecer`, { method: 'POST' });
    state.report = s; renderParecer(s);
  } catch (e) {
    box.innerHTML = `<p class="err">${esc(e.message)}</p>`;
    btn.textContent = 'Tentar novamente';
  } finally { btn.disabled = false; }
});

// ================= Detalhe da medição =================
function classOptions(selected) {
  return `<option value="" ${!selected ? 'selected' : ''}>(não revisado)</option>` +
    Object.entries(state.info?.classes || {}).map(([k, v]) => `<option value="${esc(k)}" ${k === selected ? 'selected' : ''}>${esc(k)} — ${esc(v)}</option>`).join('');
}
async function openMeasurement(mid, highlight = null) {
  const m = await api(`/api/measurements/${mid}`);
  state.med = m;
  const dlg = $('#med-dialog');
  $('#med-title').textContent = `Medição #${m.id} — ${fmtDate(m.created_at)}`;
  const hrv = m.hrv || {};
  $('#med-info').textContent = m.error ? `Erro: ${m.error}` :
    `${m.bpm} bpm · SDNN ${hrv.sdnn_ms ?? '--'} ms · RMSSD ${hrv.rmssd_ms ?? '--'} ms`;
  $('#med-label-all').innerHTML = classOptions(null);
  if (!dlg.open) dlg.showModal();
  drawMeasurement($('#med-ecg'), m, { highlight });

  const tb = $('#med-beats tbody');
  tb.innerHTML = m.beats.length ? '' : '<tr><td colspan="7" class="empty">Nenhum batimento extraído.</td></tr>';
  m.beats.forEach((b, i) => {
    const tr = document.createElement('tr');
    tr.innerHTML = `<td>${i + 1}</td><td>${(b.r_sample / m.fs).toFixed(2)}</td><td>${b.rr_interval.toFixed(3)}</td>
      <td>${b.heart_rate.toFixed(0)}</td><td>${tag(b.pred_label)}</td>
      <td>${b.confidence != null ? Math.round(b.confidence * 100) + '%' : '--'}</td>
      <td class="admin-only"><select>${classOptions(b.true_label)}</select></td>`;
    tr.addEventListener('mouseenter', () => drawMeasurement($('#med-ecg'), m, { highlight: b.r_sample }));
    tr.querySelector('select').addEventListener('change', async (ev) => {
      await api(`/api/measurements/${m.id}/label`, { method: 'POST', body: JSON.stringify({ label: ev.target.value || null, beat_ids: [b.id] }) });
      b.true_label = ev.target.value || null;
      drawMeasurement($('#med-ecg'), m, { highlight: b.r_sample });
    });
    tb.appendChild(tr);
  });
}
$('#med-close').addEventListener('click', () => $('#med-dialog').close());
$('#med-dialog').addEventListener('close', () => {
  if (state.report && !$('#results-report').hidden && activeView() === 'results') openReport(state.report.id);
});
$('#med-label-apply').addEventListener('click', async () => {
  await api(`/api/measurements/${state.med.id}/label`, { method: 'POST', body: JSON.stringify({ label: $('#med-label-all').value || null }) });
  openMeasurement(state.med.id);
});
$('#med-delete').addEventListener('click', async () => {
  const ultima = state.report && !$('#results-report').hidden && state.report.medicoes.length === 1;
  const ok = await confirmar(`Excluir a medição #${state.med.id}?`,
    'A medição e seus batimentos serão apagados do banco. Isso não pode ser desfeito.' +
    (ultima ? '\nÉ a última medição da sessão, então a sessão também será excluída.' : ''), { ok: 'Excluir', perigo: true });
  if (!ok) return;
  let r;
  try {
    r = await api(`/api/measurements/${state.med.id}`, { method: 'DELETE' });
  } catch (e) { return aviso('Não foi possível excluir', e.message); }
  if (r.sessao_excluida) {
    if (state.report?.id === state.med.session_id) state.report = null; // evita reabrir o relatório apagado
    if (activeView() === 'results') showResultsList();
  }
  $('#med-dialog').close();
  if (state.liveSession) loadLive(null, false).catch(() => resetLive());
});

// ================= Operador =================
async function loadOperator() {
  const info = await api('/api/info');
  state.info = info;
  $('#sys-info').innerHTML = `
    <dt>Modelo</dt><dd>${esc(info.modelo || 'não carregado')}</dd>
    <dt>Classes</dt><dd>${Object.keys(info.classes).map((c) => tag(c)).join(' ')}</dd>
    <dt>Amostragem</dt><dd>${info.fs} Hz</dd>
    <dt>Parecer da IA</dt><dd>${info.parecer_disponivel ? '<span class="ok">configurado</span>' : '<span class="err">sem chave da API</span>'}</dd>
    <dt>Telas conectadas</dt><dd>${info.clientes_ao_vivo}</dd>`;
  if (!state.admin) return;
  const d = await api('/api/dataset/stats');
  $('#ds-kpis').innerHTML = `
    <div class="kpi"><label>Sessões reais</label><b>${d.sessoes}</b><small>${d.sessoes_simuladas} simuladas (fora do dataset)</small></div>
    <div class="kpi"><label>Medições</label><b>${d.medicoes}</b><small>${d.medicoes_com_erro} com erro</small></div>
    <div class="kpi"><label>Batimentos</label><b>${d.batimentos}</b></div>
    <div class="kpi"><label>Revisados</label><b>${d.batimentos_revisados}</b><small>${d.batimentos ? Math.round(d.batimentos_revisados / d.batimentos * 100) : 0}% do total</small></div>`;
  $('#ds-table tbody').innerHTML = d.por_classe.map((r) =>
    `<tr><td>${tag(r.label)}</td><td>${esc(descOf(r.label))}</td><td>${r.total}</td><td>${r.revisados}</td></tr>`).join('')
    || '<tr><td colspan="4" class="empty">Sem dados reais ainda.</td></tr>';
}
$$('[data-export]').forEach((btn) => btn.addEventListener('click', async () => {
  // download com o token no cabeçalho (um link simples não enviaria)
  const res = await fetch(btn.dataset.export, { headers: { 'X-Admin-Token': state.token || '' } });
  if (!res.ok) return aviso('Não foi possível exportar', `O servidor respondeu ${res.status}.`);
  const url = URL.createObjectURL(await res.blob());
  Object.assign(document.createElement('a'), { href: url, download: btn.dataset.name }).click();
  setTimeout(() => URL.revokeObjectURL(url), 2000);
}));

function simStatus(msg) {
  const btn = $('#sim-btn'), st = $('#sim-status');
  if (msg.status === 'gerando') {
    btn.disabled = true; btn.textContent = 'Simulando…';
    st.textContent = `Medição ${msg.atual} de ${msg.total}`;
  } else {
    btn.disabled = false; btn.textContent = 'Simular';
    st.innerHTML = '<span class="ok">Simulação concluída</span>';
    setTimeout(() => (st.textContent = ''), 4000);
  }
}
$('#sim-form').addEventListener('submit', async (ev) => {
  ev.preventDefault();
  const f = new FormData(ev.target);
  const body = { bpm: +f.get('bpm'), ruido: +f.get('ruido'), medicoes: +f.get('medicoes'), intervalo: 1 };
  const btn = $('#sim-btn');
  btn.disabled = true; btn.textContent = 'Simulando…';
  try {
    await api('/api/simulate', { method: 'POST', body: JSON.stringify(body) });
  } catch (e) {
    btn.disabled = false; btn.textContent = 'Simular';
    $('#sim-status').innerHTML = `<span class="err">${esc(e.message)}</span>`;
  }
});

// ================= Status do ESP32 =================
// O ESP não fica conectado: manda um POST a cada medição (~10 s) e pausa 30 s entre ciclos.
const ESP_ATIVO_S = 45;      // até aqui: conectado (cobre a pausa entre ciclos)
const ESP_AGUARDANDO_S = 300; // até aqui: aguardando (eletrodo solto, reiniciando...); depois: offline
state.esp = [];

async function loadDispositivos() {
  try {
    const lista = await api('/api/dispositivos');
    const agora = Date.now();
    state.esp = lista.map((d) => ({ ...d, visto: agora - d.segundos_desde * 1000 })); // relógio local, imune a fuso
  } catch {}
  renderEsp();
}
function tempoDesde(ms) {
  const s = Math.round(ms / 1000);
  return s < 60 ? `${s} s` : s < 3600 ? `${Math.floor(s / 60)} min` : `${Math.floor(s / 3600)} h`;
}
function renderEsp() {
  const pill = $('#esp-pill'), d = state.esp[0];
  const idade = d ? (Date.now() - d.visto) / 1000 : Infinity;
  const estado = idade <= ESP_ATIVO_S ? 'on' : idade <= ESP_AGUARDANDO_S ? 'idle' : 'off';
  pill.className = `pill esp ${estado}`;
  const nome = d ? d.device_id.toUpperCase() : 'ESP';
  $('#esp-text').textContent = { on: `${nome} conectado`, idle: `${nome} aguardando`, off: 'ESP offline' }[estado];
  pill.title = d
    ? `${nome} · IP ${d.ip}${d.via_ngrok ? ' (via ngrok)' : ''} · última medição há ${tempoDesde(Date.now() - d.visto)} · ${d.medicoes} medições desde que o servidor iniciou`
    : 'Nenhum ESP enviou medições desde que o servidor iniciou';
}
$('#esp-pill').addEventListener('click', () => {
  if (!state.esp.length) return aviso('ESP32', 'Nenhum ESP enviou medições desde que o servidor foi iniciado.\nConfira o Wi-Fi do ESP e a URL do ngrok no firmware.');
  aviso('Dispositivos ECG', state.esp.map((d) => {
    const idade = (Date.now() - d.visto) / 1000;
    const st = idade <= ESP_ATIVO_S ? 'conectado' : idade <= ESP_AGUARDANDO_S ? 'aguardando' : 'offline';
    return `${d.device_id.toUpperCase()} — ${st}\nIP ${d.ip}${d.via_ngrok ? ' (via ngrok)' : ''}\n` +
      `Última medição há ${tempoDesde(Date.now() - d.visto)}${d.ultimo_erro ? ` (erro: ${d.ultimo_erro})` : ''}\n${d.medicoes} medições desde que o servidor iniciou`;
  }).join('\n\n'));
});
setInterval(renderEsp, 5000);

// ================= Tempo real =================
function connectWS() {
  const ws = new WebSocket(`${location.protocol === 'https:' ? 'wss' : 'ws'}://${location.host}/ws`);
  ws.onopen = () => { $('#conn-dot').classList.add('on'); $('#conn-text').textContent = 'ao vivo'; };
  ws.onclose = () => { $('#conn-dot').classList.remove('on'); $('#conn-text').textContent = 'offline'; setTimeout(connectWS, 2000); };
  ws.onmessage = async (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.type === 'sim') return simStatus(msg);
    if (msg.type === 'paciente') { await loadPaciente(); if (state.pendente) resetLive(); return; }
    if (msg.type !== 'measurement') return;
    loadDispositivos();
    state.pendente = false;
    loadLive(msg.measurement_id, true);
    if (state.admin && activeView() === 'results') {
      if (!$('#results-report').hidden && state.report?.id === msg.session_id) openReport(msg.session_id);
      else if ($('#results-report').hidden) loadSessions();
    }
  };
  setInterval(() => ws.readyState === 1 && ws.send('ping'), 25000);
}

// ================= Início =================
$('#footer-year').textContent = new Date().getFullYear();
(async () => {
  state.token = load('icecg_token');
  await refreshAuth();
  state.info = await api('/api/info');
  if (!state.info.modelo) $('#live-hint').innerHTML += '<br><span class="err">Modelo de classificação não encontrado no servidor.</span>';
  await loadPaciente();
  loadDispositivos();
  if (state.pendente) resetLive();
  else await loadLive(null, false).catch(() => resetLive());
  connectWS();
})();
