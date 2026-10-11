#!/usr/bin/env node
/* Golden fixtures for the native member app's Dart domain port.
 *
 *   node member-app/scripts/gen-fixtures.mjs
 *
 * openGym's own functions answer a fixed, seeded set of questions; test/member/domain_test.dart
 * asks the Dart port the same ones and requires identical answers. Regenerate after changing
 * either side on purpose. */
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const lib = join(here, '..', 'opengym', 'frontend', 'src', 'lib');
const { estimate1RM, bestSetOf, FORMULAS, e1rmSeries, best1RM, is1RMRecord } = await import(join(lib, 'onerm.js'));
const { bestWeightForEntry, lastEntryFor, bestWeightFor, workoutVolume, setsDone, setsDoneActive, setUnitsTotal } = await import(join(lib, 'history.js'));
const { sessionEnd, buildCompletedWorkout } = await import(join(lib, 'finish-workout.js'));
const { CATALOGUE, isAssisted, EXIDX } = await import(join(lib, 'exercises.js'));
const { readableIn, inkOnBoth, mix, contrast, isGrey } = await import(join(lib, 'accent.js'));
const { convertStateUnit, convertWeight, convertBodyWeight } = await import(join(lib, 'units.js'));
const { workoutDay, workoutDuration, stepEffort, capEffort } = await import(join(lib, 'history.js'));
const { accessoriesOf, eqAvailable, ALL_EQUIPMENT } = await import(join(lib, 'equipment.js'));
const { isoOf, weekDayOffset } = await import(join(lib, 'format.js'));

// small deterministic PRNG so fixtures are stable
let seed = 20261010;
const rnd = () => { seed = (seed * 1664525 + 1013904223) >>> 0; return seed / 2 ** 32; };
const pick = (a) => a[Math.floor(rnd() * a.length)];
const round1 = (n) => Math.round(n * 10) / 10;

const assistedId = CATALOGUE.find((e) => isAssisted(e.id))?.id;
const plainIds = CATALOGUE.filter((e) => !isAssisted(e.id) && e.bp !== 'cardio').slice(0, 12).map((e) => e.id);

// 1. one-rep-max estimates
const oneRm = [];
for (const formula of [...Object.keys(FORMULAS), 'weighted']) {
  for (const w of [0, -5, 20, 60, 100, 142.5]) {
    for (const r of [0, 1, 2, 3, 5, 8, 10, 12, 13, 15, 16, 20]) {
      for (const rir of [null, 0, 1, 2, 4]) oneRm.push({ formula, w, r, rir, out: estimate1RM(w, r, formula, rir) });
    }
  }
}

// 2. random entries: best set, best weight
const mkSet = (done = rnd() > 0.2) => ({ w: round1(20 + rnd() * 100), r: 1 + Math.floor(rnd() * 14), done, ...(rnd() > 0.7 ? { phase: 'warmup' } : {}), ...(rnd() > 0.8 ? { rir: Math.floor(rnd() * 4) } : {}) });
const entries = [];
for (let i = 0; i < 60; i++) {
  const id = i % 10 === 0 && assistedId ? assistedId : pick(plainIds);
  const entry = { id, sets: Array.from({ length: 1 + Math.floor(rnd() * 5) }, () => mkSet()) };
  if (i % 7 === 0) entry.sets.push({ sides: { L: { w: 30, r: 8, done: true }, R: { w: 30, r: 7, done: rnd() > 0.5 } }, w: 30, r: 8, done: true });
  entries.push({ entry, best: bestSetOf(entry), bestW: bestWeightForEntry(entry) });
}

// 3. session end (forgotten-session rule)
const sessionEnds = [];
for (let i = 0; i < 30; i++) {
  const base = 1_760_000_000_000;
  let at = base;
  const sets = Array.from({ length: 2 + Math.floor(rnd() * 8) }, () => {
    at += Math.floor(rnd() * 40 * 60000);
    return { w: 50, r: 5, done: rnd() > 0.1, at, ...(rnd() > 0.9 ? { min: 10 } : {}) };
  });
  const active = { entries: [{ id: plainIds[0], sets }] };
  const now = at + Math.floor(rnd() * 3 * 3600000);
  sessionEnds.push({ active, now, out: sessionEnd(active, now) });
}

// 4. completed workouts
const completed = [];
for (let i = 0; i < 25; i++) {
  const mk = () => ({ id: pick(plainIds), sets: Array.from({ length: 1 + Math.floor(rnd() * 4) }, () => mkSet()), ...(rnd() > 0.7 ? { note: ' felt good ' } : {}), ...(rnd() > 0.8 ? { sg: 'sg-0-1' } : {}) });
  const active = { id: 'w' + i, d: '2026-10-10', start: 1_760_000_000_000, routineIds: rnd() > 0.5 ? ['r1'] : [], name: 'Session ' + i, bw: rnd() > 0.5 ? 71.5 : null, note: rnd() > 0.8 ? ' hard day ' : '', entries: [mk(), mk(), mk()] };
  completed.push({ active, end: 1_760_003_600_000, prs: [], out: buildCompletedWorkout(active, { end: 1_760_003_600_000, prs: [] }) });
}

// 5. history lookups and records
const workouts = [];
for (let i = 0; i < 12; i++) {
  const day = String(1 + i).padStart(2, '0');
  workouts.push({ id: 'h' + i, d: `2026-09-${day}`, start: Date.parse(`2026-09-${day}T17:00:00Z`), end: Date.parse(`2026-09-${day}T18:00:00Z`), routineIds: i % 3 ? [] : ['r1'], entries: [
    { id: plainIds[0], ...(i % 3 ? {} : { rid: 'r1' }), sets: [mkSet(true), mkSet(true), mkSet(rnd() > 0.5)], ...(i === 5 ? { noProg: true } : {}) },
    { id: plainIds[1], sets: [mkSet(true)] },
  ] });
}
const S = { workouts, exWeights: {}, unit: 'kg' };
const history = {
  S,
  last: plainIds.slice(0, 3).flatMap((id) => [null, 'r1'].map((rid) => ({ id, rid, out: lastEntryFor(S, id, rid) ?? null }))),
  series: plainIds.slice(0, 2).map((id) => ({ id, out: e1rmSeries(S, id, 'epley', 'total') })),
  best: plainIds.slice(0, 2).map((id) => ({ id, out: best1RM(S, id, 'epley', 'total') ?? null })),
  record: plainIds.slice(0, 2).map((id) => ({ id, entry: { id, sets: [{ w: 150, r: 5, done: true }] }, out: is1RMRecord(S, id, { id, sets: [{ w: 150, r: 5, done: true }] }, 'epley') ?? null })),
};

// 6. accent colours: the contrast maths and the "made readable" adjustment, on both themes
const hexes = ['#30d158', '#0a84ff', '#ffd60a', '#000000', '#ffffff', '#808080', '#123456', '#ffff00', '#fefefe', '#1c1c1e', '#bf5af2', '#ff0000', '#00ff00', '#3a3a3c', '#d0d0d8', '#9c27b0', '#222244', '#e0e0a0'];
for (let i = 0; i < 40; i++) hexes.push('#' + Math.floor(rnd() * 0xffffff).toString(16).padStart(6, '0'));
const accents = hexes.map((hex) => ({
  hex, grey: isGrey(hex),
  dark: readableIn(hex, 'dark'), light: readableIn(hex, 'light'),
  ink: [readableIn(hex, 'dark'), readableIn(hex, 'light')].map((c) => inkOnBoth(c, mix(c, '#000000', 0.25))),
  contrast: contrast(hex, '#1c1c1e'),
}));

// 7. kg <-> lb: the whole log, both ways
const mkLog = (unit) => ({
  unit, bodyweight: [{ d: '2026-09-01', w: 78.6 }, { d: '2026-09-02', w: 80 }], targetW: 75,
  exWeights: { [plainIds[0]]: { w: 100, d: '2026-09-01' }, [plainIds[1]]: 42.5 },
  routines: [{ id: 'r1', name: 'A', ex: [{ id: plainIds[0], sets: 3, reps: 8, weight: 60, inc: 2.5, warmup: [{ weight: 20, reps: 5 }], pyramidWeight: [50, 0, 60] }] }],
  workouts: workouts.slice(0, 4).map((w) => ({ ...w, bw: 71.5, vol: workoutVolume(w) })),
  barWeights: { [plainIds[0]]: 25, [plainIds[1]]: 20 },
});
const unitCases = ['kg', 'lb'].map((from) => {
  const log = mkLog(from);
  const to = from === 'kg' ? 'lb' : 'kg';
  return { from, to, log, out: convertStateUnit(log, to) };
});
const weights = [0, 0.5, 1.25, 2.5, 20, 45, 60.1, 100, 142.5, 225, 317.5].map((v) => ({ v, lb: convertWeight(v, 'kg', 'lb'), kg: convertWeight(v, 'lb', 'kg'), bwLb: convertBodyWeight(v, 'kg', 'lb'), bwKg: convertBodyWeight(v, 'lb', 'kg') }));

// 8. the Activity heatmap's day logic (history.js) and its shading, copied line for line from components/Heatmap.jsx
const heat = [];
for (const [weekStart, metric] of [[1, 'time'], [0, 'time'], [1, 'vol'], [0, 'vol']]) {
  const hw = [];
  for (let i = 0; i < 40; i++) {
    const day = new Date(2026, 9, 10, 12); day.setDate(day.getDate() - Math.floor(rnd() * 300));
    const start = Date.parse(isoOf(day) + 'T09:00:00Z');
    const dur = Math.floor(rnd() * 100) * 60000;
    const w = { id: 'hm' + i, d: isoOf(day), start, end: rnd() > 0.1 ? start + dur : undefined, entries: [{ id: plainIds[i % 4], sets: [mkSet(true), mkSet(rnd() > 0.5)] }] };
    if (i % 9 === 0) { delete w.d; w.start = Date.parse(isoOf(day) + 'T12:00:00Z'); }   // older record: the day comes from the start time
    if (i % 13 === 0) { w.d = 'not a date'; }
    if (i % 17 === 0) { delete w.entries; w.vol = 1234; }                               // legacy record: cached volume only
    hw.push(w);
  }
  const S = { workouts: hw, weekStart };
  const volumeOf = (w) => (Array.isArray(w?.entries) ? Math.max(0, Number(workoutVolume(w)) || 0) : (Number.isFinite(Number(w?.vol)) ? Math.max(0, Number(w.vol)) : 0));
  const agg = {};
  hw.forEach((w) => {
    const d = workoutDay(w); if (!d) return;
    const a = agg[d] = agg[d] || { n: 0, vol: 0, min: 0 };
    a.n++; a.vol += volumeOf(w); a.min += Math.max(0, Math.round(workoutDuration(w) / 60000));
  });
  const metricValue = metric === 'vol' ? 'vol' : 'min';
  const values = Object.values(agg).map((a) => a[metricValue]).filter((v) => v > 0).sort((a, b) => a - b);
  const q = (p) => (values.length ? values[Math.min(values.length - 1, Math.floor(p * values.length))] : 0);
  const t1 = q(0.25), t2 = q(0.5), t3 = q(0.75);
  const level = (a) => (!a ? 0 : !a[metricValue] ? 1 : a[metricValue] >= t3 ? 4 : a[metricValue] >= t2 ? 3 : a[metricValue] >= t1 ? 2 : 1);
  const today = new Date(2026, 9, 10, 12);
  const end = new Date(today); end.setDate(today.getDate() - weekDayOffset(today.getDay(), weekStart));
  const startD = new Date(end); startD.setDate(end.getDate() - 52 * 7);
  const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const months = [], cols = []; let lastMonth = -1;
  for (let wk = 0; wk <= 52; wk++) {
    const colStart = new Date(startD); colStart.setDate(startD.getDate() + wk * 7);
    const mo = colStart.getMonth();
    const showM = mo !== lastMonth && colStart.getDate() <= 7 && wk < 51;
    months.push(showM ? MONTHS[mo] : '');
    if (colStart.getDate() <= 7) lastMonth = mo;
    const cells = [];
    for (let d = 0; d < 7; d++) {
      const day = new Date(colStart); day.setDate(colStart.getDate() + d);
      const key = isoOf(day);
      cells.push({ iso: key, level: level(agg[key]), today: key === isoOf(new Date()) && false, future: day > today });
    }
    cols.push(cells);
  }
  const dayLabels = Array(7).fill(null);
  dayLabels[weekDayOffset(1, weekStart)] = 'Mon'; dayLabels[weekDayOffset(3, weekStart)] = 'Wed'; dayLabels[weekDayOffset(5, weekStart)] = 'Fri';
  heat.push({ weekStart, metric, today: isoOf(today), workouts: hw, days: hw.map((w) => ({ day: workoutDay(w) ?? null, ms: workoutDuration(w) })), cols, months, dayLabels, agg });
}

// 9. effort stepping and equipment
const efforts = [];
for (const kind of ['rir', 'rpe']) {
  for (const cur of [null, 0, 0.5, 2, 5.5, 6, 6.5, 9.5, 10, 3]) {
    for (const dir of [-1, 1]) efforts.push({ kind, cur, dir, out: stepEffort(kind, cur, dir) ?? null });
  }
  for (const v of [0, 3.3, 7, 10, 12]) efforts.push({ kind, cap: v, out: capEffort(kind, v) });
}
const eqLists = [[], ['barbell', 'bench'], ['dumbbell', 'pull-up bar', 'bench'], ALL_EQUIPMENT, ['cable', 'band']];
const equip = Object.values(EXIDX).filter((_, i) => i % 23 === 0).slice(0, 220).map((ex) => ({
  id: ex.id, acc: accessoriesOf(ex), avail: eqLists.map((l) => eqAvailable(l, ex)),
}));

const extra = {
  accents, unitCases, weights, heat, efforts, equip, allEquipment: ALL_EQUIPMENT, eqLists,
  volumes: completed.map((c) => ({ w: c.out, vol: workoutVolume(c.out), done: setsDone(c.out), total: setUnitsTotal(c.out.entries) })),
  bestWeights: plainIds.slice(0, 3).map((id) => ({ id, out: bestWeightFor(S, id) })),
};
const out = { ...extra, assistedId, plainIds, oneRm, entries, sessionEnds, completed, history };
const target = join(here, '..', '..', 'test', 'member', 'fixtures', 'golden.json');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, JSON.stringify(out));
console.log(`fixtures -> ${target} (${oneRm.length} 1RM, ${entries.length} entries, ${sessionEnds.length} session ends, ${completed.length} workouts)`);
