import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { parseStart, parseLocation, parsePhone, parseDemo, parseConfess } from '../src/validate.js';

describe('parseStart', () => {
  test('accepts a normal session and trims the course name', () => {
    const r = parseStart({ studyMinutes: 25, dollarsPerMinute: 2.5, courseName: '  BUAD 112 ' });
    assert.deepEqual(r, {
      ok: true,
      value: { studyMinutes: 25, dollarsPerMinute: 2.5, tuitionPerYear: null, courseName: 'BUAD 112', quiet: false, deposit: 0, mode: 'mac' },
    });
  });

  test('turns yearly college tuition into what one minute of class costs', () => {
    const r = parseStart({ studyMinutes: 25, tuitionPerYear: 70_000 });
    assert.equal(r.ok, true);
    assert.equal(r.value.tuitionPerYear, 70_000);
    // 15 class hours a week x 15-week semesters x 2 semesters = 27,000 class minutes
    assert.equal(r.value.dollarsPerMinute, 70_000 / 27_000);
  });

  test('rejects tuition that is not a real yearly amount', () => {
    for (const bad of [0, -5, 'lots', 600_000]) {
      const r = parseStart({ studyMinutes: 25, tuitionPerYear: bad });
      assert.equal(r.ok, false, String(bad));
      assert.match(r.error, /tuition/i);
    }
  });

  test('fills defaults for missing optional fields', () => {
    const r = parseStart({ studyMinutes: 10 });
    assert.equal(r.ok, true);
    assert.equal(r.value.courseName, 'BUAD 112');
    assert.equal(r.value.dollarsPerMinute, 2.5);
  });

  for (const bad of [0, 241, 2.5, '25', null]) {
    test(`rejects studyMinutes ${JSON.stringify(bad)}`, () => {
      const r = parseStart({ studyMinutes: bad });
      assert.equal(r.ok, false);
      assert.match(r.error, /minutes/i);
    });
  }

  test('rejects a negative or absurd tuition rate', () => {
    assert.equal(parseStart({ studyMinutes: 5, dollarsPerMinute: -1 }).ok, false);
    assert.equal(parseStart({ studyMinutes: 5, dollarsPerMinute: 1000 }).ok, false);
  });

  test('rejects a course name over 40 characters', () => {
    assert.equal(parseStart({ studyMinutes: 5, courseName: 'x'.repeat(41) }).ok, false);
  });

  test('rejects a non-object body', () => {
    assert.equal(parseStart(null).ok, false);
    assert.equal(parseStart([]).ok, false);
  });
});

describe('parseLocation', () => {
  test('accepts a real fix', () => {
    assert.deepEqual(parseLocation({ lat: 34.02, lng: -118.28, accuracy: 15 }), {
      ok: true,
      value: { lat: 34.02, lng: -118.28, accuracy: 15 },
    });
  });

  test('rejects out-of-range coordinates and negative accuracy', () => {
    assert.equal(parseLocation({ lat: 91, lng: 0, accuracy: 5 }).ok, false);
    assert.equal(parseLocation({ lat: 0, lng: 181, accuracy: 5 }).ok, false);
    assert.equal(parseLocation({ lat: 0, lng: 0, accuracy: -1 }).ok, false);
    assert.equal(parseLocation({ lat: 'a', lng: 0, accuracy: 5 }).ok, false);
  });
});

describe('parsePhone', () => {
  test('needs a boolean', () => {
    assert.deepEqual(parsePhone({ onPhone: true }), { ok: true, value: true });
    assert.equal(parsePhone({ onPhone: 'yes' }).ok, false);
  });
});

describe('parseDemo', () => {
  test('accepts a speed and a simulated distance', () => {
    assert.deepEqual(parseDemo({ speed: 6, simulatedM: 60 }), { ok: true, value: { speed: 6, simulatedM: 60 } });
  });

  test('accepts null to go back to real location, and partial updates', () => {
    assert.deepEqual(parseDemo({ simulatedM: null }), { ok: true, value: { simulatedM: null } });
    assert.deepEqual(parseDemo({ speed: 1 }), { ok: true, value: { speed: 1 } });
  });

  test('rejects unknown speeds and distances out of range', () => {
    assert.equal(parseDemo({ speed: 3.5 }).ok, true, 'anywhere from 1x to 10x');
    assert.equal(parseDemo({ speed: 0.5 }).ok, false);
    assert.equal(parseDemo({ speed: 11 }).ok, false);
    assert.equal(parseDemo({ simulatedM: -1 }).ok, false);
    assert.equal(parseDemo({ simulatedM: 501 }).ok, false);
    assert.equal(parseDemo({}).ok, false);
  });
});

describe('parseConfess', () => {
  test('accepts short text and rejects long or missing text', () => {
    assert.deepEqual(parseConfess({ text: 'hi' }), { ok: true, value: 'hi' });
    assert.equal(parseConfess({ text: 'x'.repeat(201) }).ok, false);
    assert.equal(parseConfess({}).ok, false);
  });
});
