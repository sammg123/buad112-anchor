// Anchor phone page. The server owns the session; this renders snapshots from /events,
// reports location, and shows the gate. No user text is ever written as HTML.
const $ = (id) => document.getElementById(id);
const LOCATION_SEND_MS = 5000;
const KEY_STORE = 'anchor-key';

let memoryKey = '';
let rules = null;
let snap = null;
let gateOpen = false;
let gateEndsAt = 0;
let gateTimer = null;
let gateSeconds = 0;
let gatePassed = false;
let lockedOpen = false;
const geo = { fix: null, lastSentAt: 0, error: '' };

/* ---------- key ---------- */

function loadKey() {
  const fromUrl = new URLSearchParams(location.search).get('k');
  if (fromUrl) {
    memoryKey = fromUrl;
    try { localStorage.setItem(KEY_STORE, fromUrl); } catch { /* private mode */ }
    return fromUrl;
  }
  try { return localStorage.getItem(KEY_STORE) || memoryKey; } catch { return memoryKey; }
}
const key = loadKey();

/* ---------- helpers ---------- */

const clock = (ms) => {
  const t = Math.floor(Math.max(0, ms) / 1000);
  const h = Math.floor(t / 3600);
  const m = Math.floor((t % 3600) / 60);
  const s = String(t % 60).padStart(2, '0');
  return h > 0 ? `${h}:${String(m).padStart(2, '0')}:${s}` : `${m}:${s}`;
};
const money = (n) => `$${Math.max(0, Number(n) || 0).toFixed(2)}`;
const setText = (id, text) => { const el = $(id); if (el.textContent !== text) el.textContent = text; };
const show = (id, visible) => { $(id).hidden = !visible; };

async function api(path, body) {
  const opts = { headers: { 'x-anchor-key': key } };
  if (body !== undefined) {
    opts.method = 'POST';
    opts.headers['content-type'] = 'application/json';
    opts.body = JSON.stringify(body);
  }
  let res;
  try {
    res = await fetch(path, opts);
  } catch {
    return { ok: false, status: 0, error: 'Cannot reach Anchor.' };
  }
  let json = {};
  try { json = await res.json(); } catch { /* not json */ }
  return { ok: res.ok && json.success !== false, status: res.status, data: json.data, error: json.error || `Error ${res.status}` };
}

/* ---------- rendering ---------- */

function ladderSteps(s) {
  const l = rules.ladders;
  return (s.deposit ? l.phone : l['phone-nodeposit']).steps;
}

function render(next) {
  snap = next;
  const view = next.status === 'running' ? 'session' : next.status === 'done' ? 'done' : 'setup';
  document.body.dataset.view = view;
  const cover = gateOpen || lockedOpen;
  show('setup', view === 'setup' && !cover);
  show('session', view === 'session' && !cover);
  show('done', view === 'done' && !cover);
  if (view === 'session') renderSession(next);
  if (view === 'done') renderDone(next);
  renderEffects(next);
  if (gateOpen) renderGate();
  if (lockedOpen) renderLocked();
}

function renderSession(s) {
  const steps = ladderSteps(s);
  setText('study-time', clock(s.study.remainingMs));
  setText('phone-time', clock(s.phone.totalMs));
  setText('pickups', s.phone.pickups ? `(${s.phone.pickups} pickup${s.phone.pickups === 1 ? '' : 's'})` : '');
  const list = $('rubric');
  if (list.children.length !== steps.length) {
    list.replaceChildren();
    steps.forEach((step, i) => {
      const li = document.createElement('li');
      const mark = document.createElement('span');
      mark.className = 'rubric__mark';
      const box = document.createElement('span');
      const name = document.createElement('strong');
      name.textContent = `${clock(i * rules.levelMs)}  ${step.name}`;
      const note = document.createElement('small');
      note.textContent = step.note;
      box.append(name, note);
      li.append(mark, box);
      list.append(li);
    });
  }
  [...list.children].forEach((li, i) => {
    const state = s.phone.level === i ? 'current' : s.phone.level > i ? 'reached' : 'todo';
    li.dataset.state = state;
    li.firstChild.textContent = state === 'reached' ? '✓' : state === 'current' ? String(i + 1) : '';
  });
  const loc = s.location;
  const locEl = $('loc');
  locEl.dataset.inside = String(Boolean(loc.inside));
  setText('loc', !loc.hasAnchor ? 'No anchor yet.'
    : loc.inside ? `Inside the zone (${Math.round(loc.distanceM)} m from anchor). Stop is locked.`
    : `${Math.round(loc.distanceM)} m from anchor. Outside the zone.`);
  const stop = $('stop-btn');
  stop.disabled = !s.canStop;
  setText('stop-why', s.canStop ? 'You walked away. You can stop.' : `Stop unlocks past ${loc.unlockAtM ?? rules.unlockAtM ?? 50} m from your anchor.`);
  setText('course-name', s.courseName || 'BUAD 112');
  const dep = s.deposit;
  show('deposit-chip', Boolean(dep));
  if (dep) setText('deposit-left', money(dep.left));
  if (document.activeElement !== $('speed-range')) {
    $('speed-range').value = s.demoSpeed || 1;
    setText('speed-out', `${s.demoSpeed || 1}x`);
  }
}

function renderDone(s) {
  const sum = s.summary;
  if (!sum) return;
  setText('grade', sum.grade);
  setText('score', String(Math.round(sum.focusScore)));
  const rows = [
    ['Studied', clock(sum.studiedMs)],
    ['On your phone', clock(sum.phoneMs)],
    ['Pickups', String(sum.pickups)],
    ['Tuition burned', money(sum.cost)],
    ['Deposit lost', money(sum.depositLost)],
  ];
  const dl = $('filled');
  dl.replaceChildren(...rows.map(([k, v]) => {
    const row = document.createElement('div');
    const dt = document.createElement('dt');
    const dd = document.createElement('dd');
    dt.textContent = k; dd.textContent = v;
    row.append(dt, dd);
    return row;
  }));
}

function renderEffects(s) {
  const fx = s.phoneFx || {};
  const on = s.status === 'running' && Boolean(fx.active);
  document.body.dataset.gray = String(Boolean(on && fx.grayscale));
  $('dim').dataset.on = String(Boolean(on && fx.dim));
  document.documentElement.style.fontSize = on && fx.bigText ? '125%' : '';
}

/* ---------- gate ---------- */

function openGate(fx) {
  gateOpen = true;
  gatePassed = false;
  gateSeconds = fx?.gateSeconds ?? snap?.phoneFx?.gateSeconds ?? 10;
  gateEndsAt = Date.now() + gateSeconds * 1000;
  $('gate-input').value = '';
  setText('gate-error', '');
  show('gate-ok', false);
  show('gate-btn', true);
  clearInterval(gateTimer);
  gateTimer = setInterval(renderGate, 250);
  if (snap) render(snap);
  renderGate();
}

function closeGate() {
  gateOpen = false;
  clearInterval(gateTimer);
  show('gate', false);
  if (location.hash) history.replaceState(null, '', location.pathname + location.search);
  if (snap) render(snap);
}

function renderGate() {
  show('gate', true);
  for (const id of ['setup', 'session', 'done']) show(id, false);
  const s = snap;
  const fx = s?.phoneFx || {};
  const left = Math.max(0, Math.ceil((gateEndsAt - Date.now()) / 1000));
  setText('gate-count', String(left));
  const costIdx = s ? ladderSteps(s).findIndex((x) => x.id === 'cost') : -1;
  const showCost = Boolean(s && costIdx >= 0 && s.phone.level >= costIdx);
  show('gate-cost', showCost);
  if (showCost) setText('gate-cost-amt', money(s.cost));
  const on = [];
  if (fx.grayscale) on.push('grey');
  if (fx.silentOff) on.push('loud');
  if (fx.dim) on.push('dim');
  if (fx.bigText) on.push('huge text');
  if (fx.shame) on.push('shame wallpaper');
  if (fx.flash) on.push('flashlight');
  show('gate-fx', on.length > 0);
  setText('gate-fx', on.length ? `Your phone is now: ${on.join(', ')}. It gets worse.` : '');
  const confess = Boolean(fx.confess);
  show('gate-form', confess && !gatePassed);
  setText('gate-phrase', confess ? `Type: "${s.confession?.phrase || rules.confession}"` : '');
  if (!gatePassed) {
    $('gate-btn').disabled = left > 0 || (confess && !$('gate-input').value.trim());
    setText('gate-line', left > 0 ? 'Wait. Then decide if you really need this app.' : 'Time is up. Do you still want it?');
  }
}

async function passGate() {
  const confess = Boolean(snap?.phoneFx?.confess);
  const res = await api('/api/gate', confess ? { text: $('gate-input').value } : {});
  if (!res.ok) { setText('gate-error', res.status === 409 ? 'Not quite. Type it exactly.' : res.error); return; }
  gatePassed = true;
  setText('gate-error', '');
  show('gate-btn', false);
  show('gate-form', false);
  setText('gate-line', '');
  setText('gate-ok', `Pass granted for ${res.data?.passSeconds ?? snap?.phoneFx?.passSeconds} s. Go back to your app.`);
  show('gate-ok', true);
  if (location.hash) history.replaceState(null, '', location.pathname + location.search);
}

/* ---------- locked ---------- */

function openLocked() {
  lockedOpen = true;
  show('locked', true);
  if (snap) render(snap);
  renderLocked();
}

function closeLocked() {
  lockedOpen = false;
  show('locked', false);
  if (location.hash) history.replaceState(null, '', location.pathname + location.search);
  if (snap) render(snap);
}

function renderLocked() {
  show('locked', true);
  for (const id of ['setup', 'session', 'done', 'gate']) show(id, false);
  const loc = snap?.location;
  const togo = loc && loc.distanceM != null ? Math.max(0, Math.ceil((loc.unlockAtM ?? 50) - loc.distanceM)) : null;
  setText('locked-dist', togo === null ? 'Walk away' : `${togo} m`);
}

const runEnforcer = () => { location.href = 'shortcuts://run-shortcut?name=Anchor%20Enforcer'; };

/* ---------- location ---------- */

function sendFix(force = false) {
  if (!geo.fix) return Promise.resolve({ ok: false });
  const now = Date.now();
  if (!force && now - geo.lastSentAt < LOCATION_SEND_MS) return Promise.resolve({ ok: true });
  geo.lastSentAt = now;
  return api('/api/location', geo.fix);
}

function startLocation() {
  if (!navigator.geolocation) { geo.error = 'This browser has no location.'; return; }
  navigator.geolocation.watchPosition(
    (p) => {
      geo.fix = { lat: p.coords.latitude, lng: p.coords.longitude, accuracy: p.coords.accuracy };
      geo.error = '';
      sendFix();
    },
    (e) => { geo.error = e.code === 1 ? 'Location is blocked. Allow it for this page in Settings, then reload.' : 'Could not get your location.'; },
    { enableHighAccuracy: true, maximumAge: 5000, timeout: 20000 },
  );
}

function freshFix() {
  return new Promise((resolve, reject) => {
    if (!navigator.geolocation) return reject(new Error('This browser has no location.'));
    navigator.geolocation.getCurrentPosition(
      (p) => resolve({ lat: p.coords.latitude, lng: p.coords.longitude, accuracy: p.coords.accuracy }),
      (e) => (e.code !== 1 && geo.fix ? resolve(geo.fix) : reject(new Error(e.code === 1 ? 'Location is blocked. Allow it for this page, then try again.' : 'Could not get your location. Try again outside.'))),
      { enableHighAccuracy: true, maximumAge: 10000, timeout: 8000 },
    );
  });
}

/* ---------- forms ---------- */

const parseMoney = (raw) => {
  const n = Number(String(raw).replace(/[$,\s]/g, ''));
  return raw.trim() === '' ? null : Number.isFinite(n) && n >= 0 ? n : NaN;
};

async function onStart(event) {
  event.preventDefault();
  const form = event.currentTarget;
  const btn = $('start-btn');
  const data = new FormData(form);
  const minutes = Number(data.get('studyMinutes'));
  const tuition = parseMoney(String(data.get('tuitionPerYear')));
  const deposit = parseMoney(String(data.get('deposit')));
  if (!Number.isInteger(minutes) || minutes < 1 || minutes > 240) return setText('start-error', 'Minutes must be 1 to 240.');
  if (Number.isNaN(tuition)) return setText('start-error', 'Tuition must be a number.');
  if (Number.isNaN(deposit) || (deposit ?? 0) > (rules.depositMax ?? 10000)) return setText('start-error', 'Deposit must be a number up to the limit.');
  btn.disabled = true;
  setText('start-error', '');
  try {
    geo.fix = await freshFix();
    const loc = await sendFix(true);
    if (!loc.ok) throw new Error(loc.error);
    const body = { studyMinutes: minutes, mode: 'phone', courseName: String(data.get('courseName')).trim() || 'BUAD 112' };
    if (tuition !== null) body.tuitionPerYear = tuition;
    if (deposit) body.deposit = deposit;
    const res = await api('/api/start', body);
    if (!res.ok) throw new Error(res.error);
    runEnforcer();
  } catch (err) {
    setText('start-error', err.message);
  } finally {
    btn.disabled = false;
  }
}

async function simulateOpen() {
  const res = await api('/api/phone/open', { app: 'Instagram' });
  if (!res.ok) return setText('session-error', res.error);
  setText('session-error', '');
  if (res.data?.gate) { document.querySelector('.presenter').open = false; openGate(res.data); }
}

async function simulateGuard() {
  const res = await api('/api/phone/guard', { app: 'Settings' });
  if (!res.ok) return setText('session-error', res.error);
  setText('session-error', '');
  if (res.data?.locked) { document.querySelector('.presenter').open = false; openLocked(); }
}

function wire() {
  $('guard-btn').addEventListener('click', simulateGuard);
  $('enforcer-btn').addEventListener('click', runEnforcer);
  $('locked-back').addEventListener('click', closeLocked);
  show('a2hs', window.navigator.standalone === false);
  $('start-form').addEventListener('submit', onStart);
  $('stop-btn').addEventListener('click', async () => { const r = await api('/api/stop', {}); if (!r.ok) setText('session-error', r.error); });
  $('again-btn').addEventListener('click', async () => { const r = await api('/api/reset', {}); if (!r.ok) setText('done-error', r.error); });
  $('open-btn').addEventListener('click', simulateOpen);
  $('close-btn').addEventListener('click', async () => { const r = await api('/api/phone/close', { app: 'Instagram' }); setText('session-error', r.ok ? '' : r.error); });
  $('speed-range').addEventListener('input', (e) => setText('speed-out', `${e.target.value}x`));
  $('speed-range').addEventListener('change', (e) => api('/api/demo', { speed: Number(e.target.value) }));
  $('sim-range').addEventListener('input', (e) => setText('sim-out', `${e.target.value} m`));
  $('sim-range').addEventListener('change', (e) => api('/api/demo', { simulatedM: Number(e.target.value) }));
  $('sim-reset').addEventListener('click', () => { $('sim-range').value = 0; setText('sim-out', 'real GPS'); api('/api/demo', { simulatedM: null }); });
  $('gate-btn').addEventListener('click', passGate);
  $('gate-input').addEventListener('input', renderGate);
  $('gate-form').addEventListener('submit', (e) => { e.preventDefault(); if (!$('gate-btn').disabled) passGate(); });
  $('gate-back').addEventListener('click', closeGate);
  window.addEventListener('hashchange', () => { if (location.hash === '#gate' && !gateOpen) openGate(); if (location.hash === '#locked' && !lockedOpen) openLocked(); });
}

function connect() {
  const es = new EventSource(`/events?k=${encodeURIComponent(key)}`);
  es.onopen = () => show('offline', false);
  es.onerror = () => show('offline', true);
  es.onmessage = (e) => { try { render(JSON.parse(e.data)); } catch (err) { setText('session-error', err.message); } };
}

async function init() {
  const res = await api('/api/rules');
  if (!res.ok) {
    document.body.dataset.view = 'setup';
    show('setup', true);
    setText('start-error', res.status === 403 ? 'Wrong or missing key. Scan the QR code on the Mac again.' : 'Anchor is not answering.');
    return;
  }
  rules = res.data;
  wire();
  startLocation();
  connect();
  if (location.hash === '#gate') openGate();
  if (location.hash === '#locked') openLocked();
}

init();
