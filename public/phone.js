// Anchor phone page. The server owns the session; this renders snapshots from /events,
// reports location, and shows the gate. No user text is ever written as HTML.
const $ = (id) => document.getElementById(id);
/** The distance on screen is redrawn from live GPS this often; the server hears a fix every LOCATION_SEND_MS. */
const LIVE_MS = 500;
const LOCATION_SEND_MS = 2000;
/** A GPS fix older than this shows the live dot as stale. */
const STALE_FIX_MS = 5000;
const DROP_MS = 2300;
/** Live position: GPS readings from this long ago are blended, so the dot doesn't jump around. */
const SMOOTH_MS = 3000;
/** Dropping the anchor listens to GPS for up to this long, and stops early once a reading is this good. */
const ANCHOR_SAMPLE_MS = 6000;
const ANCHOR_GOOD_M = 10;
const ANCHOR_MIN_MS = 1500;
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
const geo = { fix: null, at: 0, samples: [], lastSentAt: 0, error: '' };

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
  return rules.ladders[`phone${s.quiet ? '-quiet' : ''}${s.deposit ? '' : '-nodeposit'}`].steps;
}

function render(next) {
  snap = next;
  const view = next.status === 'running' ? 'session' : next.status === 'done' ? 'done' : 'setup';
  document.body.dataset.view = view;
  const cover = gateOpen || lockedOpen;
  show('setup', view === 'setup' && !cover);
  show('session', view === 'session' && !cover);
  show('done', view === 'done' && !cover);
  if (view === 'setup') renderSpot();
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
  renderLive();
  const loc = s.location;
  $('stop-btn').dataset.locked = String(!s.canStop);
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

/** Meters between two fixes (haversine), the same math the server uses. */
function metersBetween(a, b) {
  const rad = Math.PI / 180;
  const h = Math.sin(((b.lat - a.lat) * rad) / 2) ** 2
    + Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * Math.sin(((b.lng - a.lng) * rad) / 2) ** 2;
  return 2 * 6_371_008.8 * Math.asin(Math.min(1, Math.sqrt(h)));
}

/** "You are N m away from your anchor": from this phone's own GPS when it can, else what the server last said. */
function renderLive() {
  if (snap?.status !== 'running') return;
  const loc = snap.location;
  const own = loc.anchor && geo.fix && !loc.simulated;
  const distance = own ? metersBetween(loc.anchor, geo.fix) : loc.distanceM;
  const unlockAt = Math.round(loc.unlockAtM ?? loc.radiusM ?? 50);
  const card = $('anchor-card');
  if (distance == null) {
    card.dataset.inside = 'true';
    setText('anchor-dist', '–');
    setText('anchor-note', geo.error || 'Finding you...');
    $('anchor-bar').style.width = '0';
  } else {
    const meters = Math.round(distance);
    const inside = meters <= unlockAt;
    card.dataset.inside = String(inside);
    setText('anchor-dist', String(meters));
    setText('anchor-note', inside ? `Stop unlocks at ${unlockAt} m: ${unlockAt - meters} m to go.` : 'Outside the zone. You can stop.');
    setText('cant-body', inside ? `You're inside the no-phone zone. Walk ${unlockAt - meters} m more to leave it, then you can stop.` : 'You just left the zone. Tap Stop again.');
    $('anchor-bar').style.width = `${Math.min(100, (meters / unlockAt) * 100)}%`;
  }
  const inside = card.dataset.inside === 'true';
  $('zone-status').dataset.inside = String(inside);
  setText('zone-status-title', inside ? 'No-phone zone' : 'Outside the zone');
  setText('zone-status-sub', inside ? 'Phone use here is penalized. Stop is locked.' : 'Your phone is free here. You can stop.');
  renderMap(loc, own);
  const stale = !loc.simulated && (!geo.fix || Date.now() - geo.at > STALE_FIX_MS);
  $('anchor-live').parentElement.dataset.stale = String(stale);
  setText('anchor-live', loc.simulated ? 'Simulated distance (presenter)'
    : geo.fix ? `Live GPS, accurate to ${Math.round(geo.fix.accuracy)} m${stale ? ' (waiting for a new fix)' : ''}` : 'Waiting for GPS');
}

/* ---------- zone map ---------- */

const ZONE_COLOR = '#d7262e';
const INK = '#14284b';
const YOU_COLOR = '#2a7de1';
const ANCHOR_SVG = '<svg viewBox="0 0 64 64" fill="none" stroke="currentColor" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"><circle cx="32" cy="10" r="5"/><path d="M32 15v42M21 25h22M12 38c2 11 10 18 20 19 10-1 18-8 20-19"/></svg>';
const addTiles = (map) => window.L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
  maxZoom: 19, attribution: '© OpenStreetMap contributors',
  // The page sends no referrer, but OpenStreetMap's tile policy wants to know which site is asking (just the origin).
  referrerPolicy: 'strict-origin',
}).addTo(map);
const ZONE_STYLE = { color: ZONE_COLOR, weight: 2, fillColor: ZONE_COLOR, fillOpacity: 0.22, interactive: false };

/*
 * Picking the study spot, like parking a scooter: the pin stays in the middle and you drag the map under it.
 * It follows your GPS until you drag; the locate button goes back to following.
 */
const spot = { map: null, circle: null, moved: false };

function spotRadius() {
  const r = Number(document.querySelector('#start-form [name=radiusM]').value);
  return Number.isFinite(r) && r >= 10 ? Math.min(r, 400) : 50;
}

function renderSpot() {
  const L = window.L;
  if (!L || $('setup').hidden) return;
  if (!spot.map) {
    spot.map = L.map('spot-map', { zoomControl: false, doubleClickZoom: 'center', scrollWheelZoom: 'center', touchZoom: 'center' })
      .setView(geo.fix ? [geo.fix.lat, geo.fix.lng] : [34.0205, -118.2856], 17);
    addTiles(spot.map);
    spot.circle = L.circle(spot.map.getCenter(), { ...ZONE_STYLE, radius: spotRadius() }).addTo(spot.map);
    spot.map.on('move', () => spot.circle.setLatLng(spot.map.getCenter()));
    spot.map.on('dragstart', () => { spot.moved = true; $('spot-map').parentElement.dataset.dragging = 'true'; renderSpot(); });
    spot.map.on('dragend', () => { $('spot-map').parentElement.dataset.dragging = 'false'; });
  }
  spot.map.invalidateSize();
  spot.circle.setRadius(spotRadius());
  if (!spot.moved && geo.fix) {
    spot.map.fitBounds(L.latLng(geo.fix.lat, geo.fix.lng).toBounds(spotRadius() * 2.6), { animate: false, maxZoom: 19 });
  }
  $('spot-locate').dataset.on = String(!spot.moved);
  setText('spot-tag', spot.moved ? 'Your anchor drops on the pin' : 'Drag the map to put the pin on your desk');
  setText('spot-acc', spot.moved ? 'Placed by hand' : geo.fix ? `GPS, accurate to ${Math.round(geo.fix.accuracy)} m` : geo.error || 'Finding you...');
}

const zoneMap = { map: null, key: '', anchor: null, zone: null, unlock: null, you: null, youHalo: null };

/** Red: where using your phone counts. Dashed: where Stop unlocks (zone plus GPS margin). Blue: you, with GPS accuracy. */
function renderMap(loc, own) {
  const L = window.L;
  if (!L || !loc.anchor) return;
  const anchor = [loc.anchor.lat, loc.anchor.lng];
  if (!zoneMap.map) {
    zoneMap.map = L.map('zone-map', { zoomControl: false, dragging: false, touchZoom: false, scrollWheelZoom: false, doubleClickZoom: false, boxZoom: false, keyboard: false, tap: false });
    addTiles(zoneMap.map);
    zoneMap.zone = L.circle(anchor, { ...ZONE_STYLE, radius: 1 }).addTo(zoneMap.map);
    zoneMap.unlock = L.circle(anchor, { radius: 1, color: INK, weight: 2, dashArray: '6 6', fill: false }).addTo(zoneMap.map);
    zoneMap.anchor = L.marker(anchor, { icon: L.divIcon({ className: '', html: `<span class="anchor-pin">${ANCHOR_SVG}</span>`, iconSize: [28, 28], iconAnchor: [14, 14] }), keyboard: false, interactive: false }).addTo(zoneMap.map);
    zoneMap.youHalo = L.circle(anchor, { radius: 1, stroke: false, fillColor: YOU_COLOR, fillOpacity: 0.15, interactive: false });
    zoneMap.you = L.circleMarker(anchor, { radius: 7, color: '#fff', weight: 3, fillColor: YOU_COLOR, fillOpacity: 1, interactive: false });
  }
  const radius = loc.radiusM ?? 50;
  const unlockAt = loc.unlockAtM ?? radius;
  zoneMap.zone.setLatLng(anchor).setRadius(radius);
  zoneMap.unlock.setLatLng(anchor).setRadius(unlockAt);
  zoneMap.anchor.setLatLng(anchor);
  const showYou = Boolean(own);
  if (showYou) {
    const you = [geo.fix.lat, geo.fix.lng];
    zoneMap.you.setLatLng(you).addTo(zoneMap.map);
    zoneMap.youHalo.setLatLng(you).setRadius(geo.fix.accuracy).addTo(zoneMap.map);
  } else {
    zoneMap.you.remove();
    zoneMap.youHalo.remove();
  }
  // Keep the whole unlock ring and you in view; only re-fit when that frame actually changes.
  let bounds = L.latLng(anchor).toBounds(unlockAt * 2);
  if (showYou) bounds = bounds.extend([geo.fix.lat, geo.fix.lng]);
  // The map's size is in the key too, so it re-fits after the gate or locked screen was covering it.
  const box = $('zone-map');
  const key = `${bounds.toBBoxString()} ${box.clientWidth}x${box.clientHeight}`;
  if (key !== zoneMap.key) {
    zoneMap.key = key;
    zoneMap.map.invalidateSize();
    // Leave room for the status banner on top and the key at the bottom.
    zoneMap.map.fitBounds(bounds, { paddingTopLeft: [20, 96], paddingBottomRight: [20, 52], maxZoom: 19, animate: false });
  }
}

/** The anchor falls in and ripples out, then gets out of the way. */
function playDrop(fix, byHand = false) {
  setText('drop-sub', byHand ? 'Right where you put the pin.' : fix ? `Right here, accurate to ${Math.round(fix.accuracy)} m.` : 'Right here.');
  const el = $('drop');
  el.hidden = false;
  // Restart the CSS animations if it plays twice without a reload.
  el.style.animation = 'none';
  void el.offsetWidth;
  el.style.animation = '';
  return new Promise((resolve) => setTimeout(() => { el.hidden = true; resolve(); }, DROP_MS));
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
  $('gray').dataset.on = String(Boolean(on && fx.grayscale));
  $('dim').dataset.on = String(Boolean(on && fx.dim));
  document.documentElement.style.fontSize = on && fx.bigText ? '175%' : '';
  keepFlashing(on && fx.flash);
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
  if (fx.flash) on.push('flashing');
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

/* ---------- one-time install ---------- */

const INSTALLED_STORE = 'anchor-installed';
const installed = () => { try { return localStorage.getItem(INSTALLED_STORE) === '1'; } catch { return false; } };

async function renderInstall() {
  setText('copy-base', location.origin);
  setText('copy-key', key);
  $('installed').checked = installed();
  $('install').open = !installed();
  let links = [];
  try {
    const res = await fetch('shortcuts.json', { cache: 'no-store' });
    links = (await res.json()).links ?? [];
  } catch { /* shown as not ready below */ }
  const list = $('install-links');
  list.replaceChildren(...links.map(({ name, url }) => {
    const li = document.createElement('li');
    const ok = typeof url === 'string' && url.startsWith('https://www.icloud.com/shortcuts/');
    const el = document.createElement(ok ? 'a' : 'span');
    el.textContent = ok ? `Add ${name}` : `${name} (link not added yet)`;
    if (ok) { el.href = url; el.className = 'btn btn--small btn--ink'; }
    li.append(el);
    return li;
  }));
}

function wireInstall() {
  $('installed').addEventListener('change', (e) => {
    try { localStorage.setItem(INSTALLED_STORE, e.target.checked ? '1' : '0'); } catch { /* private mode */ }
  });
  document.querySelectorAll('[data-copy]').forEach((btn) => btn.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText($(btn.dataset.copy).textContent);
      btn.textContent = 'Copied';
    } catch {
      btn.textContent = 'Press and hold to copy';
    }
  }));
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

const sample = (p) => ({ lat: p.coords.latitude, lng: p.coords.longitude, accuracy: p.coords.accuracy });

/**
 * Several GPS readings into one: the sloppy ones (worse than twice the best) are dropped and the rest are
 * averaged, weighting each by how sure the phone was (1 / accuracy squared). Reports the best accuracy seen.
 */
function blend(samples) {
  const best = Math.min(...samples.map((s) => s.accuracy));
  const keep = samples.filter((s) => s.accuracy <= Math.max(best * 2, best + 5));
  let w = 0; let lat = 0; let lng = 0;
  for (const s of keep) {
    const k = 1 / Math.max(1, s.accuracy) ** 2;
    w += k; lat += s.lat * k; lng += s.lng * k;
  }
  return { lat: lat / w, lng: lng / w, accuracy: best };
}

function startLocation() {
  if (!navigator.geolocation) { geo.error = 'This browser has no location.'; return; }
  navigator.geolocation.watchPosition(
    (p) => {
      const now = Date.now();
      geo.samples = [...geo.samples.filter((s) => now - s.t <= SMOOTH_MS), { ...sample(p), t: now }];
      geo.fix = blend(geo.samples);
      geo.at = now;
      geo.error = '';
      if (snap?.status !== 'running') renderSpot();
    },
    (e) => { geo.error = e.code === 1 ? 'Location is blocked. Allow it for this page in Settings, then reload.' : 'Could not get your location.'; },
    { enableHighAccuracy: true, maximumAge: 0, timeout: 20000 },
  );
  // Live tracking: redraw the distance every half second, and keep the server's copy close behind.
  setInterval(() => {
    if (snap?.status !== 'running') return;
    renderLive();
    sendFix();
  }, LIVE_MS);
}

/**
 * Where to drop the anchor: listen to GPS for a few seconds (it sharpens as it goes) and blend the best readings.
 * Stops early once a reading is good to ANCHOR_GOOD_M. `onProgress` gets the best accuracy so far.
 */
function preciseFix(onProgress) {
  return new Promise((resolve, reject) => {
    if (!navigator.geolocation) return reject(new Error('This browser has no location.'));
    const started = Date.now();
    const samples = [];
    let done = false;
    let watchId = null;
    const finish = (error) => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      if (watchId !== null) navigator.geolocation.clearWatch(watchId);
      if (samples.length) { geo.at = Date.now(); return resolve(blend(samples)); }
      if (error?.code !== 1 && geo.fix) return resolve(geo.fix);
      reject(new Error(error?.code === 1 ? 'Location is blocked. Allow it for this page, then try again.' : 'Could not get your location. Try again outside.'));
    };
    const timer = setTimeout(finish, ANCHOR_SAMPLE_MS);
    // A good reading can arrive before the minimum wait, and GPS may not send another one.
    setTimeout(() => { if (samples.some((s) => s.accuracy <= ANCHOR_GOOD_M)) finish(); }, ANCHOR_MIN_MS);
    watchId = navigator.geolocation.watchPosition(
      (p) => {
        samples.push(sample(p));
        onProgress(Math.min(...samples.map((s) => s.accuracy)));
        if (p.coords.accuracy <= ANCHOR_GOOD_M && Date.now() - started >= ANCHOR_MIN_MS) finish();
      },
      (e) => { if (e.code === 1) finish(e); },
      { enableHighAccuracy: true, maximumAge: 0, timeout: ANCHOR_SAMPLE_MS },
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
  const radiusM = Number(data.get('radiusM'));
  if (!Number.isInteger(radiusM) || radiusM < 10 || radiusM > 400) return setText('start-error', 'Zone size must be 10 to 400 meters.');
  if (!Number.isInteger(minutes) || minutes < 1 || minutes > 240) return setText('start-error', 'Minutes must be 1 to 240.');
  if (Number.isNaN(tuition)) return setText('start-error', 'Tuition must be a number.');
  if (Number.isNaN(deposit) || (deposit ?? 0) > (rules.depositMax ?? 10000)) return setText('start-error', 'Deposit must be a number up to the limit.');
  btn.disabled = true;
  setText('start-error', '');
  try {
    let anchor;
    if (spot.moved && spot.map) {
      // You put the pin where your desk is, so that's the anchor, exactly.
      const c = spot.map.getCenter();
      anchor = { lat: c.lat, lng: c.lng, accuracy: 5 };
    } else {
      setText('start-btn', 'Finding your exact spot...');
      geo.fix = await preciseFix((best) => setText('start-btn', `Finding your exact spot... ${Math.round(best)} m`));
      anchor = geo.fix;
    }
    const body = { studyMinutes: minutes, radiusM, anchor, mode: 'phone', courseName: String(data.get('courseName')).trim() || 'BUAD 112' };
    if (tuition !== null) body.tuitionPerYear = tuition;
    if (deposit) body.deposit = deposit;
    body.quiet = data.get('quiet') === 'on';
    try { localStorage.setItem('anchor-quiet', body.quiet ? '1' : '0'); } catch { /* private mode */ }
    const res = await api('/api/start', body);
    if (!res.ok) throw new Error(res.error);
    await playDrop(anchor, spot.moved);
    if (installed()) runEnforcer();
  } catch (err) {
    setText('start-error', err.message);
  } finally {
    btn.disabled = false;
    setText('start-btn', 'Drop anchor & start');
  }
}

/* ---------- stand-ins for the Shortcut-only effects ---------- */
// A web page can't flash other apps, or change silent mode or volume, so the page
// shows them on screen instead. On a real app open the Shortcuts do the real thing.

const reduceMotion = () => window.matchMedia('(prefers-reduced-motion: reduce)').matches;

const ALARM_MS = 4000;
let alarm = null;
let alarmStop = null;

/**
 * Called inside the tap, before any await: iOS only plays sound that starts from a tap. When the Loud
 * step is already on (or `force`), the alarm, a tone, and the voice start right here. Each one reports
 * what happened in the Presenter panel, since iPhones block sound in different ways.
 */
function soundOnTap(force = false) {
  const loud = force || Boolean(snap?.status === 'running' && snap?.phoneFx?.silentOff);
  const report = [];
  const note = (text) => { report.push(text); setText('sound-status', report.join(' · ')); };
  setText('sound-status', '');
  try {
    // Play through the silent switch, like a video does (Safari 16.4+).
    if (navigator.audioSession) {
      navigator.audioSession.type = 'playback';
      note('silent override on');
    } else {
      note('no silent override on this browser');
    }
  } catch (err) { note(`silent override failed: ${err.name}`); }
  if (!loud) {
    unlockAudio();
    return;
  }
  playAlarm(note);
  playTone(note);
  speak('Put the phone down. You are at your anchor.', note);
}

/** Before the Loud step, a tap still primes the audio so later taps are allowed to play. */
function unlockAudio() {
  try {
    alarm = alarm ?? new Audio('alarm.wav');
    alarm.muted = true;
    alarm.play().then(() => alarm.pause()).catch(() => {});
    tone = tone ?? new (window.AudioContext || window.webkitAudioContext)();
    tone.resume().catch(() => {});
  } catch { /* priming is best effort */ }
}

function playAlarm(note) {
  try {
    alarm = alarm ?? new Audio('alarm.wav');
    alarm.loop = true;
    alarm.muted = false;
    alarm.volume = 1;
    if (alarm.readyState > 0) alarm.currentTime = 0;
    alarm.play().then(() => note('alarm playing')).catch((err) => note(`alarm blocked: ${err.name}`));
    clearTimeout(alarmStop);
    alarmStop = setTimeout(() => alarm.pause(), ALARM_MS);
  } catch (err) { note(`alarm failed: ${err.name}`); }
}

let tone = null;
/** A siren made in the browser (Web Audio), a second route in case the audio file is blocked. */
function playTone(note) {
  try {
    tone = tone ?? new (window.AudioContext || window.webkitAudioContext)();
    // The context starts a moment after the tap, so report its state once resume settles.
    tone.resume().then(() => note(`tone ${tone.state}`), (err) => note(`tone blocked: ${err.name}`));
    const osc = tone.createOscillator();
    const gain = tone.createGain();
    const t = tone.currentTime;
    osc.type = 'sawtooth';
    for (let i = 0; i < 8; i += 1) {
      osc.frequency.setValueAtTime(620, t + i * 0.5);
      osc.frequency.linearRampToValueAtTime(1350, t + i * 0.5 + 0.45);
    }
    gain.gain.setValueAtTime(0.4, t);
    osc.connect(gain).connect(tone.destination);
    osc.start(t);
    osc.stop(t + ALARM_MS / 1000);
  } catch (err) { note(`tone failed: ${err.name}`); }
}

function speak(text, note = () => {}) {
  try {
    if (!('speechSynthesis' in window)) return note('no voice on this browser');
    const line = new SpeechSynthesisUtterance(text);
    line.volume = 1;
    line.onstart = () => note('voice speaking');
    line.onerror = (e) => note(`voice error: ${e.error}`);
    speechSynthesis.speak(line);
  } catch (err) { note(`voice failed: ${err.name}`); }
}

/** While the Flashing step is on, a burst of flashes every few seconds, for as long as the page is open. */
const FLASH_EVERY_MS = 5000;
let flashLoop = null;
function keepFlashing(on) {
  if (on && !flashLoop) {
    flashScreen(2);
    flashLoop = setInterval(() => flashScreen(2), FLASH_EVERY_MS);
  } else if (!on && flashLoop) {
    clearInterval(flashLoop);
    flashLoop = null;
    $('flash').dataset.on = 'false';
  }
}

/** One burst of flashes: at most one flash a second; one slow pulse with Reduce Motion on. */
function flashScreen(times) {
  const el = $('flash');
  if (reduceMotion()) {
    el.dataset.soft = 'true';
    el.dataset.on = 'true';
    setTimeout(() => { el.dataset.on = 'false'; }, 700);
    return;
  }
  el.dataset.soft = 'false';
  let n = 0;
  const step = () => {
    el.dataset.on = String(n % 2 === 0);
    n += 1;
    if (n < times * 2) setTimeout(step, 500);
    else el.dataset.on = 'false';
  };
  step();
}

async function standIns(fx) {
  if (fx.flash) flashScreen(3);
}

async function simulateOpen() {
  soundOnTap();
  const res = await api('/api/phone/open', { app: 'Instagram' });
  if (!res.ok) return setText('session-error', res.error);
  setText('session-error', '');
  await standIns(res.data ?? {});
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
  $('sound-btn').addEventListener('click', () => soundOnTap(true));
  try { $('quiet').checked = localStorage.getItem('anchor-quiet') === '1'; } catch { /* private mode */ }
  $('enforcer-btn').addEventListener('click', runEnforcer);
  $('locked-back').addEventListener('click', closeLocked);
  show('a2hs', window.navigator.standalone === false);
  $('start-form').addEventListener('submit', onStart);
  // Like trying to park in a no-parking zone: Stop inside the zone explains instead of doing nothing.
  $('stop-btn').addEventListener('click', async () => {
    if (!snap?.canStop) { renderLive(); show('cant', true); $('cant-ok').focus(); return; }
    const r = await api('/api/stop', {});
    if (!r.ok) setText('session-error', r.error);
  });
  $('cant-ok').addEventListener('click', () => show('cant', false));
  $('cant').addEventListener('click', (e) => { if (e.target === e.currentTarget) show('cant', false); });
  $('spot-locate').addEventListener('click', () => { spot.moved = false; renderSpot(); });
  document.querySelector('#start-form [name=radiusM]').addEventListener('input', renderSpot);
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
  wireInstall();
  renderInstall();
  startLocation();
  connect();
  if (location.hash === '#gate') openGate();
  if (location.hash === '#locked') openLocked();
}

init();
