/**
 * Pure planning for the Mac-wide effects. `planEffects` decides which one-shot actions are due
 * (tick, speak, notify, siren, volume); `overlayFrame` describes what the native overlay draws.
 * Executing them is mac.js and overlay.js's job.
 */
import { intensity, ladderFor } from './ladder.js';
import { clock, money } from './format.js';
import { voiceLine, notifyLine, snitchMessage } from './lines.js';

export const VOICE_EVERY_MS = 15_000;
export const NOTIFY_EVERY_MS = 10_000;

/** Output volume (0-100) forced while sound is part of the punishment. */
export const VOLUME_FLOOR = Object.freeze({ tick: 35, siren: 70 });

/** While a floor is on, push it again this often in case it was turned down or muted. */
export const VOLUME_REASSERT_MS = 5_000;

const ladderOfSnap = (snap) => ladderFor(snap.quiet === true, Boolean(snap.deposit), snap.mode);

/**
 * Blur comes in waves so the screen stays usable between them. The cycle length is fixed, so the rhythm
 * never jumps when the step changes; each step past the blur step just makes more of it blurred, leaving
 * a clear gap of at least 1.5 s.
 */
export const BLUR_WAVE = Object.freeze({
  periodMs: 5500,
  onStartMs: 2500,
  onStepMs: 500,
  onMaxMs: 4000,
});

/**
 * @param {number} level
 * @param {ReturnType<typeof ladderFor>} [ladder]
 * @returns {{ onMs: number, offMs: number } | null} null before the blur step
 */
export function blurWave(level, ladder = ladderFor(false)) {
  if (!ladder.reached(level, 'blur')) return null;
  const steps = level - ladder.stepAt('blur');
  const onMs = Math.min(BLUR_WAVE.onMaxMs, BLUR_WAVE.onStartMs + BLUR_WAVE.onStepMs * steps);
  return Object.freeze({ onMs, offMs: BLUR_WAVE.periodMs - onMs });
}

/** Real-time phase, so waves keep a human rhythm even at 6x demo speed. */
function inWave(wave, now) {
  if (!wave) return false;
  const period = wave.onMs + wave.offMs;
  return ((now % period) + period) % period < wave.onMs;
}

export function createPlan() {
  return Object.freeze({
    lastTickAt: null,
    lastVoiceAt: null,
    lastNotifyAt: null,
    voiceIndex: 0,
    notifyIndex: 0,
    siren: false,
    volumeFloor: null,
    lastVolumeAt: null,
  });
}

/** Effects only fire on the phone at the anchor; away from it the phone is just a phone. */
const isActive = (snap) => snap.status === 'running' && snap.phone.onPhone && !snap.away;
const isDue = (last, every, now) => last === null || now - last >= every;

/**
 * A repeating action that runs while `on`, on its own interval, and restarts immediately next time.
 * @returns {{ fire: boolean, last: number | null }}
 */
function repeating(on, last, every, now) {
  if (!on) return { fire: false, last: null };
  return isDue(last, every, now) ? { fire: true, last: now } : { fire: false, last };
}

/**
 * @param {ReturnType<typeof createPlan>} plan
 * @param {ReturnType<typeof import('./engine.js').snapshot>} snap
 * @param {number} now real ms
 * @returns {{ plan: ReturnType<typeof createPlan>, actions: Array<Record<string, unknown>> }}
 */
export function planEffects(plan, snap, now) {
  const active = isActive(snap);
  const ladder = ladderOfSnap(snap);
  const level = active ? snap.phone.level : -1;
  const fx = intensity(level, ladder);

  // Library mode has no tick, voice, or siren steps, so none of these ever fire there.
  const tick = repeating(fx.tickIntervalMs !== null, plan.lastTickAt, fx.tickIntervalMs, now);
  const voice = repeating(ladder.reached(level, 'voice'), plan.lastVoiceAt, VOICE_EVERY_MS, now);
  const notify = repeating(ladder.reached(level, 'notify'), plan.lastNotifyAt, NOTIFY_EVERY_MS, now);
  const siren = ladder.reached(level, 'siren');
  const volumeFloor = siren ? VOLUME_FLOOR.siren : fx.tickIntervalMs !== null ? VOLUME_FLOOR.tick : null;
  const reassert = volumeFloor !== null && isDue(plan.lastVolumeAt, VOLUME_REASSERT_MS, now);
  const pushVolume = volumeFloor !== plan.volumeFloor || reassert;

  // Siren first: stopping it is instant, while restoring the volume takes a moment.
  const actions = [
    ...(siren !== plan.siren ? [{ type: 'siren', on: siren }] : []),
    ...(pushVolume ? [{ type: 'volume', floor: volumeFloor }] : []),
    ...(tick.fire ? [{ type: 'tick' }] : []),
    ...(voice.fire ? [{ type: 'say', text: voiceLine(plan.voiceIndex, snap) }] : []),
    ...(notify.fire ? [{ type: 'notify', silent: ladder.quiet, ...notifyLine(plan.notifyIndex, snap) }] : []),
  ];

  return {
    actions,
    plan: Object.freeze({
      lastTickAt: tick.last,
      lastVoiceAt: voice.last,
      lastNotifyAt: notify.last,
      voiceIndex: plan.voiceIndex + (voice.fire ? 1 : 0),
      notifyIndex: plan.notifyIndex + (notify.fire ? 1 : 0),
      siren,
      volumeFloor,
      lastVolumeAt: volumeFloor === null ? null : pushVolume ? now : plan.lastVolumeAt,
    }),
  };
}

const INACTIVE_FRAME = Object.freeze({
  t: 'frame',
  active: false,
  phoneText: null,
  levelNumber: null,
  levelCount: null,
  levelName: null,
  costText: null,
  penaltyText: null,
  pulseAlpha: 0,
  pulsePeriodMs: null,
  blur: 0,
  shake: false,
  shakeAmp: 0,
  shakeReady: false,
  depositLeft: null,
  depositTotal: null,
  snitchPhase: null,
  snitchSeconds: null,
  snitchMessage: null,
  confession: null,
});

/**
 * What the native overlay should draw right now. Flat on purpose so Swift can decode it directly.
 * Blur and shake only show inside a blur wave; `shakeReady` keeps the overlay's snapshots warm between waves.
 * @param {ReturnType<typeof import('./engine.js').snapshot>} snap
 * @param {number} [now] real ms, for the blur wave phase
 */
export function overlayFrame(snap, now = Date.now()) {
  if (!isActive(snap)) return INACTIVE_FRAME;
  const { level } = snap.phone;
  const ladder = ladderOfSnap(snap);
  const fx = intensity(level, ladder);
  const waveOn = inWave(blurWave(level, ladder), now);
  return Object.freeze({
    ...INACTIVE_FRAME,
    active: true,
    phoneText: clock(snap.phone.stintMs),
    levelNumber: level + 1,
    levelCount: snap.phone.maxLevel + 1,
    levelName: snap.phone.levelName,
    costText: ladder.reached(level, 'cost') ? `${money(snap.cost)} of tuition` : null,
    penaltyText: ladder.reached(level, 'penalty') ? `+${clock(snap.study.penaltyMs)} added to studying` : null,
    pulseAlpha: fx.pulseAlpha,
    pulsePeriodMs: fx.pulsePeriodMs,
    blur: waveOn ? fx.blur : 0,
    shake: waveOn && fx.shake,
    shakeAmp: waveOn ? fx.shakeAmp : 0,
    shakeReady: fx.shakeAmp > 0,
    depositLeft: snap.deposit?.left ?? null,
    depositTotal: snap.deposit?.total ?? null,
    snitchPhase: snap.snitch?.phase ?? null,
    snitchSeconds: snap.snitch?.phase === 'countdown' ? snap.snitch.secondsLeft : null,
    snitchMessage: snap.snitch ? snitchMessage(snap) : null,
    confession: snap.confession.required ? snap.confession.phrase : null,
  });
}
