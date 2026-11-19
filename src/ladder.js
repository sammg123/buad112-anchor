import { LEVEL_MS, QUIET_LEVEL_MS } from './config.js';

/**
 * Every step, in order. Each step keeps the ones before it. `sound: true` steps are cut in library mode.
 * @type {ReadonlyArray<{ id: string, name: string, note: string, sound: boolean }>}
 */
const ALL_STEPS = Object.freeze(
  [
    { id: 'clock', name: 'Clock', note: 'A phone timer follows you into every app', sound: false },
    { id: 'pulse', name: 'Red pulse', note: 'The whole screen pulses red', sound: false },
    { id: 'tick', name: 'Ticking', note: 'A clock ticks, faster every step', sound: true },
    { id: 'blur', name: 'Blur', note: 'The screen blurs in waves, a few clear seconds between', sound: false },
    { id: 'shake', name: 'Shake', note: 'Every blur wave shakes the whole screen', sound: false },
    { id: 'cost', name: 'Receipt', note: 'Tuition burned, counted live', sound: false },
    { id: 'voice', name: 'Voice', note: 'Your Mac starts talking to you', sound: true },
    { id: 'notify', name: 'Notifications', note: 'A banner every 10 seconds', sound: false },
    { id: 'penalty', name: 'Penalty', note: 'Each phone second adds 2 to studying', sound: false },
    { id: 'snitch', name: 'Snitch', note: 'Texting your study group', sound: false },
    { id: 'siren', name: 'Siren', note: 'Siren, volume forced up', sound: true },
    { id: 'confess', name: 'Confession', note: 'Type it to make the popup leave (once)', sound: false },
    { id: 'deposit', name: 'Deposit', note: 'Your deposit drains, a bigger bite every minute', sound: false },
  ].map((step) => Object.freeze(step)),
);

/**
 * A ladder: its steps, how long each lasts, and helpers that answer "is this step on yet?".
 * Steps a ladder doesn't have (the sound steps in library mode) are never reached.
 */
function buildLadder(steps, levelMs, quiet) {
  const ids = steps.map((step) => step.id);
  const maxLevel = steps.length - 1;
  const stepAt = (id) => ids.indexOf(id);
  return Object.freeze({
    quiet,
    steps,
    levelMs,
    maxLevel,
    stepAt,
    has: (id) => stepAt(id) !== -1,
    /** @param {number} pressureMs */
    levelFor: (pressureMs) => Math.min(maxLevel, Math.floor(Math.max(0, pressureMs) / levelMs)),
    /** @param {number} level @param {string} id */
    reached: (level, id) => stepAt(id) !== -1 && level >= stepAt(id),
  });
}

/**
 * Phone mode: the punishment lands on the phone itself, through iOS Shortcuts automations
 * (see docs/shortcuts.md). Every app open inside the zone bounces to Anchor's gate page.
 */
const PHONE_STEPS = Object.freeze(
  [
    { id: 'gate', name: 'Gate', note: 'Opening an app bounces you to Anchor and makes you wait', sound: false },
    { id: 'gray', name: 'Grayscale', note: 'The whole phone goes grey', sound: false },
    { id: 'loud', name: 'Loud', note: 'Silent mode off, volume all the way up, alarm and voice', sound: true },
    { id: 'dim', name: 'Dim', note: 'Brightness drops to 15%', sound: false },
    { id: 'cost', name: 'Receipt', note: 'Tuition burned, counted live on the gate', sound: false },
    { id: 'text', name: 'Huge text', note: 'Text size maxed out, feeds are a slog', sound: false },
    { id: 'flash', name: 'Flashing', note: 'The whole phone flashes, in every app, over and over', sound: false },
    { id: 'confess', name: 'Confession', note: 'Type it to get past the gate (once)', sound: false },
    { id: 'deposit', name: 'Deposit', note: 'Your deposit drains, a bigger bite every minute', sound: false },
  ].map((step) => Object.freeze(step)),
);

const keep = (pred) => Object.freeze(ALL_STEPS.filter(pred));
const notDeposit = (step) => step.id !== 'deposit';

/** Normal mode: every step, one every 15 s. */
export const NORMAL_LADDER = buildLadder(ALL_STEPS, LEVEL_MS, false);

/** Library mode: no sound steps, one every 20 s, so the deposit still lands at 3:00. */
export const QUIET_LADDER = buildLadder(keep((step) => !step.sound), QUIET_LEVEL_MS, true);

/** No money put down: the same ladders without the deposit step. */
const NORMAL_NO_DEPOSIT = buildLadder(keep(notDeposit), LEVEL_MS, false);
const QUIET_NO_DEPOSIT = buildLadder(keep((step) => !step.sound && notDeposit(step)), QUIET_LEVEL_MS, true);

/** Phone mode: one step every 15 s, so the deposit lands at 2:15 on the phone. */
export const PHONE_LADDER = buildLadder(PHONE_STEPS, LEVEL_MS, false);
const PHONE_NO_DEPOSIT = buildLadder(Object.freeze(PHONE_STEPS.filter(notDeposit)), LEVEL_MS, false);

/** Library mode on the phone: the Loud step is cut, so nothing ever makes a sound. */
const phoneKeep = (pred) => Object.freeze(PHONE_STEPS.filter(pred));
const PHONE_QUIET = buildLadder(phoneKeep((step) => !step.sound), LEVEL_MS, true);
const PHONE_QUIET_NO_DEPOSIT = buildLadder(phoneKeep((step) => !step.sound && notDeposit(step)), LEVEL_MS, true);

/**
 * @param {boolean} quiet library mode
 * @param {boolean} [hasDeposit] whether money was put down
 * @param {'mac' | 'phone'} [mode] where the punishment lands
 */
export function ladderFor(quiet, hasDeposit = true, mode = 'mac') {
  if (mode === 'phone' && quiet) return hasDeposit ? PHONE_QUIET : PHONE_QUIET_NO_DEPOSIT;
  if (mode === 'phone') return hasDeposit ? PHONE_LADDER : PHONE_NO_DEPOSIT;
  if (quiet) return hasDeposit ? QUIET_LADDER : QUIET_NO_DEPOSIT;
  return hasDeposit ? NORMAL_LADDER : NORMAL_NO_DEPOSIT;
}

/** Every ladder by name, for the pages' rubrics. */
export const LADDERS = Object.freeze({
  normal: NORMAL_LADDER,
  quiet: QUIET_LADDER,
  'normal-nodeposit': NORMAL_NO_DEPOSIT,
  'quiet-nodeposit': QUIET_NO_DEPOSIT,
  phone: PHONE_LADDER,
  'phone-nodeposit': PHONE_NO_DEPOSIT,
  'phone-quiet': PHONE_QUIET,
  'phone-quiet-nodeposit': PHONE_QUIET_NO_DEPOSIT,
});

// Normal-mode shortcuts, used where the mode doesn't matter or by tests.
export const LADDER = NORMAL_LADDER.steps;
export const MAX_LEVEL = NORMAL_LADDER.maxLevel;

/**
 * @param {string} id
 * @returns {number} the step's index in the normal ladder
 */
export function levelIndexOf(id) {
  const index = NORMAL_LADDER.stepAt(id);
  if (index === -1) throw new Error(`Unknown ladder step: ${id}`);
  return index;
}

/** @param {number} pressureMs */
export const levelForPressure = (pressureMs) => NORMAL_LADDER.levelFor(pressureMs);

/** Screen vibration in points: starts violent, gets worse, stays inside the overlay's 60-point bleed. */
const SHAKE_START_PT = 18;
const SHAKE_STEP_PT = 3;
const SHAKE_MAX_PT = 36;

/** Steps past the one that switched an effect on, or -1 when it is not on (or not in this ladder). */
const stepsPast = (level, start) => (start >= 0 && level >= start ? level - start : -1);

/**
 * How hard each continuous effect hits at a given level. Level -1 means off the phone.
 * The pulse period never drops below 1.2 s, far under the 3 flashes/second seizure threshold.
 * @param {number} level
 * @param {ReturnType<typeof buildLadder>} [ladder]
 */
export function intensity(level, ladder = NORMAL_LADDER) {
  const pulse = stepsPast(level, ladder.stepAt('pulse'));
  const tick = stepsPast(level, ladder.stepAt('tick'));
  const blur = stepsPast(level, ladder.stepAt('blur'));
  const shake = stepsPast(level, ladder.stepAt('shake'));
  const shakeAmp = shake < 0 ? 0 : Math.min(SHAKE_MAX_PT, SHAKE_START_PT + SHAKE_STEP_PT * shake);
  return Object.freeze({
    pulseAlpha: pulse < 0 ? 0 : Math.min(0.42, 0.16 + 0.026 * pulse),
    pulsePeriodMs: pulse < 0 ? null : Math.max(1200, 3000 - 180 * pulse),
    blur: blur < 0 ? 0 : Math.min(1, 0.85 + 0.05 * blur),
    shakeAmp,
    shake: shakeAmp > 0,
    tickIntervalMs: tick < 0 ? null : Math.max(280, Math.round(1000 * 0.85 ** tick)),
  });
}
