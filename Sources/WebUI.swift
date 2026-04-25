// Embedded web application — vanilla HTML/CSS/JS, no frameworks.

enum WebUI {
    static let html = ##"""
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>MLX Launcher</title>
<style>
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
:root{
  --bg:#09090b;--surface:#18181b;--border:#27272a;--border-subtle:#1f1f23;
  --text:#fafafa;--text-2:#a1a1aa;--text-3:#71717a;
  --accent:#2dd4bf;--accent-dim:#0d9488;--accent-bg:rgba(45,212,191,0.08);
  --red:#f87171;--orange:#fb923c;--green:#4ade80;--blue:#60a5fa;
  --mono:"SF Mono","JetBrains Mono","Fira Code",monospace;
  --sans:system-ui,-apple-system,sans-serif;
  --radius:6px;
}
html{font-family:var(--sans);background:var(--bg);color:var(--text);font-size:14px;line-height:1.5}
body{min-height:100vh;display:flex;flex-direction:column}
a{color:var(--accent);text-decoration:none}
a:hover{text-decoration:underline}
button{font-family:var(--sans);cursor:pointer;border:1px solid var(--border);background:var(--surface);color:var(--text);padding:6px 14px;border-radius:var(--radius);font-size:13px;transition:all .15s}
button:hover{border-color:var(--accent-dim);background:var(--accent-bg)}
button.primary{background:var(--accent-dim);border-color:var(--accent-dim);color:#fff;font-weight:600}
button.primary:hover{background:var(--accent)}
button.danger{border-color:#7f1d1d;color:var(--red)}
button.danger:hover{background:rgba(248,113,113,0.1)}
button:disabled{opacity:.4;cursor:default}
input,select,textarea{font-family:var(--mono);background:var(--bg);border:1px solid var(--border);color:var(--text);padding:6px 10px;border-radius:var(--radius);font-size:13px;outline:none}
input:focus,select:focus,textarea:focus{border-color:var(--accent-dim)}
textarea{resize:vertical;min-height:60px}

/* Layout */
.header{display:flex;align-items:center;gap:12px;padding:12px 20px;border-bottom:1px solid var(--border);background:var(--surface)}
.header h1{font-size:16px;font-weight:700;letter-spacing:-.02em}
.header .kitty{font-size:22px}
.header .status{margin-left:auto;display:flex;align-items:center;gap:8px;font-size:12px;color:var(--text-2)}
.header .dot{width:8px;height:8px;border-radius:50%;background:var(--text-3)}
.header .dot.on{background:var(--green)}
.header .dot.starting{background:var(--orange)}
.header .dot.error{background:var(--red)}

.main{flex:1;display:grid;grid-template-columns:1fr 1fr;grid-template-rows:auto 1fr;gap:0}
.panel{border-right:1px solid var(--border);border-bottom:1px solid var(--border);display:flex;flex-direction:column}
.panel-head{padding:10px 16px;border-bottom:1px solid var(--border-subtle);display:flex;align-items:center;gap:8px;font-size:12px;font-weight:600;color:var(--text-2);text-transform:uppercase;letter-spacing:.05em}
.panel-body{flex:1;overflow-y:auto;padding:0}

/* Model list */
.model-item{display:flex;align-items:center;gap:10px;padding:8px 16px;cursor:pointer;border-bottom:1px solid var(--border-subtle);transition:background .1s}
.model-item:hover{background:var(--accent-bg)}
.model-item.selected{background:var(--accent-bg);border-left:2px solid var(--accent)}
.model-item .name{font-family:var(--mono);font-size:13px;flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.badge{font-family:var(--mono);font-size:10px;padding:2px 6px;border-radius:3px;font-weight:600;text-transform:uppercase}
.badge.mlx{background:rgba(45,212,191,0.15);color:var(--accent)}
.badge.anthropic{background:rgba(251,146,60,0.15);color:var(--orange)}
.badge.openai{background:rgba(74,222,128,0.15);color:var(--green)}
.badge.google{background:rgba(96,165,250,0.15);color:var(--blue)}
.size{font-family:var(--mono);font-size:11px;color:var(--text-3);min-width:40px;text-align:right}

/* Runner grid */
.runner-grid{display:grid;grid-template-columns:repeat(5,1fr);gap:6px;padding:12px 16px}
.runner-btn{display:flex;flex-direction:column;align-items:center;gap:4px;padding:10px 4px;border-radius:var(--radius);border:1px solid var(--border);background:transparent;font-size:11px;color:var(--text-2);transition:all .15s}
.runner-btn:hover{border-color:var(--accent-dim);color:var(--text)}
.runner-btn.active{border-color:var(--accent);background:var(--accent-bg);color:var(--accent)}
.runner-btn.disabled{opacity:.3;cursor:default}
.runner-btn .icon{font-size:18px}

/* Server controls */
.server-bar{display:flex;gap:8px;padding:12px 16px;border-bottom:1px solid var(--border);align-items:center}
.server-bar .info{flex:1;font-family:var(--mono);font-size:12px;color:var(--text-2)}

/* Combos grid */
.combo-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:8px;padding:16px}
.combo-card{border:1px solid var(--border);border-radius:var(--radius);padding:12px;cursor:pointer;transition:all .15s}
.combo-card:hover{border-color:var(--accent-dim);background:var(--accent-bg)}
.combo-card .runner-name{font-size:11px;color:var(--text-3);text-transform:uppercase;letter-spacing:.05em;margin-bottom:4px}
.combo-card .model-name{font-family:var(--mono);font-size:13px;margin-bottom:6px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.combo-card .meta{display:flex;gap:6px;align-items:center}

.search{padding:12px 16px;border-bottom:1px solid var(--border-subtle)}
.search input{width:100%}

/* Footer */
.footer{padding:8px 20px;border-top:1px solid var(--border);font-size:11px;color:var(--text-3);display:flex;align-items:center;gap:16px}
</style>
</head>
<body>

<div class="header">
  <span class="kitty">🐱</span>
  <h1>MLX Launcher</h1>
  <div class="status">
    <span class="dot" id="status-dot"></span>
    <span id="status-text">Checking...</span>
  </div>
</div>

<div class="main">
  <!-- Top left: Models -->
  <div class="panel">
    <div class="panel-head">
      <span>Models</span>
      <span style="margin-left:auto;font-weight:400" id="model-count"></span>
    </div>
    <div class="search"><input type="text" id="model-search" placeholder="Filter models..."></div>
    <div class="panel-body" id="model-list"></div>
  </div>

  <!-- Top right: Runner + Server -->
  <div class="panel">
    <div class="panel-head">Runner</div>
    <div class="runner-grid" id="runner-grid"></div>

    <div class="panel-head" style="border-top:1px solid var(--border)">Server</div>
    <div class="server-bar">
      <span class="info" id="server-info">--</span>
      <button onclick="startServer()" id="btn-start">Start</button>
      <button onclick="stopServer()" id="btn-stop" class="danger">Stop</button>
      <button onclick="restartServer()">Restart</button>
    </div>

    <div class="panel-head" style="border-top:1px solid var(--border)">Quick Launch</div>
    <div style="padding:12px 16px;display:flex;gap:8px">
      <button class="primary" onclick="launchSelected()" id="btn-launch" style="flex:1" disabled>Launch Selected</button>
    </div>
  </div>

  <!-- Bottom: All runner+model combos -->
  <div class="panel" style="grid-column:1/-1">
    <div class="panel-head">
      <span>All Combinations</span>
      <span style="margin-left:auto;font-weight:400" id="combo-count"></span>
    </div>
    <div class="search"><input type="text" id="combo-search" placeholder="Filter combos..."></div>
    <div class="panel-body">
      <div class="combo-grid" id="combo-grid"></div>
    </div>
  </div>
</div>

<div class="footer">
  <span>MLX Launcher &middot; REST API on this port</span>
  <a href="/api/models">GET /api/models</a>
  <a href="/api/runners">GET /api/runners</a>
  <a href="/api/server">GET /api/server</a>
  <a href="/api/profiles">GET /api/profiles</a>
  <a href="/api/prompts">GET /api/prompts</a>
</div>

<script>
const API = '';
let models = [], runners = [], selectedModel = null, selectedRunner = null;

const icons = {claude:'🧠',codex:'⌨️',gemini:'✨',aider:'🔧',gptme:'💬'};
const badgeClass = {local:'mlx',anthropic:'anthropic',openai:'openai',google:'google'};

async function fetchJSON(url, opts) {
  const r = await fetch(API + url, opts);
  return r.json();
}

async function init() {
  [models, runners] = await Promise.all([fetchJSON('/api/models'), fetchJSON('/api/runners')]);
  renderModels();
  renderRunners();
  renderCombos();
  pollServer();
  setTimeout(refreshModels, 1000);
  setInterval(refreshModels, 5000);
  setInterval(pollServer, 5000);
}

async function refreshModels() {
  try {
    const previous = selectedModel?.launchIdentity || selectedModel?.id;
    models = await fetchJSON('/api/models');
    selectedModel = previous ? models.find(m => (m.launchIdentity || m.id) === previous) || null : selectedModel;
    renderModels(document.getElementById('model-search').value);
    renderCombos(document.getElementById('combo-search').value);
    document.getElementById('btn-launch').disabled = !selectedModel || !selectedRunner;
  } catch(e) {}
}

function renderModels(filter = '') {
  const el = document.getElementById('model-list');
  const f = filter.toLowerCase();
  const filtered = models.filter(m => !f || m.id.toLowerCase().includes(f) || m.shortName.toLowerCase().includes(f));
  document.getElementById('model-count').textContent = filtered.length + ' models';
  el.innerHTML = filtered.map(m => `
    <div class="model-item ${(selectedModel?.launchIdentity || selectedModel?.id) === (m.launchIdentity || m.id) ? 'selected' : ''}" onclick="selectModel('${m.launchIdentity || m.id}')">
      <span class="name" title="${m.id}">${m.shortName}</span>
      <span class="badge ${badgeClass[m.source]}">${m.provider}</span>
      <span class="size">${m.size}</span>
    </div>
  `).join('');
}

function renderRunners() {
  const el = document.getElementById('runner-grid');
  el.innerHTML = runners.map(r => `
    <div class="runner-btn ${selectedRunner?.id === r.id ? 'active' : ''} ${r.installed ? '' : 'disabled'}"
         onclick="${r.installed ? `selectRunner('${r.id}')` : ''}">
      <span class="icon">${icons[r.id] || '🤖'}</span>
      <span>${r.name}</span>
    </div>
  `).join('');
}

function renderCombos(filter = '') {
  const el = document.getElementById('combo-grid');
  const f = filter.toLowerCase();
  const installed = runners.filter(r => r.installed);
  let combos = [];
  for (const r of installed) {
    for (const m of models) {
      const label = `${r.name} + ${m.shortName}`;
      if (f && !label.toLowerCase().includes(f)) continue;
      combos.push({r, m, label});
    }
  }
  document.getElementById('combo-count').textContent = combos.length + ' combinations';
  el.innerHTML = combos.map(c => `
    <div class="combo-card" onclick="launchCombo('${c.r.id}','${c.m.launchIdentity || c.m.id}')">
      <div class="runner-name">${icons[c.r.id] || ''} ${c.r.name}</div>
      <div class="model-name">${c.m.shortName}</div>
      <div class="meta">
        <span class="badge ${badgeClass[c.m.source]}">${c.m.provider}</span>
        <span class="size">${c.m.size}</span>
      </div>
    </div>
  `).join('');
}

function selectModel(id) {
  selectedModel = models.find(m => (m.launchIdentity || m.id) === id || m.id === id);
  renderModels(document.getElementById('model-search').value);
  document.getElementById('btn-launch').disabled = !selectedModel || !selectedRunner;
}

function selectRunner(id) {
  selectedRunner = runners.find(r => r.id === id);
  renderRunners();
  document.getElementById('btn-launch').disabled = !selectedModel || !selectedRunner;
}

async function pollServer() {
  try {
    const s = await fetchJSON('/api/server');
    const dot = document.getElementById('status-dot');
    const txt = document.getElementById('status-text');
    dot.className = 'dot ' + (s.state === 'running' ? 'on' : s.state === 'starting' ? 'starting' : s.state === 'error' ? 'error' : '');
    txt.textContent = s.state === 'running' ? `Running: ${s.model}` : s.state === 'starting' ? 'Starting...' : 'Idle';
    document.getElementById('server-info').textContent = s.state === 'running' ? `${s.model} on :${s.port} (PID ${s.pid})` : 'No server running';
    document.getElementById('btn-start').disabled = s.state === 'running';
    document.getElementById('btn-stop').disabled = s.state !== 'running';
  } catch(e) {}
}

async function startServer() {
  if (!selectedModel || selectedModel.source !== 'local') return alert('Select a local MLX model first');
  await fetchJSON('/api/server/start', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({model:selectedModel.id})});
  setTimeout(pollServer, 1000);
}
async function stopServer() {
  await fetchJSON('/api/server/stop', {method:'POST'});
  setTimeout(pollServer, 1000);
}
async function restartServer() {
  await fetchJSON('/api/server/restart', {method:'POST'});
  setTimeout(pollServer, 2000);
}
async function launchSelected() {
  if (!selectedModel || !selectedRunner) return;
  await fetchJSON('/api/launch', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({model:selectedModel.launchIdentity || selectedModel.id, runner:selectedRunner.id})});
}
async function launchCombo(runnerId, modelId) {
  await fetchJSON('/api/launch', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({model:modelId, runner:runnerId})});
}

document.getElementById('model-search').addEventListener('input', e => renderModels(e.target.value));
document.getElementById('combo-search').addEventListener('input', e => renderCombos(e.target.value));
init();
</script>
</body>
</html>
"""##
}
