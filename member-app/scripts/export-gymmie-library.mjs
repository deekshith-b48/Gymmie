#!/usr/bin/env node
/* Exports openGym's exercise catalogue into Gymmie's own default exercise library
 * (backend/src/data/opengym_exercises.json), mapped to Gymmie's categories and equipment.
 *
 *   node member-app/scripts/export-gymmie-library.mjs */
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const { CATALOGUE } = await import(join(here, '..', 'opengym', 'frontend', 'src', 'lib', 'exercises.js'));

const CATEGORY = { chest: 'Chest', back: 'Back', shoulders: 'Shoulders', neck: 'Shoulders', 'upper arms': 'Arms', 'lower arms': 'Arms', 'upper legs': 'Legs', 'lower legs': 'Legs', waist: 'Core', cardio: 'Cardio', 'full body': 'Cardio' };
const EQUIP = {
  'body weight': 'Bodyweight Only', band: 'Resistance Bands', 'resistance band': 'Resistance Bands', dumbbell: 'Dumbbells',
  barbell: 'Barbell', 'ez barbell': 'Barbell', 'olympic barbell': 'Barbell', 'trap bar': 'Barbell', cable: 'Cables', rope: 'Cables',
};
const title = (s) => s.replace(/(^|[\s(/-])([a-z])/g, (_, a, b) => a + b.toUpperCase());

const rows = CATALOGUE.map((e) => [
  e.id, title(e.n), CATEGORY[e.bp] ?? 'Core', [EQUIP[e.eq] ?? 'Full Gym'], e.img ?? '', e.eq ?? '', e.cat ?? '',
]);
const target = join(here, '..', '..', 'backend', 'src', 'data', 'opengym_exercises.json');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, JSON.stringify({ source: 'openGym catalogue (AGPL-3.0-or-later)', rows }));
console.log(`${rows.length} exercises -> ${target}`);
