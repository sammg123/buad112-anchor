/**
 * Input validation for everything that crosses the HTTP boundary.
 * Each parser returns `{ ok: true, value }` or `{ ok: false, error }` with a message fit to show a person.
 */
import { DEFAULTS, LIMITS, DEMO_SPEED_MIN, DEMO_SPEED_MAX, CLASS_MINUTES_PER_YEAR } from './config.js';
import { DEPOSIT_MAX, isValidDeposit } from './deposit.js';

const ok = (value) => ({ ok: true, value });
const fail = (error) => ({ ok: false, error });

const isPlainObject = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
const isFiniteNumber = (v) => typeof v === 'number' && Number.isFinite(v);
const inRange = (v, min, max) => isFiniteNumber(v) && v >= min && v <= max;

/** @param {unknown} body */
export function parseStart(body) {
  if (!isPlainObject(body)) return fail('Send the session settings as a JSON object.');
  const { studyMinutes, tuitionPerYear, courseName = DEFAULTS.courseName } = body;
  const hasTuition = tuitionPerYear !== undefined && tuitionPerYear !== null;
  if (hasTuition && !inRange(tuitionPerYear, 1, LIMITS.maxTuitionPerYear)) {
    return fail('College tuition must be a yearly amount from $1 to $500,000.');
  }
  const dollarsPerMinute = hasTuition
    ? tuitionPerYear / CLASS_MINUTES_PER_YEAR
    : (body.dollarsPerMinute ?? DEFAULTS.dollarsPerMinute);

  const minutesOk =
    Number.isInteger(studyMinutes) && studyMinutes >= LIMITS.minStudyMinutes && studyMinutes <= LIMITS.maxStudyMinutes;
  if (!minutesOk) {
    return fail(`Study minutes must be a whole number from ${LIMITS.minStudyMinutes} to ${LIMITS.maxStudyMinutes}.`);
  }
  if (!inRange(dollarsPerMinute, 0, LIMITS.maxDollarsPerMinute)) {
    return fail(`Tuition per minute must be between $0 and $${LIMITS.maxDollarsPerMinute}.`);
  }
  // Strip control, zero-width, and direction-override characters: the name is drawn over every app.
  const cleaned = typeof courseName === 'string' ? courseName.replace(/\p{C}/gu, '').trim() : null;
  if (cleaned === null || cleaned.length > LIMITS.maxCourseName) {
    return fail(`Course name must be ${LIMITS.maxCourseName} characters or fewer.`);
  }
  const name = cleaned || DEFAULTS.courseName;
  const quiet = body.quiet ?? false;
  if (typeof quiet !== 'boolean') return fail('Library mode must be on or off.');
  const mode = body.mode ?? 'mac';
  if (mode !== 'mac' && mode !== 'phone') return fail('Mode must be "mac" or "phone".');
  // Leaving the deposit empty means no money down and no deposit step.
  const deposit = body.deposit ?? 0;
  if (!isValidDeposit(deposit)) {
    return fail(`Deposit must be an amount from $0 to $${DEPOSIT_MAX.toLocaleString('en-US')}, or left empty.`);
  }
  return ok({
    studyMinutes,
    dollarsPerMinute,
    tuitionPerYear: hasTuition ? tuitionPerYear : null,
    courseName: name,
    quiet,
    deposit,
    mode,
  });
}

/**
 * What an iOS Shortcut sends when an app opens or closes: the app's name and, optionally, where you are.
 * @param {unknown} body
 */
export function parsePhoneEvent(body) {
  if (!isPlainObject(body)) return fail('Send the app event as a JSON object.');
  const app = typeof body.app === 'string' ? body.app.replace(/\p{C}/gu, '').trim().slice(0, 40) : '';
  if (body.lat === undefined && body.lng === undefined) return ok({ app, fix: null });
  const fix = parseLocation({ lat: body.lat, lng: body.lng, accuracy: body.accuracy ?? 30 });
  return fix.ok ? ok({ app, fix: fix.value }) : fix;
}

/** @param {unknown} body */
export function parseGatePass(body) {
  if (!isPlainObject(body)) return fail('Send the gate pass as a JSON object.');
  if (body.text !== undefined && typeof body.text !== 'string') return fail('Type the sentence to confess.');
  if ((body.text ?? '').length > LIMITS.maxConfession) return fail('That is longer than the sentence.');
  return ok(body.text ?? '');
}

/** @param {unknown} body */
export function parseLocation(body) {
  if (!isPlainObject(body)) return fail('Send the location as a JSON object.');
  const { lat, lng, accuracy } = body;
  if (!inRange(lat, -90, 90) || !inRange(lng, -180, 180)) return fail('That location is not a real coordinate.');
  if (!inRange(accuracy, 0, LIMITS.maxAccuracyM)) return fail('Location accuracy must be a positive number of meters.');
  return ok({ lat, lng, accuracy });
}

/** @param {unknown} body */
export function parsePhone(body) {
  if (!isPlainObject(body) || typeof body.onPhone !== 'boolean') return fail('onPhone must be true or false.');
  return ok(body.onPhone);
}

/** @param {unknown} body */
export function parseDemo(body) {
  if (!isPlainObject(body)) return fail('Send the demo settings as a JSON object.');
  const hasSpeed = 'speed' in body;
  const hasDistance = 'simulatedM' in body;
  if (!hasSpeed && !hasDistance) return fail('Send a demo speed, a simulated distance, or both.');
  if (hasSpeed && !inRange(body.speed, DEMO_SPEED_MIN, DEMO_SPEED_MAX)) {
    return fail(`Demo speed must be from ${DEMO_SPEED_MIN}x to ${DEMO_SPEED_MAX}x.`);
  }
  if (hasDistance && body.simulatedM !== null && !inRange(body.simulatedM, 0, LIMITS.maxSimulatedM)) {
    return fail(`Simulated distance must be from 0 to ${LIMITS.maxSimulatedM} meters.`);
  }
  return ok({
    ...(hasSpeed ? { speed: body.speed } : {}),
    ...(hasDistance ? { simulatedM: body.simulatedM } : {}),
  });
}

/** @param {unknown} body */
export function parseConfess(body) {
  if (!isPlainObject(body) || typeof body.text !== 'string') return fail('Type the sentence to confess.');
  if (body.text.length > LIMITS.maxConfession) return fail('That is longer than the sentence.');
  return ok(body.text);
}
