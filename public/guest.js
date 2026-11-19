// Anchor guest page: a read-only live card polled from /api/guest, plus a purely client-side
// sandbox of the phone ladder. The sandbox sends nothing to the server.
const $ = (id) => document.getElementById(id);
const KEY_STORE = 'anchor-guest-key';
const POLL_MS = 3000;
const SPEED = 5;
const TICK_MS = 250;
const STEP_MS = 15000; // sandbox phone time per step; real time is this / SPEED
const TUITION = 70000;
const CLASS_MIN = 27000;
const DEPOSIT = 20;

let memoryKey = '';
let rules = null;

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

const clock = (ms) => {
  const t = Math.floor(Math.max(0, ms) / 1000);
  return `${Math.floor(t / 60)}:${String(t % 60).padStart(2, '0')}`;
};
const money = (n) => `$${Math.max(0, Number(n) || 0).toFixed(2)}`;
const setText = (id, text) => { const el = $(id); if (el.textContent !== text) el.textContent = text; };
const show = (id, on) => { $(id).hidden = !on; };

async function getJson(path) {
  const res = await fetch(path, { headers: { 'x-anchor-key': key } });
  const json = await res.json().catch(() => ({}));
  if (!res.ok || json.success === false) throw new Error(res.status === 403 ? 'Wrong key. Scan the QR again.' : json.error || `Error ${res.status}`);
  return json.data;
}

function buildRubric(list, steps) {
  list.replaceChildren();
  steps.forEach((step, i) => {
    const li = document.createElement('li');
    const mark = document.createElement('span');
    mark.className = 'rubric__mark';
    const box = document.createElement('span');
    const name = document.createElement('strong');
    name.textContent = `${clock(i * STEP_MS)}  ${step.name}`;
    const note = document.createElement('small');
    note.textContent = step.note;
    box.append(name, note);
    li.append(mark, box);
    list.append(li);
  });
}

function markRubric(list, level) {
  [...list.children].forEach((li, i) => {
    const state = level === i ? 'current' : level > i ? 'reached' : 'todo';
    li.dataset.state = state;
    li.firstChild.textContent = state === 'reached' ? '✓' : state === 'current' ? String(i + 1) : '';
  });
}

/* ---------- live card ---------- */

function renderLive(g) {
  const running = g.status === 'running';
  show('live-wait', g.status === 'idle');
  show('live-body', running);
  show('live-grade', g.status === 'done');
  if (g.status === 'done') setText('live-grade-mark', g.grade || '');
  if (!running) return;
  setText('live-course', g.courseName || 'BUAD 112');
  setText('live-time', clock(g.study.remainingMs));
  setText('live-phone', clock(g.phone.totalMs));
  const ladderKey = `phone${g.quiet ? '-quiet' : ''}${g.deposit ? '' : '-nodeposit'}`;
  if ($('live-rubric').dataset.ladder !== ladderKey && rules.ladders[ladderKey]) {
    buildRubric($('live-rubric'), rules.ladders[ladderKey].steps);
    $('live-rubric').dataset.ladder = ladderKey;
  }
  setText('live-step', g.phone.levelName);
  setText('live-cost', money(g.cost));
  setText('live-dep', g.deposit ? `Deposit left ${money(g.deposit.left)}` : '');
  markRubric($('live-rubric'), g.phone.level);
}

async function poll() {
  if (document.hidden) return;
  try {
    renderLive(await getJson('/api/guest'));
    setText('live-error', '');
  } catch (err) {
    setText('live-error', err.message);
  }
}

/* ---------- sandbox ---------- */

const sb = { mode: 'off', phoneMs: 0, level: 0, gateEnd: 0, confessed: false, flashed: -1, depositLost: 0, lastBiteLevel: -1, timer: null };
const reduceMotion = () => window.matchMedia('(prefers-reduced-motion: reduce)').matches;
const stepIndex = (id) => rules.ladders.phone.steps.findIndex((s) => s.id === id);
const reached = (id) => sb.level >= stepIndex(id);
const sbCost = () => (sb.phoneMs / 60000) * (TUITION / CLASS_MIN);

function applyEffects() {
  const on = sb.mode !== 'off';
  grayLayer().dataset.on = String(Boolean(on && reached('gray')));
  document.documentElement.style.fontSize = on && reached('text') ? '175%' : '';
  $('sb-dim').dataset.on = String(on && reached('dim'));
}

function speak() {
  try {
    if ('speechSynthesis' in window) speechSynthesis.speak(new SpeechSynthesisUtterance('Put the phone down.'));
  } catch { /* no speech */ }
}

function doFlash() {
  if (reduceMotion()) return;
  const el = $('sb-flash');
  let n = 0;
  const step = () => {
    el.dataset.on = String(n % 2 === 0);
    n += 1;
    if (n <= 6) setTimeout(step, 500); // on 0.5 s, off 0.5 s: at most one flash per second
    else el.dataset.on = 'false';
  };
  step();
}

function enterEffects() {
  if (reached('loud')) speak();
  if (reached('flash')) doFlash();
}

function levelUp() {
  const next = Math.min(Math.floor(sb.phoneMs / STEP_MS), rules.ladders.phone.steps.length - 1);
  if (next === sb.level) return;
  sb.level = next;
  applyEffects();
  if (reached('flash') && sb.flashed < 0) { sb.flashed = sb.level; doFlash(); }
  if (reached('deposit') && sb.level > sb.lastBiteLevel) sb.lastBiteLevel = sb.level;
}

function tick() {
  if (sb.mode === 'feed') {
    sb.phoneMs += TICK_MS * SPEED;
    levelUp();
    if (reached('deposit')) {
      // Bites of $1, $2, $4... every 3 real seconds of phone time past the deposit step.
      const sinceMs = sb.phoneMs - stepIndex('deposit') * STEP_MS;
      const bites = Math.floor(sinceMs / STEP_MS);
      let lost = 0;
      for (let i = 0; i < bites; i += 1) lost += 2 ** i;
      sb.depositLost = Math.min(DEPOSIT, lost);
    }
    renderHud();
  } else if (sb.mode === 'gate') {
    renderGate();
  }
}

function renderHud() {
  const parts = [];
  if (reached('cost')) parts.push(`${money(sbCost())} burned`);
  if (reached('deposit')) parts.push(`$${DEPOSIT - sb.depositLost} of $${DEPOSIT} deposit`);
  setText('sb-hud', parts.join('  '));
}

function gateSecondsNow() {
  const secs = rules.gateSeconds ?? [10];
  return Math.max(1, Math.ceil(secs[Math.min(sb.level, secs.length - 1)] / SPEED));
}

function needsConfession() { return reached('confess') && !sb.confessed; }

function openGate() {
  sb.mode = 'gate';
  sb.gateEnd = Date.now() + gateSecondsNow() * 1000;
  $('sb-input').value = '';
  show('sb-gate', true);
  show('sb-feed', false);
  show('page', false);
  applyEffects();
  renderGate();
}

function renderGate() {
  const left = Math.max(0, Math.ceil((sb.gateEnd - Date.now()) / 1000));
  setText('sb-count', String(left));
  show('sb-gate-cost', reached('cost'));
  setText('sb-gate-amt', money(sbCost()));
  const on = [];
  if (reached('gray')) on.push('grey');
  if (reached('loud')) on.push('loud');
  if (reached('dim')) on.push('dim');
  if (reached('text')) on.push('huge text');
  if (reached('flash')) on.push('flashing');
  show('sb-fx', on.length > 0);
  setText('sb-fx', on.length ? `Your phone is now: ${on.join(', ')}. It gets worse.` : '');
  const confess = needsConfession();
  show('sb-form', confess);
  setText('sb-phrase', confess ? `Type: "${rules.confession}"` : '');
  const typed = $('sb-input').value.trim().toLowerCase() === String(rules.confession).trim().toLowerCase();
  $('sb-continue').disabled = left > 0 || (confess && !typed);
}

function goFeed() {
  if (needsConfession()) sb.confessed = true;
  sb.mode = 'feed';
  show('sb-gate', false);
  show('sb-feed', true);
  enterEffects();
  renderHud();
}

function closeInstagram() {
  sb.mode = 'closed';
  show('sb-feed', false);
  show('page', true);
  show('try-idle', false);
  show('try-closed', true);
  setText('try-status', `Phone time ${clock(sb.phoneMs)}. Effects stay on. Reopening bounces you to the gate.`);
  applyEffects();
}

function walkAway() {
  const ms = sb.phoneMs;
  sb.mode = 'off';
  applyEffects();
  for (const id of ['sb-gate', 'sb-feed']) show(id, false);
  show('page', true);
  show('try-idle', false);
  show('try-closed', false);
  show('try-done', true);
  const s = ms / 1000;
  setText('try-grade', s < 15 ? 'A' : s < 45 ? 'B' : s < 90 ? 'C' : s < 135 ? 'D' : 'F');
  setText('try-summary', `Phone time ${clock(ms)}, tuition burned ${money(sbCost())}${sb.depositLost ? `, deposit lost $${sb.depositLost}` : ''}. You walked away; everything lifted.`);
}

function resetSandbox() {
  Object.assign(sb, { mode: 'off', phoneMs: 0, level: 0, confessed: false, flashed: -1, depositLost: 0, lastBiteLevel: -1 });
  applyEffects();
  for (const id of ['sb-gate', 'sb-feed', 'try-closed', 'try-done']) show(id, false);
  $('sb-flash').dataset.on = 'false';
  show('page', true);
  show('try-idle', true);
}

function wire() {
  $('try-start').addEventListener('click', () => { resetSandbox(); openGate(); });
  $('try-reopen').addEventListener('click', openGate);
  $('try-walk').addEventListener('click', walkAway);
  $('sb-gate-walk').addEventListener('click', walkAway);
  $('sb-feed-walk').addEventListener('click', walkAway);
  $('sb-close').addEventListener('click', closeInstagram);
  $('sb-continue').addEventListener('click', goFeed);
  $('sb-input').addEventListener('input', renderGate);
  $('sb-form').addEventListener('submit', (e) => { e.preventDefault(); if (!$('sb-continue').disabled) goFeed(); });
  $('try-again').addEventListener('click', resetSandbox);
  $('try-reset').addEventListener('click', resetSandbox);
  document.addEventListener('visibilitychange', () => { if (!document.hidden) poll(); });
}

async function init() {
  try {
    rules = await getJson('/api/rules');
  } catch (err) {
    setText('live-error', err.message);
    return;
  }
  buildRubric($('live-rubric'), rules.ladders.phone.steps);
  wire();
  sb.timer = setInterval(tick, TICK_MS);
  poll();
  setInterval(poll, POLL_MS);
}

init();

/** The see-through grey layer (styles in phone.css); iOS Safari won't grey the page background with a filter. */
function grayLayer() {
  let el = document.getElementById('gray');
  if (!el) {
    el = document.createElement('div');
    el.id = 'gray';
    el.className = 'gray';
    el.setAttribute('aria-hidden', 'true');
    document.body.append(el);
  }
  return el;
}
