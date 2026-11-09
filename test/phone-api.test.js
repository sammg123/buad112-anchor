import { test, describe, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { createApp } from '../src/app.js';
import { createHttpServer } from '../src/server.js';
import { GATE_SECONDS, PASS_SECONDS, DIM_BRIGHTNESS } from '../src/phone.js';
import { CONFESSION_PHRASE } from '../src/config.js';

const PUBLIC_DIR = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'public');
const T0 = 1_700_000_000_000;
const TOKEN = 'test-token-123';
const ANCHOR = { lat: 34.0224, lng: -118.2851 };
const FAR = { lat: 34.0254, lng: -118.2851 }; // ~330 m north

let clock = T0;
let app;
let server;
let port;

/** Requests as the tunnel sees them: a public Host and no Origin, like an iOS Shortcut. */
function remote(method, route, { body, key = TOKEN } = {}) {
  const payload = body === undefined ? undefined : JSON.stringify(body);
  const headers = { host: 'demo.trycloudflare.com', 'content-type': 'application/json' };
  if (key) headers['x-anchor-key'] = key;
  return new Promise((resolve, reject) => {
    const req = http.request({ host: '127.0.0.1', port, method, path: route, headers }, (res) => {
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => {
        const text = Buffer.concat(chunks).toString('utf8');
        let json = null;
        try {
          json = JSON.parse(text);
        } catch {
          // static file
        }
        resolve({ status: res.statusCode, json, text });
      });
    });
    req.on('error', reject);
    req.end(payload);
  });
}

const open = (extra = {}) => remote('POST', '/api/phone/open', { body: { app: 'Instagram', ...extra } });
const close = () => remote('POST', '/api/phone/close', { body: { app: 'Instagram' } });
const advance = (ms) => {
  // Step in small ticks: the engine treats one gap over 2 s as a pause.
  for (let t = 0; t < ms; t += 500) {
    clock += 500;
    app.step();
  }
};

async function startPhoneSession(extra = {}) {
  await remote('POST', '/api/location', { body: { ...ANCHOR, accuracy: 10 } });
  const r = await remote('POST', '/api/start', { body: { studyMinutes: 30, mode: 'phone', ...extra } });
  assert.equal(r.status, 200, r.text);
}

describe('phone mode over the tunnel', () => {
  before(async () => {
    server = createHttpServer({ app: { phoneNow: () => app.phoneNow(), ...proxy() }, publicDir: PUBLIC_DIR, token: TOKEN });
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    port = server.address().port;
  });
  after(() => server.close());
  beforeEach(() => {
    clock = T0;
    app = createApp({ now: () => clock, effects: { run() {}, stopAll() {} } });
  });

  test('without the token, the API refuses but the page loads', async () => {
    assert.equal((await remote('GET', '/api/state', { key: null })).status, 403);
    assert.equal((await remote('POST', '/api/phone/open', { key: null, body: {} })).status, 403);
    assert.equal((await remote('GET', '/', { key: null })).status, 200);
    assert.equal((await remote('GET', '/api/state', { key: 'wrong-token-12' })).status, 403);
  });

  test('the pairing code is only for the Mac', async () => {
    assert.equal((await remote('GET', '/api/connect')).status, 403);
  });

  test('an app open with no session does nothing', async () => {
    const r = await open();
    assert.equal(r.status, 200);
    assert.equal(r.json.data.active, false);
    assert.equal(r.json.data.gate, false);
  });

  test('first open gates for 10 s, then grayscale, loud, and dim arrive with phone time', async () => {
    await startPhoneSession();
    let fx = (await open()).json.data;
    assert.equal(fx.active, true);
    assert.equal(fx.gate, true);
    assert.equal(fx.gateSeconds, GATE_SECONDS[0]);
    assert.equal(fx.grayscale, false);

    advance(16_000);
    fx = (await open()).json.data;
    assert.equal(fx.grayscale, true);
    assert.equal(fx.dim, false);

    advance(15_000);
    fx = (await open()).json.data;
    assert.equal(fx.silentOff, true);
    assert.equal(fx.volumePercent, 100);
    assert.equal(fx.dim, false);

    advance(15_000);
    fx = (await open()).json.data;
    assert.equal(fx.dim, true);
    assert.equal(fx.brightness, DIM_BRIGHTNESS);
    assert.equal(fx.brightnessPercent, 15);
  });

  test('huge text, shame wallpaper, and flashlight come later', async () => {
    await startPhoneSession();
    await open();
    advance(76_000);
    let fx = (await open()).json.data;
    assert.equal(fx.bigText, true);
    assert.equal(fx.shame, false);
    advance(15_000);
    fx = (await open()).json.data;
    assert.equal(fx.shame, true);
    assert.equal(fx.flash, false);
    advance(15_000);
    fx = (await open()).json.data;
    assert.equal(fx.flash, true);
    assert.ok(fx.flashBlinks > 0);
  });

  test('effects stay on after the app closes, while you are in the zone', async () => {
    await startPhoneSession();
    await open();
    advance(50_000);
    const fx = (await close()).json.data;
    assert.equal(fx.active, true);
    assert.equal(fx.grayscale, true);
    assert.equal(fx.dim, true);
    assert.equal(fx.reapplySeconds > 0, true);
    const now = (await remote('GET', '/api/phone/now')).json.data;
    assert.equal(now.grayscale, true);
  });

  test('Settings and Shortcuts are locked inside the zone and free outside it', async () => {
    assert.equal((await remote('POST', '/api/phone/guard', { body: { app: 'Settings' } })).json.data.locked, false);
    await startPhoneSession();
    let fx = (await remote('POST', '/api/phone/guard', { body: { app: 'Settings' } })).json.data;
    assert.equal(fx.locked, true);
    assert.equal(fx.gate, true);
    assert.equal(app.state().phone.onPhone, false);
    fx = (await remote('POST', '/api/phone/guard', { body: { app: 'Settings', ...FAR, accuracy: 10 } })).json.data;
    assert.equal(fx.locked, false);
    assert.equal(fx.reapplySeconds, 0);
  });

  test('the shame wallpaper is a PNG and needs the key', async () => {
    await startPhoneSession();
    const r = await remote('GET', '/api/wallpaper.png');
    assert.equal(r.status, 200);
    assert.equal(r.text.slice(1, 4), 'PNG');
    assert.equal((await remote('GET', '/api/wallpaper.png', { key: null })).status, 403);
  });

  test('closing the app pauses the clock; the step stays', async () => {
    await startPhoneSession();
    await open();
    advance(20_000);
    await close();
    const level = app.state().phone.level;
    advance(60_000);
    assert.equal(app.state().phone.level, level);
    assert.equal(app.state().phone.onPhone, false);
  });

  test('passing the gate stops the bounce for a while, then it comes back', async () => {
    await startPhoneSession();
    await open();
    const pass = await remote('POST', '/api/gate', { body: {} });
    assert.equal(pass.status, 200);
    assert.equal(pass.json.data.gate, false);
    await close();
    assert.equal((await open()).json.data.gate, false);
    await close();
    clock += PASS_SECONDS[0] * 1000 + 1;
    assert.equal((await open()).json.data.gate, true);
  });

  test('the confession blocks the gate until typed, even after the app closed', async () => {
    await startPhoneSession();
    await open();
    advance(121_000);
    await close();
    let fx = app.phoneNow();
    assert.equal(fx.confess, true);
    const wrong = await remote('POST', '/api/gate', { body: { text: 'nope' } });
    assert.equal(wrong.status, 409);
    const right = await remote('POST', '/api/gate', { body: { text: CONFESSION_PHRASE } });
    assert.equal(right.status, 200);
    fx = right.json.data;
    assert.equal(fx.confess, false);
    assert.equal(fx.gate, false);
  });

  test('away from the anchor everything is off', async () => {
    await startPhoneSession();
    await open();
    advance(40_000);
    const fx = (await open({ ...FAR, accuracy: 10 })).json.data;
    assert.equal(fx.active, false);
    assert.equal(fx.inZone, false);
    assert.equal(fx.grayscale, false);
    assert.equal(fx.gate, false);
  });

  test('the phone ladder ends in the deposit only when money is down', async () => {
    await startPhoneSession({ deposit: 20 });
    assert.equal(app.state().mode, 'phone');
    assert.equal(app.state().phone.maxLevel, 9);
  });
});

/** Forward every app method to the current `app`, which beforeEach replaces. */
function proxy() {
  const names = ['wallpaper', 'state', 'start', 'phone', 'location', 'demo', 'confess', 'stop', 'reset', 'subscribe'];
  const out = Object.fromEntries(names.map((n) => [n, (...args) => app[n](...args)]));
  out.phoneOpened = (e) => app.phoneOpened(e);
  out.phoneClosed = (e) => app.phoneClosed(e);
  out.passGate = (t) => app.passGate(t);
  out.phoneGuarded = (e) => app.phoneGuarded(e);
  return out;
}
