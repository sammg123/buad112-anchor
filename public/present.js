// Anchor presenter screen (projector). On the Mac at localhost no key is needed; anywhere else
// (a classroom computer through the tunnel) open it with ?k=<owner key>.
const $ = (id) => document.getElementById(id);
const setText = (id, t) => { const el = $(id); if (el.textContent !== t) el.textContent = t; };
const show = (id, on) => { $(id).hidden = !on; };

let rules = null;
let snap = null;
let guestSvg = '';
let guestUrl = '';

const clock = (ms) => {
  const t = Math.floor(Math.max(0, ms) / 1000);
  const h = Math.floor(t / 3600);
  const m = Math.floor((t % 3600) / 60);
  const s = String(t % 60).padStart(2, '0');
  return h > 0 ? `${h}:${String(m).padStart(2, '0')}:${s}` : `${m}:${s}`;
};
const money = (n) => `$${Math.max(0, Number(n) || 0).toFixed(2)}`;

const KEY = new URLSearchParams(location.search).get('k') || '';
const keyed = (path) => (KEY ? `${path}${path.includes('?') ? '&' : '?'}k=${encodeURIComponent(KEY)}` : path);
const get = (path) => fetch(keyed(path));

async function post(path, body) {
  try {
    await fetch(keyed(path), { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
  } catch { /* server restarting */ }
}

function steps(s) {
  return rules.ladders[`phone${s.quiet ? '-quiet' : ''}${s.deposit ? '' : '-nodeposit'}`].steps;
}

function render(s) {
  snap = s;
  const view = s.status === 'running' ? 'running' : s.status === 'done' ? 'done' : 'idle';
  document.body.dataset.view = view;
  show('idle', view === 'idle');
  show('running', view === 'running');
  show('done', view === 'done');
  if (view === 'running') renderRunning(s);
  if (view === 'done') renderDone(s);
  // The simulated distance has to reach past whatever zone size this session picked.
  if (s.location?.radiusM) $('sim').max = Math.max(200, s.location.radiusM + 50);
  if (document.activeElement !== $('speed')) {
    $('speed').value = s.demoSpeed || 1;
    setText('speed-out', `${s.demoSpeed || 1}x`);
  }
}

function renderRunning(s) {
  const list = steps(s);
  setText('course', s.courseName || s.config?.courseName || 'BUAD 112');
  setText('time', clock(s.study.remainingMs));
  setText('phone-time', clock(s.phone.totalMs));
  const cur = list[Math.min(s.phone.level, list.length - 1)];
  setText('step-name', cur.name);
  setText('step-note', cur.note);
  const ol = $('rubric');
  if (ol.children.length !== list.length) {
    ol.replaceChildren(...list.map((step, i) => {
      const li = document.createElement('li');
      const mark = document.createElement('span');
      mark.className = 'rubric__mark';
      const name = document.createElement('span');
      name.textContent = `${clock(i * rules.levelMs)}  ${step.name}`;
      li.append(mark, name);
      return li;
    }));
  }
  [...ol.children].forEach((li, i) => {
    const st = s.phone.level === i ? 'current' : s.phone.level > i ? 'reached' : 'todo';
    li.dataset.state = st;
    li.firstChild.textContent = st === 'reached' ? '✓' : st === 'current' ? '○' : '';
  });
  setText('cost', money(s.cost));
  show('dep-tile', Boolean(s.deposit));
  if (s.deposit) setText('dep', money(s.deposit.left));
  setText('pickups', String(s.phone.pickups));
  renderChips(s);
}

function renderChips(s) {
  const fx = s.phoneFx || {};
  const chips = [];
  if (s.away) chips.push(['Outside the zone: phone is free', true]);
  else if (fx.active) {
    if (fx.grayscale) chips.push(['GREY']);
    if (fx.silentOff) chips.push(['LOUD']);
    if (fx.dim) chips.push(['DIM']);
    if (fx.bigText) chips.push(['HUGE TEXT']);
    if (fx.flash) chips.push(['FLASHING']);
    if (fx.confess) chips.push(['CONFESSION OWED']);
  }
  const ul = $('chips');
  const sig = chips.map((c) => c[0]).join('|');
  if (ul.dataset.sig === sig) return;
  ul.dataset.sig = sig;
  ul.replaceChildren(...chips.map(([t, free]) => {
    const li = document.createElement('li');
    li.className = free ? 'chip chip--free' : 'chip';
    li.textContent = t;
    return li;
  }));
}

function renderDone(s) {
  const m = s.summary;
  if (!m) return;
  setText('grade', m.grade);
  setText('score', String(Math.round(m.focusScore)));
  const rows = [['Phone time', clock(m.phoneMs), true], ['Pickups', String(m.pickups), true], ['Tuition burned', money(m.cost), true], ['Deposit lost', money(m.depositLost), true], ['Studied', clock(m.studiedMs)]];
  $('filled').replaceChildren(...rows.map(([k, v, pen]) => {
    const row = document.createElement('div');
    if (pen) row.className = 'pen';
    const dt = document.createElement('dt'); dt.textContent = k;
    const dd = document.createElement('dd'); dd.textContent = v;
    row.append(dt, dd);
    return row;
  }));
}

/* ---------- pairing ---------- */

async function loadPairing() {
  try {
    const data = (await (await get('/api/connect')).json()).data;
    setText('qr-err', data?.error || '');
    if (data?.guestUrl) {
      guestSvg = data.guestQrSvg;
      guestUrl = data.guestUrl;
      $('qr').innerHTML = guestSvg; // trusted server output
      setText('guest-url', guestUrl);
      $('owner-qr').innerHTML = data.qrSvg || '';
      setText('owner-base', data.base || '');
      setText('owner-key', data.token || '');
      return;
    }
  } catch { /* retry */ }
  setTimeout(loadPairing, 3000);
}

/* ---------- controls ---------- */

function toggleOverlay(on = $('overlay').hidden) {
  if (on && !guestSvg) return;
  if (on) { $('overlay-qr').innerHTML = guestSvg; setText('overlay-url', guestUrl); }
  show('overlay', on);
}

function toggleDrawer() {
  const open = $('drawer-body').hidden;
  show('drawer-body', open);
  $('drawer-toggle').setAttribute('aria-expanded', String(open));
}

function wire() {
  $('qr').addEventListener('click', () => toggleOverlay());
  $('overlay').addEventListener('click', () => toggleOverlay(false));
  $('drawer-toggle').addEventListener('click', toggleDrawer);
  $('speed').addEventListener('input', (e) => setText('speed-out', `${e.target.value}x`));
  $('speed').addEventListener('change', (e) => post('/api/demo', { speed: Number(e.target.value) }));
  $('sim').addEventListener('input', (e) => setText('sim-out', `${e.target.value} m`));
  $('sim').addEventListener('change', (e) => post('/api/demo', { simulatedM: Number(e.target.value) }));
  $('sim-real').addEventListener('click', () => { $('sim').value = 0; setText('sim-out', 'real GPS'); post('/api/demo', { simulatedM: null }); });
  $('owner-btn').addEventListener('click', () => {
    const open = $('owner').hidden;
    show('owner', open);
    $('owner-btn').setAttribute('aria-expanded', String(open));
    setText('owner-btn', open ? 'Hide my phone\'s QR' : 'Show my phone\'s QR (private)');
  });
  document.addEventListener('keydown', (e) => {
    if (e.target instanceof HTMLInputElement && e.target.type !== 'range') return;
    if (e.key === 'q' || e.key === 'Q') toggleOverlay();
    else if (e.key === 'p' || e.key === 'P') toggleDrawer();
    else if (e.key === 'Escape') toggleOverlay(false);
  });
}

async function init() {
  try {
    rules = (await (await get('/api/rules')).json()).data;
  } catch {
    setText('qr-err', 'Anchor is not answering. Is npm start running?');
    return;
  }
  wire();
  loadPairing();
  const es = new EventSource(keyed('/events'));
  es.onmessage = (e) => { try { render(JSON.parse(e.data)); } catch { /* bad frame */ } };
}

init();
