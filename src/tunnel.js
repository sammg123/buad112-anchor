/**
 * Phone mode: a tunnel gives the Mac's localhost an HTTPS address the phone can reach
 * (iOS only allows location over HTTPS). With an ngrok domain it uses ngrok's free static domain through
 * the @ngrok/ngrok package (nothing else to install), so the address never changes. Otherwise a
 * Cloudflare quick tunnel (no account, new address every start), if cloudflared is installed.
 */
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import QRCode from 'qrcode';
import ngrok from '@ngrok/ngrok';

const TUNNEL_URL = /https:\/\/[a-z0-9-]+\.trycloudflare\.com/;

const DIRS = [path.join(os.homedir(), '.local', 'bin'), '/opt/homebrew/bin', '/usr/local/bin'];

function findBin(name) {
  const dirs = [...(process.env.PATH ?? '').split(path.delimiter), ...DIRS];
  return dirs.map((dir) => path.join(dir, name)).find((file) => fs.existsSync(file)) ?? null;
}

/** Which tunnel to run: [binary, args, fixed base URL or null], or an error. */
function tunnelCommand(port) {
  const bin = findBin('cloudflared');
  if (!bin) {
    return { error: 'No tunnel: set NGROK_AUTHTOKEN and NGROK_DOMAIN once (see README: Phone setup), or install cloudflared.' };
  }
  return { bin, args: ['tunnel', '--no-autoupdate', '--url', `http://127.0.0.1:${port}`] };
}

const cleanDomain = (raw) => String(raw ?? '').trim().replace(/^https?:\/\//, '').replace(/\/.*$/, '');

/**
 * ngrok settings: from the environment the first time, then remembered in data/ngrok.json so later
 * starts are just `npm start`.
 */
export function ngrokSettings(dataDir, env = process.env) {
  const file = path.join(dataDir, 'ngrok.json');
  let saved = {};
  try {
    saved = JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    // first run
  }
  const authtoken = String(env.NGROK_AUTHTOKEN ?? saved.authtoken ?? '').trim();
  const domain = cleanDomain(env.NGROK_DOMAIN ?? saved.domain);
  if (!authtoken || !domain) return null;
  if (authtoken !== saved.authtoken || domain !== saved.domain) {
    fs.mkdirSync(dataDir, { recursive: true });
    fs.writeFileSync(file, JSON.stringify({ authtoken, domain }), { mode: 0o600 });
  }
  return { authtoken, domain };
}

/** The page the phone opens, with its key. */
export const phoneUrl = (base, token) => `${base}/phone.html?k=${encodeURIComponent(token)}`;

/** The page classmates open from the projector: watch the session, try a sandbox. */
export const guestUrl = (base, guestToken) => `${base}/guest.html?k=${encodeURIComponent(guestToken)}`;

/**
 * @param {{ port: number, token: string, guestToken: string, log: ReturnType<typeof import('./log.js').createLogger> }} deps
 */
export function startTunnel({ port, token, guestToken, dataDir, log }) {
  let base = null;
  let qrSvg = null;
  let guestQrSvg = null;
  let error = null;
  let stop = () => {};

  const found = (url) => {
    base = url;
    error = null;
    const qr = (link) => QRCode.toString(link, { type: 'svg', margin: 1 });
    Promise.all([qr(phoneUrl(base, token)), qr(guestUrl(base, guestToken))])
      .then(([owner, guest]) => {
        qrSvg = owner;
        guestQrSvg = guest;
      })
      .catch((e) => log.error('Could not draw the pairing QR codes', e));
    log.info(`Phone link: ${phoneUrl(base, token)}`);
    log.info(`Shortcuts base URL: ${base}   key: ${token}`);
    log.info(`Guest link (projector): ${guestUrl(base, guestToken)}`);
  };

  const settings = ngrokSettings(dataDir);
  if (settings) {
    log.info(`Opening the ngrok tunnel to https://${settings.domain} ...`);
    ngrok
      .forward({ addr: `127.0.0.1:${port}`, authtoken: settings.authtoken, domain: settings.domain })
      .then((listener) => {
        found(listener.url());
        stop = () => listener.close().catch(() => {});
      })
      .catch((e) => {
        error = `ngrok refused: ${e.message}. Check the authtoken and domain on dashboard.ngrok.com, then restart.`;
        log.error(error);
      });
  } else {
    const command = tunnelCommand(port);
    if (command.error) {
      error = command.error;
      log.error(`${error} The phone can't reach Anchor until then.`);
    } else {
      const child = spawn(command.bin, command.args, { stdio: ['ignore', 'pipe', 'pipe'] });
      const scan = (chunk) => {
        const match = base ? null : String(chunk).match(TUNNEL_URL);
        if (match) found(match[0]);
      };
      child.stdout.on('data', scan);
      child.stderr.on('data', scan);
      child.on('exit', (code) => {
        if (code !== null && code !== 0) {
          error = `cloudflared exited (${code}). Check its output above and restart Anchor.`;
          log.error(error);
        }
      });
      stop = () => child.kill();
    }
  }

  return {
    connect: () => ({
      url: base && phoneUrl(base, token),
      base,
      token,
      qrSvg,
      guestUrl: base && guestUrl(base, guestToken),
      guestQrSvg,
      error,
    }),
    stop: () => stop(),
  };
}
