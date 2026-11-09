/**
 * Owns the one live session. Applies actions through the pure engine, then plans and runs the
 * Mac-wide effects, feeds the overlay, persists, and broadcasts snapshots to the page.
 */
import {
  createIdle,
  startSession,
  tick,
  setPhone,
  updateLocation,
  setSimulatedDistance,
  setDemoSpeed,
  confess,
  confessAtGate,
  stopSession,
  resetSession,
  snapshot,
} from './engine.js';
import { createPlan, planEffects, overlayFrame } from './effects.js';
import { phoneEffects, guardEffects, shameWallpaper } from './phone.js';
import { RADIUS_M } from './config.js';
import { createLogger } from './log.js';

const ok = (data) => ({ ok: true, data });
const conflict = (error) => ({ ok: false, status: 409, error });

/**
 * @param {{
 *   now?: () => number,
 *   effects: { run: (action: object) => void, stopAll: () => void },
 *   overlay?: { send: (frame: object) => void, stop: () => void, isAvailable: () => boolean } | null,
 *   persist?: { save: (state: object) => void, flush?: () => void } | null,
 *   initialState?: object,
 *   log?: ReturnType<typeof createLogger>,
 * }} deps
 */
export function createApp({ now = Date.now, effects, overlay = null, persist = null, initialState, log = createLogger() }) {
  let state = initialState ?? createIdle();
  let plan = createPlan();
  // Phone mode: after the gate, app opens don't bounce until this time. Not saved; a restart means a gate.
  let passUntil = null;
  const listeners = new Set();

  /** What the page gets: the snapshot plus the overlay frame, which the page draws itself if the overlay is down. */
  const view = (snap) => ({
    ...snap,
    overlayAvailable: overlay ? overlay.isAvailable() : false,
    fx: overlayFrame(snap, now()),
    phoneFx: phoneEffects(snap, { passUntil }, now()),
  });

  function runAction(action) {
    try {
      effects.run(action);
    } catch (error) {
      log.error(`Effect "${action.type}" failed`, error);
    }
  }

  function broadcast(snap) {
    listeners.forEach((listener) => {
      try {
        listener(snap);
      } catch (error) {
        log.error('A live-update listener failed', error);
      }
    });
  }

  /** One loop iteration: advance time, fire due effects, redraw the overlay, publish. */
  function step() {
    const t = now();
    state = tick(state, t);
    const snap = snapshot(state, t);
    const planned = planEffects(plan, snap, t);
    plan = planned.plan;
    planned.actions.forEach(runAction);
    overlay?.send(overlayFrame(snap, t));
    persist?.save(state);
    const published = view(snap);
    broadcast(published);
    return published;
  }

  /** Apply a pure transition at the current time, then run the loop once so effects react instantly. */
  function apply(transition) {
    state = transition(tick(state, now()), now());
    return ok(step());
  }

  const requireRunning = () => (state.status === 'running' ? null : conflict('Start a study session first.'));

  return {
    step,
    state: () => view(snapshot(state, now())),

    start(config) {
      if (state.status === 'running') return conflict('A study session is already running.');
      passUntil = null;
      return apply((s, t) => startSession(s.status === 'done' ? resetSession(s) : s, config, t));
    },

    phone(onPhone) {
      return requireRunning() ?? apply((s, t) => setPhone(s, onPhone, t));
    },

    location(fix) {
      return apply((s, t) => updateLocation(s, fix, t));
    },

    demo({ speed, simulatedM }) {
      return apply((s) => {
        const sped = speed === undefined ? s : setDemoSpeed(s, speed);
        return simulatedM === undefined ? sped : setSimulatedDistance(sped, simulatedM);
      });
    },

    confess(text) {
      return requireRunning() ?? apply((s, t) => confess(s, text, t));
    },

    stop() {
      const notRunning = requireRunning();
      if (notRunning) return notRunning;
      const t = now();
      const current = tick(state, t);
      if (current.status === 'running' && !snapshot(current, t).canStop) {
        return conflict(`Stop is locked within ${RADIUS_M} m of where you started. Walk away to unlock it.`);
      }
      return apply((s, at) => stopSession(s, at));
    },

    /** iOS Shortcut: an app opened. Updates location if sent, starts the phone clock, says what to do. */
    phoneOpened({ fix }) {
      if (fix) this.location(fix);
      if (state.status === 'running') this.phone(true);
      return ok(this.phoneNow());
    },

    /** iOS Shortcut: the app closed. Stops the phone clock and lifts the phone-wide effects. */
    phoneClosed({ fix }) {
      if (fix) this.location(fix);
      if (state.status === 'running') this.phone(false);
      return ok(this.phoneNow());
    },

    /** iOS Shortcut: Settings or Shortcuts opened. Not phone time; inside the zone it's always locked. */
    phoneGuarded({ fix }) {
      if (fix) this.location(fix);
      return ok(guardEffects(this.phoneNow()));
    },

    /** The shame wallpaper PNG for right now. */
    wallpaper() {
      const t = now();
      return shameWallpaper(snapshot(tick(state, t), t));
    },

    /** The gate page's Continue button: confession if it's owed, then a pass that grows shorter every step. */
    passGate(text) {
      const notRunning = requireRunning();
      if (notRunning) return notRunning;
      const t = now();
      state = confessAtGate(tick(state, t), text);
      const fx = this.phoneNow();
      if (fx.confess) return conflict('Type the sentence exactly to get past the gate.');
      passUntil = t + (fx.passSeconds ?? 0) * 1000;
      return ok(this.phoneNow());
    },

    phoneNow() {
      const t = now();
      return phoneEffects(snapshot(state, t), { passUntil }, t);
    },

    reset() {
      if (state.status === 'running') return conflict('A running session cannot be reset. Finish it or walk away.');
      passUntil = null;
      return apply((s) => resetSession(s));
    },

    /** Events from the native overlay: the floating off button and the confession box. */
    handleOverlayEvent(event) {
      if (event?.e === 'off') return this.phone(false);
      if (event?.e === 'confess' && typeof event.text === 'string') return this.confess(event.text.slice(0, 200));
      return null;
    },

    subscribe(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },

    shutdown() {
      effects.stopAll();
      overlay?.stop();
      persist?.flush?.();
    },
  };
}
