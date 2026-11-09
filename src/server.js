/**
 * Localhost HTTP server: static page, JSON API, and a server-sent-events stream.
 * Only answers requests addressed to this machine's loopback name, and only accepts
 * same-origin JSON posts, so another website cannot drive the session.
 * Phone mode: with a token set, the page is also served through a tunnel, and any request carrying
 * the token (the `x-anchor-key` header or `?k=`) may use the API: the phone page and its iOS Shortcuts.
 */
import http from 'node:http';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {
  parseStart,
  parseLocation,
  parsePhone,
  parseDemo,
  parseConfess,
  parsePhoneEvent,
  parseGatePass,
} from './validate.js';
import { createLogger } from './log.js';
import { LADDER, LADDERS } from './ladder.js';
import { DEPOSIT_MAX } from './deposit.js';
import { LEVEL_MS, RADIUS_M, CONFESSION_PHRASE, CLASS_MINUTES_PER_YEAR, LIMITS } from './config.js';

const RULES = Object.freeze({
  ladder: LADDER,
  levelMs: LEVEL_MS,
  radiusM: RADIUS_M,
  confession: CONFESSION_PHRASE,
  classMinutesPerYear: CLASS_MINUTES_PER_YEAR,
  maxTuitionPerYear: LIMITS.maxTuitionPerYear,
  depositMax: DEPOSIT_MAX,
  ladders: Object.fromEntries(
    Object.entries(LADDERS).map(([name, ladder]) => [name, { steps: ladder.steps, levelMs: ladder.levelMs }]),
  ),
});

const MAX_BODY_BYTES = 8 * 1024;
const LOOPBACK_HOSTS = Object.freeze(['localhost', '127.0.0.1']);
const MAX_EVENT_STREAMS = 10;

const CONTENT_TYPES = Object.freeze({
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.woff2': 'font/woff2',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
  '.webmanifest': 'application/manifest+json',
});

const SECURITY_HEADERS = Object.freeze({
  'content-security-policy':
    "default-src 'self'; script-src 'self'; style-src 'self'; font-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'",
  'x-content-type-options': 'nosniff',
  'referrer-policy': 'no-referrer',
  'cache-control': 'no-store',
});

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

function sendJson(res, status, payload) {
  res.writeHead(status, { ...SECURITY_HEADERS, 'content-type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(payload));
}

const success = (res, data) => sendJson(res, 200, { success: true, data, error: null });
const failure = (res, status, error) => sendJson(res, status, { success: false, data: null, error });

function readJson(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > MAX_BODY_BYTES * 64) req.destroy();
      if (size <= MAX_BODY_BYTES) chunks.push(chunk);
    });
    req.on('end', () => {
      if (size > MAX_BODY_BYTES) {
        reject(new HttpError(413, 'That request is too large.'));
        return;
      }
      try {
        resolve(chunks.length ? JSON.parse(Buffer.concat(chunks).toString('utf8')) : {});
      } catch {
        reject(new HttpError(400, 'That request body is not valid JSON.'));
      }
    });
    req.on('error', reject);
  });
}

const allowedOrigins = (port) => LOOPBACK_HOSTS.map((host) => `http://${host}:${port}`);
const isLoopbackHost = (hostHeader, port) =>
  typeof hostHeader === 'string' && LOOPBACK_HOSTS.some((host) => hostHeader.toLowerCase() === `${host}:${port}`);

/** Wraps an app action result into an HTTP response. */
function respond(res, result) {
  if (result.ok) return success(res, result.data);
  return failure(res, result.status ?? 400, result.error);
}

/**
 * Route table: each POST route validates its body, then calls the app.
 * @param {ReturnType<typeof import('./app.js').createApp>} app
 */
function postRoutes(app) {
  const validated = (parse, act) => (body) => {
    const parsed = parse(body);
    return parsed.ok ? act(parsed.value) : { ok: false, status: 400, error: parsed.error };
  };
  return Object.freeze({
    '/api/start': validated(parseStart, (config) => app.start(config)),
    '/api/phone': validated(parsePhone, (onPhone) => app.phone(onPhone)),
    '/api/location': validated(parseLocation, (fix) => app.location(fix)),
    '/api/demo': validated(parseDemo, (demo) => app.demo(demo)),
    '/api/confess': validated(parseConfess, (text) => app.confess(text)),
    '/api/phone/open': validated(parsePhoneEvent, (event) => app.phoneOpened(event)),
    '/api/phone/close': validated(parsePhoneEvent, (event) => app.phoneClosed(event)),
    '/api/phone/guard': validated(parsePhoneEvent, (event) => app.phoneGuarded(event)),
    '/api/gate': validated(parseGatePass, (text) => app.passGate(text)),
    '/api/stop': () => app.stop(),
    '/api/reset': () => app.reset(),
  });
}

function serveEvents(req, res, app, streams) {
  if (streams.size >= MAX_EVENT_STREAMS) return failure(res, 503, 'Too many open Anchor tabs. Close one and reload.');
  streams.add(res);
  res.writeHead(200, {
    ...SECURITY_HEADERS,
    'content-type': 'text/event-stream; charset=utf-8',
    connection: 'keep-alive',
  });
  // A tab that stopped reading (laptop asleep) gets skipped instead of buffering forever.
  const send = (snap) => !res.writableNeedDrain && res.write(`data: ${JSON.stringify(snap)}\n\n`);
  send(app.state());
  const unsubscribe = app.subscribe(send);
  req.on('close', () => {
    unsubscribe();
    streams.delete(res);
  });
  return undefined;
}

function serveStatic(pathname, res, publicDir) {
  const relative = pathname === '/' ? 'index.html' : pathname.slice(1);
  const resolved = path.resolve(publicDir, relative);
  const insidePublic = resolved.startsWith(publicDir + path.sep);
  const type = CONTENT_TYPES[path.extname(resolved)];
  if (!insidePublic || !type || relative.includes('\0')) return failure(res, 404, 'Not found.');
  fs.readFile(resolved, (error, data) => {
    if (error) return failure(res, 404, 'Not found.');
    res.writeHead(200, { ...SECURITY_HEADERS, 'content-type': type });
    return res.end(data);
  });
  return undefined;
}

/** Constant-time token check. */
function hasKey(req, url, token) {
  if (!token) return false;
  const given = String(req.headers['x-anchor-key'] ?? url.searchParams.get('k') ?? '');
  const a = Buffer.from(given);
  const b = Buffer.from(token);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

/**
 * @param {{
 *   app: ReturnType<typeof import('./app.js').createApp>,
 *   publicDir: string,
 *   log?: ReturnType<typeof createLogger>,
 *   token?: string | null,
 *   connect?: () => { url: string | null, qrSvg: string | null },
 * }} deps
 * @returns {http.Server}
 */
export function createHttpServer({ app, publicDir, log = createLogger(), token = null, connect = () => ({ url: null, qrSvg: null }) }) {
  const root = path.resolve(publicDir);
  const routes = postRoutes(app);
  const streams = new Set();

  async function handle(req, res, port) {
    const url = new URL(req.url ?? '/', `http://localhost:${port}`);
    const { pathname } = url;
    const local = isLoopbackHost(req.headers.host, port);
    const keyed = hasKey(req, url, token);
    // Through the tunnel the page itself is public (it holds nothing); everything live needs the token.
    const isPage = req.method === 'GET' && !pathname.startsWith('/api/') && pathname !== '/events';
    if (!local && !keyed && !(token && isPage)) return failure(res, 403, 'Anchor only answers on localhost.');

    if (req.method === 'GET' && pathname === '/api/connect') {
      return local ? success(res, connect()) : failure(res, 403, 'Only the Mac can show the pairing code.');
    }
    if (req.method === 'GET' && pathname === '/api/phone/now') return success(res, app.phoneNow());
    if (req.method === 'GET' && pathname === '/api/wallpaper.png') {
      res.writeHead(200, { ...SECURITY_HEADERS, 'content-type': 'image/png' });
      return res.end(app.wallpaper());
    }
    if (req.method === 'GET' && pathname === '/api/state') return success(res, app.state());
    if (req.method === 'GET' && pathname === '/api/rules') return success(res, RULES);
    if (req.method === 'GET' && pathname === '/events') return serveEvents(req, res, app, streams);
    if (req.method === 'GET') return serveStatic(pathname, res, root);
    if (req.method !== 'POST') return failure(res, 405, 'Method not allowed.');

    // A keyed request (phone page, Shortcuts) proved itself; Shortcuts send no Origin at all.
    if (!keyed && !allowedOrigins(port).includes(req.headers.origin)) {
      return failure(res, 403, 'Cross-site requests are not allowed.');
    }
    if (!String(req.headers['content-type'] ?? '').startsWith('application/json')) {
      return failure(res, 415, 'Send JSON.');
    }
    const route = routes[pathname];
    if (!route) return failure(res, 404, 'Not found.');
    return respond(res, route(await readJson(req)));
  }

  const server = http.createServer((req, res) => {
    const port = server.address()?.port;
    handle(req, res, port).catch((error) => {
      if (error instanceof HttpError) return failure(res, error.status, error.message);
      log.error(`Request ${req.method} ${req.url} failed`, error);
      return failure(res, 500, 'Something went wrong. Check the terminal running Anchor.');
    });
  });
  return server;
}
