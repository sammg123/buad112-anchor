/**
 * Phone mode: a tunnel gives the Mac's localhost an HTTPS address the phone can reach
 * (iOS only allows location over HTTPS). With NGROK_DOMAIN set it uses ngrok's free static domain, so the
 * address never changes; otherwise a Cloudflare quick tunnel (no account, new address every start).
 */
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import QRCode from 'qrcode';

const TUNNEL_URL = /https:\/\/[a-z0-9-]+\.trycloudflare\.com/;

const DIRS = [path.join(os.homedir(), '.local', 'bin'), '/opt/homebrew/bin', '/usr/local/bin'];

function findBin(name) {
  const dirs = [...(process.env.PATH ?? '').split(path.delimiter), ...DIRS];
  return dirs.map((dir) => path.join(dir, name)).find((file) => fs.existsSync(file)) ?? null;
}

/** Which tunnel to run: [binary, args, fixed base URL or null], or an error. */
function tunnelCommand(port) {
  const domain = process.env.NGROK_DOMAIN?.replace(/^https?:\/\//, '').replace(/\/$/, '');
  if (domain) {
    const bin = findBin('ngrok');
    if (!bin) return { error: 'NGROK_DOMAIN is set but ngrok is not installed. See README: Phone setup.' };
    return { bin, args: ['http', `--url=${domain}`, String(port), '--log=stdout'], base: `https://${domain}` };
  }
  const bin = findBin('cloudflared');
  if (!bin) return { error: 'cloudflared is not installed. See README: Phone setup.' };
  return { bin, args: ['tunnel', '--no-autoupdate', '--url', `http://127.0.0.1:${port}`], base: null };
}

/** The page the phone opens, with its key. */
export const phoneUrl = (base, token) => `${base}/phone.html?k=${encodeURIComponent(token)}`;

/**
 * @param {{ port: number, token: string, log: ReturnType<typeof import('./log.js').createLogger> }} deps
 */
export function startTunnel({ port, token, log }) {
  let base = null;
  let qrSvg = null;
  let error = null;
  const command = tunnelCommand(port);
  if (command.error) {
    error = command.error;
    log.error(`${error} The phone can't reach Anchor until it is.`);
    return { connect: () => ({ url: null, base: null, token, qrSvg: null, error }), stop() {} };
  }

  const child = spawn(command.bin, command.args, { stdio: ['ignore', 'pipe', 'pipe'] });
  const found = (url) => {
    base = url;
    QRCode.toString(phoneUrl(base, token), { type: 'svg', margin: 1 })
      .then((svg) => {
        qrSvg = svg;
      })
      .catch((e) => log.error('Could not draw the pairing QR code', e));
    log.info(`Phone link: ${phoneUrl(base, token)}`);
    log.info(`Shortcuts base URL: ${base}   key: ${token}`);
  };
  const scan = (chunk) => {
    const match = base ? null : String(chunk).match(TUNNEL_URL);
    if (match) found(match[0]);
  };
  // ngrok's address is known up front; Cloudflare's shows up in its log.
  if (command.base) found(command.base);
  child.stdout.on('data', scan);
  child.stderr.on('data', scan);
  child.on('exit', (code) => {
    if (code !== null && code !== 0) {
      error = `${path.basename(command.bin)} exited (${code}). Check its output above and restart Anchor.`;
      log.error(error);
    }
  });

  return {
    connect: () => ({ url: base && phoneUrl(base, token), base, token, qrSvg, error }),
    stop: () => child.kill(),
  };
}
