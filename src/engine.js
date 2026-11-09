/**
 * The session rules as pure functions. Every function takes a state and returns a new one;
 * nothing here touches the clock, the disk, or the Mac. `now` is always real wall-clock ms.
 */
import {
  RADIUS_M,
  PENALTY_RATE,
  SNITCH_COUNTDOWN_MS,
  SNITCH_SENT_VISIBLE_MS,
  CONFESSION_PHRASE,
  DEPOSIT_LOSS_EVERY_MS,
  MAX_TICK_GAP_MS,
  ANCHOR_MAX_AGE_MS,
  MAX_ACCURACY_MARGIN_M,
} from './config.js';
import { ladderFor } from './ladder.js';
import { depositSchedule, depositLostAfter } from './deposit.js';
import { distanceMeters } from './geo.js';
import { normalizePhrase } from './phrase.js';

/** The session's ladder: library mode (quiet) has no sound steps and 20 s steps. */
const depositOf = (state) => state.deposit ?? 0;
const modeOf = (state) => (state.config?.mode === 'phone' ? 'phone' : 'mac');
const ladderOf = (state) => ladderFor(state.config?.quiet === true, depositOf(state) > 0, modeOf(state));

/** The punishment clock stops at the top step; the timer you see keeps counting. */
const pressureCap = (ladder) => (ladder.maxLevel + 1) * ladder.levelMs - 1;

/** elapsedMs: time spent on the phone at the anchor since the countdown began (null = not started). */
const NO_SNITCH = Object.freeze({ elapsedMs: null, sentAt: null });

const GRADES = Object.freeze([
  [93, 'A'],
  [90, 'A-'],
  [87, 'B+'],
  [83, 'B'],
  [80, 'B-'],
  [77, 'C+'],
  [73, 'C'],
  [70, 'C-'],
  [60, 'D'],
  [0, 'F'],
]);

/**
 * @param {number} [demoSpeed]
 * @param {{ lat: number, lng: number, accuracy: number } | null} [currentFix]
 */
export function createIdle(demoSpeed = 1, currentFix = null) {
  return {
    status: 'idle',
    config: null,
    demoSpeed,
    startedAt: null,
    lastTickAt: null,
    endedAt: null,
    studyElapsedMs: 0,
    studyTargetMs: 0,
    penaltyMs: 0,
    onPhone: false,
    phoneMs: 0,
    stintMs: 0,
    pressureMs: 0,
    pickups: 0,
    maxLevel: 0,
    location: { anchor: null, current: currentFix, simulatedM: null },
    snitch: NO_SNITCH,
    confessionDone: false,
    deposit: 0,
    endedEarly: false,
    awayMs: 0,
    pickupCounted: false,
  };
}

/**
 * @param {ReturnType<typeof createIdle>} state
 * @param {{ studyMinutes: number, dollarsPerMinute: number, courseName: string }} config
 * @param {number} now
 */
export function startSession(state, config, now) {
  if (state.status === 'running') return state;
  const current = state.location.current;
  const fresh = current && Number.isFinite(current.at) && now - current.at <= ANCHOR_MAX_AGE_MS;
  const anchor = fresh ? { lat: current.lat, lng: current.lng, accuracy: current.accuracy } : null;
  return {
    ...createIdle(state.demoSpeed, current),
    status: 'running',
    config: { ...config },
    startedAt: now,
    lastTickAt: now,
    studyTargetMs: config.studyMinutes * 60_000,
    deposit: config.deposit ?? 0,
    location: { anchor, current, simulatedM: null },
  };
}

/**
 * The snitch countdown is measured in time on the phone at the anchor (real time, not demo time).
 * Off the phone or away it simply pauses, so neither dodging nor a long gap (sleep, restart) can
 * stall it or make it fire early.
 */
function advanceSnitch(snitch, { counts, atSnitch, now, realDt }) {
  if (snitch.sentAt !== null || !counts || !atSnitch) return snitch;
  if (snitch.elapsedMs === null) return { elapsedMs: 0, sentAt: null };
  const elapsedMs = snitch.elapsedMs + realDt;
  return elapsedMs >= SNITCH_COUNTDOWN_MS ? { elapsedMs, sentAt: now } : { elapsedMs, sentAt: null };
}

function finish(state, now, endedEarly) {
  return {
    ...state,
    status: 'done',
    onPhone: false,
    endedAt: now,
    endedEarly,
    snitch: state.snitch.sentAt === null ? NO_SNITCH : state.snitch,
  };
}

/**
 * Advance the clocks to `now`. Demo speed scales session time; the snitch countdown stays real.
 * @param {ReturnType<typeof createIdle>} state
 * @param {number} now
 */
export function tick(state, now) {
  if (state.status !== 'running') return state;
  const realDt = Math.min(MAX_TICK_GAP_MS, Math.max(0, now - state.lastTickAt));
  const dt = realDt * state.demoSpeed;
  const away = isAway(state.location);
  // Away from the anchor the phone is just a phone, and the study timer waits for you to come back.
  const counts = state.onPhone && !away;
  const ladder = ladderOf(state);
  const level = ladder.levelFor(state.pressureMs);
  const added = counts && ladder.reached(level, 'penalty') ? dt * PENALTY_RATE : 0;
  // One clock for the phone timer and the punishment. It only moves while the phone counts, and it
  // never resets during a session: off the phone or away it pauses, back on it resumes.
  const pressureMs = counts ? Math.min(pressureCap(ladder), state.pressureMs + dt) : state.pressureMs;
  const newLevel = ladder.levelFor(pressureMs);
  const next = {
    ...state,
    lastTickAt: now,
    studyElapsedMs: away ? state.studyElapsedMs : state.studyElapsedMs + dt,
    awayMs: away ? (state.awayMs ?? 0) + dt : (state.awayMs ?? 0),
    studyTargetMs: state.studyTargetMs + added,
    penaltyMs: state.penaltyMs + added,
    phoneMs: counts ? state.phoneMs + dt : state.phoneMs,
    stintMs: counts ? state.stintMs + dt : state.stintMs,
    pressureMs,
    maxLevel: counts ? Math.max(state.maxLevel, newLevel) : state.maxLevel,
    snitch: advanceSnitch(state.snitch, { counts, atSnitch: ladder.reached(newLevel, 'snitch'), now, realDt }),
  };
  return next.studyElapsedMs >= next.studyTargetMs ? finish(next, now, false) : next;
}

/**
 * @param {ReturnType<typeof createIdle>} state
 * @param {boolean} onPhone
 * @param {number} now
 */
export function setPhone(state, onPhone, now) {
  if (state.status !== 'running') return state;
  const current = tick(state, now);
  if (current.status !== 'running' || current.onPhone === onPhone) return current;
  if (onPhone) {
    // Away, the phone is free and nothing counts. At the anchor it's a pickup, resuming where you left off.
    if (isAway(current.location)) return { ...current, onPhone: true };
    return { ...current, onPhone: true, pickups: current.pickups + 1, pickupCounted: true };
  }
  // The snitch sends once per session: a running countdown just pauses, a sent one stays sent.
  return {
    ...current,
    onPhone: false,
    pickupCounted: false,
    // The confession pops up once; getting off the phone while it's up ends it for the session too.
    // On the phone the gate page holds it instead, and opening that page closes the app you were in.
    confessionDone: current.confessionDone || (modeOf(current) === 'mac' && confessionUp(current)),
  };
}

/**
 * Record a location fix. The first fix of a running session becomes its anchor.
 * @param {ReturnType<typeof createIdle>} state
 * @param {{ lat: number, lng: number, accuracy: number }} fix
 * @param {number} now
 */
export function updateLocation(state, fix, now) {
  const current = { lat: fix.lat, lng: fix.lng, accuracy: fix.accuracy, at: now };
  const needsAnchor = state.status === 'running' && state.location.anchor === null;
  const anchor = needsAnchor ? { lat: fix.lat, lng: fix.lng, accuracy: fix.accuracy } : state.location.anchor;
  return settleAway(state, { ...state, location: { ...state.location, current, anchor } });
}

/**
 * Presenter control: pretend to be this far from the anchor. `null` goes back to real location.
 * @param {ReturnType<typeof createIdle>} state
 * @param {number | null} meters
 */
export function setSimulatedDistance(state, meters) {
  return settleAway(state, { ...state, location: { ...state.location, simulatedM: meters } });
}

/**
 * Crossing the line. Walking back in while on the phone counts as a pickup (once per time on the
 * phone, so GPS wobbling across the line can't inflate it); the timer and step resume where they were.
 */
function settleAway(before, after) {
  if (after.status !== 'running') return after;
  const wasAway = isAway(before.location);
  const nowAway = isAway(after.location);
  if (!wasAway && nowAway && confessionUp(before)) return { ...after, confessionDone: true };
  if (wasAway && !nowAway && after.onPhone && !after.pickupCounted) {
    return { ...after, pickups: after.pickups + 1, pickupCounted: true };
  }
  return after;
}

/**
 * @param {ReturnType<typeof createIdle>} state
 * @param {number} speed
 */
export function setDemoSpeed(state, speed) {
  return { ...state, demoSpeed: speed };
}

/**
 * @param {ReturnType<typeof createIdle>} state
 * @param {string} text
 * @param {number} now
 */
export function confess(state, text, now) {
  if (state.status !== 'running' || !state.onPhone || isAway(state.location)) return state;
  if (normalizePhrase(text) !== normalizePhrase(CONFESSION_PHRASE)) return state;
  return { ...state, confessionDone: true };
}

/**
 * Phone mode: the confession is typed on the gate page, which is open after the app was closed,
 * so it doesn't need you on the phone. Only counts once its step is reached at the anchor.
 * @param {ReturnType<typeof createIdle>} state
 * @param {string} text
 */
export function confessAtGate(state, text) {
  if (state.status !== 'running' || state.confessionDone || isAway(state.location)) return state;
  const ladder = ladderOf(state);
  if (!ladder.reached(ladder.levelFor(state.pressureMs), 'confess')) return state;
  if (normalizePhrase(text) !== normalizePhrase(CONFESSION_PHRASE)) return state;
  return { ...state, confessionDone: true };
}

function distanceFromAnchor(location) {
  if (location.simulatedM !== null) return location.simulatedM;
  if (!location.anchor || !location.current) return null;
  return distanceMeters(location.anchor, location.current);
}

/** How far you must be before Stop unlocks: the radius plus a GPS margin when the location is real. */
function unlockDistance(location) {
  if (location.simulatedM !== null || !location.anchor || !location.current) return RADIUS_M;
  const accuracy = Math.max(location.anchor.accuracy ?? 0, location.current.accuracy ?? 0);
  return RADIUS_M + Math.min(MAX_ACCURACY_MARGIN_M, accuracy);
}

/** Clearly past the unlock distance. Unknown location counts as at the anchor. */
function isAway(location) {
  const distance = distanceFromAnchor(location);
  return distance !== null && distance > unlockDistance(location);
}

const canStopAt = (state) => state.status === 'running' && isAway(state.location);

/** The confession popup is showing: on the phone at the anchor, at its step, and not done yet. */
function confessionUp(state) {
  const counting = state.status === 'running' && state.onPhone && !isAway(state.location);
  const ladder = ladderOf(state);
  return counting && !state.confessionDone && ladder.reached(ladder.levelFor(state.pressureMs), 'confess');
}

/** Bites taken so far: the first at the deposit step, then one a minute (src/deposit.js has the amounts). */
function depositBites(state) {
  const ladder = ladderOf(state);
  if (!ladder.has('deposit')) return 0;
  const startMs = ladder.stepAt('deposit') * ladder.levelMs;
  if (state.stintMs < startMs) return 0;
  return 1 + Math.floor((state.stintMs - startMs) / DEPOSIT_LOSS_EVERY_MS);
}

/** Dollars taken from the deposit so far, on its exponential schedule. */
const depositLost = (state) => depositLostAfter(depositOf(state), depositBites(state));

/** The balance, or null when no money was put down. */
function depositView(state) {
  const total = depositOf(state);
  if (total <= 0) return null;
  const lost = depositLost(state);
  const schedule = depositSchedule(total);
  const bites = depositBites(state);
  return { total, left: cents(total - lost), lost, nextBite: bites < schedule.length ? schedule[bites] : null };
}

/**
 * End early. Only allowed once you are outside the radius; otherwise the state comes back unchanged.
 * @param {ReturnType<typeof createIdle>} state
 * @param {number} now
 */
export function stopSession(state, now) {
  if (state.status !== 'running') return state;
  const current = tick(state, now);
  if (current.status !== 'running') return current;
  return canStopAt(current) ? finish(current, now, true) : state;
}

/**
 * @param {ReturnType<typeof createIdle>} state
 */
export function resetSession(state) {
  return state.status === 'done' ? createIdle(1, state.location.current) : state;
}

const gradeFor = (score) => GRADES.find(([min]) => score >= min)[1];
const cents = (dollars) => Math.round(dollars * 100) / 100;

function summarize(state) {
  const studied = Math.max(1, state.studyElapsedMs);
  const focused = 1 - Math.min(1, state.phoneMs / studied);
  const completion = state.endedEarly ? Math.min(1, state.studyElapsedMs / state.studyTargetMs) : 1;
  const focusScore = Math.max(0, Math.min(100, Math.round(100 * focused * completion)));
  return {
    focusScore,
    grade: gradeFor(focusScore),
    studiedMs: state.studyElapsedMs,
    targetMs: state.studyTargetMs,
    phoneMs: state.phoneMs,
    pickups: state.pickups,
    penaltyMs: state.penaltyMs,
    cost: cents((state.phoneMs / 60_000) * state.config.dollarsPerMinute),
    maxLevel: state.maxLevel,
    // Clamped to the session's own ladder, so a save whose worst step is past its end can't crash this.
    maxLevelName: state.pickups > 0 ? ladderOf(state).steps[Math.min(state.maxLevel, ladderOf(state).maxLevel)].name : null,
    endedEarly: state.endedEarly,
    awayMs: state.awayMs ?? 0,
    depositLeft: depositView(state)?.left ?? null,
    depositLost: depositOf(state) > 0 ? depositLost(state) : null,
    quiet: ladderOf(state).quiet,
    courseName: state.config.courseName,
  };
}

function snitchView(snitch, now) {
  if (snitch.sentAt !== null) return now - snitch.sentAt < SNITCH_SENT_VISIBLE_MS ? { phase: 'sent' } : null;
  if (snitch.elapsedMs === null) return null;
  const left = Math.max(0, SNITCH_COUNTDOWN_MS - snitch.elapsedMs);
  return { phase: 'countdown', secondsLeft: Math.ceil(left / 1000) };
}

/**
 * Everything the page, the overlay, and the effects planner need, derived from state.
 * @param {ReturnType<typeof createIdle>} state
 * @param {number} now
 */
export function snapshot(state, now) {
  const ladder = ladderOf(state);
  const level = ladder.levelFor(state.pressureMs);
  const distance = distanceFromAnchor(state.location);
  const unlockAtM = unlockDistance(state.location);
  const running = state.status === 'running';
  const away = running && isAway(state.location);
  const phoneCounts = state.onPhone && !away;
  const paused = running && !phoneCounts && state.stintMs > 0;
  const rate = state.config?.dollarsPerMinute ?? 0;
  const atTop = level < ladder.maxLevel ? (level + 1) * ladder.levelMs - state.pressureMs : null;
  return {
    status: state.status,
    config: state.config,
    demoSpeed: state.demoSpeed,
    quiet: ladder.quiet,
    mode: modeOf(state),
    study: {
      elapsedMs: state.studyElapsedMs,
      targetMs: state.studyTargetMs,
      remainingMs: Math.max(0, state.studyTargetMs - state.studyElapsedMs),
      penaltyMs: state.penaltyMs,
    },
    phone: {
      onPhone: state.onPhone,
      stintMs: state.stintMs,
      totalMs: state.phoneMs,
      pickups: state.pickups,
      level,
      levelId: ladder.steps[level].id,
      levelName: ladder.steps[level].name,
      restingLevel: paused ? level : null,
      maxLevel: ladder.maxLevel,
      nextLevelInMs: phoneCounts && atTop !== null ? atTop / state.demoSpeed : null,
    },
    cost: cents((state.phoneMs / 60_000) * rate),
    location: {
      hasAnchor: state.location.anchor !== null,
      distanceM: distance,
      accuracyM: state.location.current?.accuracy ?? null,
      simulated: state.location.simulatedM !== null,
      inside: distance === null || distance <= unlockAtM,
      radiusM: RADIUS_M,
      unlockAtM,
    },
    canStop: canStopAt(state),
    away,
    deposit: depositView(state),
    snitch: running && phoneCounts ? snitchView(state.snitch, now) : null,
    confession: {
      required: confessionUp(state),
      // Phone mode: the step is reached and not typed yet, whether or not you're in an app right now.
      owed: running && !away && !state.confessionDone && ladder.reached(level, 'confess'),
      phrase: CONFESSION_PHRASE,
    },
    summary: state.status === 'done' ? summarize(state) : null,
  };
}
