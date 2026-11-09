/**
 * Phone mode: what the iOS Shortcut should do to the phone right now. Pure; the Shortcut applies it
 * (Color Filters, Silent Mode, Volume, Brightness, Text Size, Wallpaper, Flashlight, Open URL) and
 * docs/shortcuts.md shows how.
 *
 * Everything a step switches on stays on while you're inside the zone, on the phone or not, and the
 * Shortcuts re-apply it on every app open. Only leaving the zone or the session ending lifts it.
 */
import { ladderFor } from './ladder.js';
import { createCanvas, encodePng } from './png.js';
import { clock, money } from './format.js';

/** Seconds you wait on the gate before you can go back to the app, by step. Longer every step. */
export const GATE_SECONDS = Object.freeze([10, 12, 15, 20, 25, 30, 40, 45, 50, 60]);

/** After the gate, reopening apps doesn't bounce you for this long. Shorter every step. */
export const PASS_SECONDS = Object.freeze([90, 80, 70, 60, 50, 40, 30, 25, 20, 15]);

/** Brightness (0-1) forced from the dim step on. */
export const DIM_BRIGHTNESS = 0.15;

/** What the phone goes back to when the punishment lifts. */
export const RESTORE_BRIGHTNESS = 0.6;

/** Media volume forced from the loud step on, with silent mode off. */
export const LOUD_VOLUME = 1;

/** The Enforcer shortcut re-applies everything this often while you're in the zone. */
export const REAPPLY_SECONDS = 15;

/** Flashlight blinks per app open from the flash step on. */
export const FLASH_BLINKS = 6;

const at = (list, level) => list[Math.min(level, list.length - 1)];
const pct = (x) => Math.round(x * 100);

/** Nothing on: away from the anchor or no session. Every field says what to put back. */
const OFF = Object.freeze({
  active: false,
  inZone: false,
  locked: false,
  grayscale: false,
  silentOff: false,
  volumePercent: null,
  dim: false,
  brightness: RESTORE_BRIGHTNESS,
  brightnessPercent: pct(RESTORE_BRIGHTNESS),
  bigText: false,
  shame: false,
  flash: false,
  flashBlinks: 0,
  gate: false,
  gateSeconds: 0,
  passSeconds: 0,
  confess: false,
  reapplySeconds: 0,
});

/**
 * @param {ReturnType<typeof import('./engine.js').snapshot>} snap
 * @param {{ passUntil: number | null }} pass
 * @param {number} now
 */
export function phoneEffects(snap, { passUntil }, now) {
  if (snap.status !== 'running' || snap.away) return { ...OFF, inZone: !snap.away && snap.status === 'running' };
  const ladder = ladderFor(snap.quiet === true, Boolean(snap.deposit), 'phone');
  const level = snap.phone.level;
  const on = (id) => ladder.reached(level, id);
  const passed = passUntil !== null && now < passUntil;
  return {
    active: true,
    inZone: true,
    locked: false,
    level,
    levelName: snap.phone.levelName,
    grayscale: on('gray'),
    silentOff: on('loud'),
    volumePercent: on('loud') ? pct(LOUD_VOLUME) : null,
    dim: on('dim'),
    brightness: on('dim') ? DIM_BRIGHTNESS : RESTORE_BRIGHTNESS,
    // Shortcuts' Set Brightness takes a percentage.
    brightnessPercent: pct(on('dim') ? DIM_BRIGHTNESS : RESTORE_BRIGHTNESS),
    bigText: on('text'),
    shame: on('shame'),
    flash: on('flash'),
    flashBlinks: on('flash') ? FLASH_BLINKS : 0,
    // The confession can't be waited out: it gates every open until it's typed, pass or not.
    gate: !passed || snap.confession.owed,
    gateSeconds: at(GATE_SECONDS, level),
    passSeconds: at(PASS_SECONDS, level),
    confess: snap.confession.owed,
    // The Enforcer loop: re-apply this often; 0 (off) tells it to restore and stop.
    reapplySeconds: REAPPLY_SECONDS,
  };
}

/**
 * Opening Settings or Shortcuts inside the zone: that's where you'd undo all of this, so it always
 * bounces to the locked page, with every effect re-applied.
 * @param {ReturnType<typeof phoneEffects>} fx
 */
export const guardEffects = (fx) => (fx.active ? { ...fx, gate: true, locked: true } : fx);

/** iPhone lock-screen size (portrait, 3x). */
const WALLPAPER = Object.freeze({ width: 1179, height: 2556 });
const RED = [215, 38, 46];
const PAPER = [252, 251, 247];
const INK = [20, 40, 75];

/**
 * The shame wallpaper: what your phone time has cost, drawn big enough to read across a table.
 * @param {ReturnType<typeof import('./engine.js').snapshot>} snap
 * @returns {Buffer} PNG
 */
export function shameWallpaper(snap) {
  const c = createCanvas(WALLPAPER.width, WALLPAPER.height, RED);
  const { height: h } = c;
  const line = (str, y, max, color = PAPER) => c.text(str, y, c.fitScale(str, max), color);
  const course = snap.config?.courseName ?? 'CLASS';
  line('YOU ARE AT', h * 0.3, 16);
  line('YOUR ANCHOR', h * 0.36, 16);
  c.fillRect(Math.round(c.width * 0.1), Math.round(h * 0.42), Math.round(c.width * 0.8), 12, PAPER);
  line(money(snap.cost ?? 0), h * 0.5, 40);
  line('OF TUITION BURNED', h * 0.57, 10);
  line(`ON YOUR PHONE ${clock(snap.phone?.totalMs ?? 0)}`, h * 0.64, 8);
  c.fillRect(0, Math.round(h * 0.78), c.width, Math.round(h * 0.08), PAPER);
  line(`GO STUDY ${course}`, h * 0.82, 10, INK);
  return encodePng(c);
}

/** The Home Screen icon: a big paper A on navy, underlined in red pen. iOS rounds the corners. */
export function appIcon(size) {
  const c = createCanvas(size, size, INK);
  const s = Math.max(1, Math.floor(size / 13));
  c.text('A', size * 0.46, s, PAPER);
  const lineW = Math.round(size * 0.5);
  c.fillRect(Math.round((size - lineW) / 2), Math.round(size * 0.78), lineW, Math.max(2, Math.round(size / 28)), RED);
  return encodePng(c);
}
