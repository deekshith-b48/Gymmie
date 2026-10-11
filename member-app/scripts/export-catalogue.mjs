#!/usr/bin/env node
/* Exports openGym's exercise catalogue as a data asset for the native member app.
 *
 *   node member-app/scripts/export-catalogue.mjs
 *
 * The muscle weights, cardio and assisted flags are computed by openGym's own code
 * (lib/muscles.js, lib/exercises.js), so the Dart side reads facts instead of re-deriving them. */
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const src = join(here, '..', 'opengym', 'frontend', 'src', 'lib');
const { CATALOGUE, isCardio, isAssisted, BODYPARTS } = await import(join(src, 'exercises.js'));
const { musclesOf, MUSCLES, MUSCLE_NAME } = await import(join(src, 'muscles.js'));

const round = (n) => Math.round(n * 100) / 100;
const exercises = CATALOGUE.map((e) => {
  const w = Object.fromEntries(Object.entries(musclesOf(e)).map(([k, v]) => [k, round(v)]));
  return {
    id: e.id, n: e.n, bp: e.bp, eq: e.eq ?? '', cat: e.cat ?? '', img: e.img ?? '', gif: e.gif ?? '',
    w, ...(isCardio(e.id) ? { cardio: true } : {}), ...(isAssisted(e.id) ? { assisted: true } : {}),
  };
});
const out = { v: 1, muscles: MUSCLES.map((m) => ({ id: m, name: MUSCLE_NAME[m] })), bodyparts: BODYPARTS, exercises };
const target = join(here, '..', '..', 'assets', 'member', 'exercises.json');
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, JSON.stringify(out));
console.log(`${exercises.length} exercises -> ${target}`);

// Body outlines for the "Choose a focus" map (openGym lib/body-paths.js, from MuscleMap, MIT).
const body = (await import(join(src, 'body-paths.js'))).default;
const { INERT } = await import(join(src, 'muscles.js'));
const bodyTarget = join(here, '..', '..', 'assets', 'member', 'body.json');
writeFileSync(bodyTarget, JSON.stringify({ inert: INERT, ...body }));
console.log(`body outlines -> ${bodyTarget}`);
