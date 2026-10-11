// Exercise library, workout plans and diet plans (templates + per-member assignments) and generators.
import { randomUUID } from 'node:crypto';
import { S, validate } from '../validate.js';
import { conflict, invalid, notFound } from '../errors.js';
import { created, list, noContent } from '../http.js';
import { OPENGYM_EXERCISES, withImage } from '../domain/library.js';
import { ensureFeature } from '../helpers.js';
import { EXERCISE_CATEGORIES, EXERCISE_LIBRARY, EQUIPMENT, GOALS, LEVELS, DIET_PREFERENCES, estimateCalories, generateDiet, generateWorkout } from '../domain/generators.js';
import { HEALTH_CONDITIONS } from './members.js';
import { diffDays } from '../domain/dates.js';

const EX = S.obj({
  id: S.str({ max: 64 }), exerciseId: S.str({ max: 64 }), name: S.str({ required: true, min: 1, max: 100 }), sets: S.int({ required: true, min: 1, max: 20 }),
  reps: S.str({ required: true, min: 1, max: 30 }), restSec: S.int({ min: 0, max: 900, default: 60 }), notes: S.str({ max: 300, nullable: true }),
});
const DAY = S.obj({ id: S.str({ max: 64 }), name: S.str({ required: true, min: 1, max: 60 }), exercises: S.list(EX, { required: true, max: 30 }) });
const WORKOUT = {
  name: S.str({ required: true, min: 1, max: 80 }), goal: S.str({ max: 40 }), level: S.str({ max: 20 }), description: S.str({ max: 500 }),
  days: S.list(DAY, { required: true, min: 1, max: 14 }),
};
const ITEM = S.obj({ id: S.str({ max: 64 }), name: S.str({ required: true, min: 1, max: 100 }), quantity: S.num({ min: 0, max: 100000, default: 1 }), unit: S.str({ max: 30 }), kcal: S.num({ min: 0, max: 10000 }), protein: S.num({ min: 0, max: 1000 }), notes: S.str({ max: 200 }), recipeLink: S.str({ max: 300 }) });
const MEAL = S.obj({ id: S.str({ max: 64 }), name: S.str({ required: true, min: 1, max: 60 }), time: S.str({ max: 8 }), items: S.list(ITEM, { required: true, max: 30 }) });
const DIET = {
  name: S.str({ required: true, min: 1, max: 80 }), goal: S.str({ max: 40 }), dietaryPreference: S.str({ max: 30 }), calorieTarget: S.int({ min: 500, max: 10000 }),
  macros: S.obj({ protein: S.num({ min: 0 }), carbs: S.num({ min: 0 }), fat: S.num({ min: 0 }) }), notes: S.str({ max: 1000 }), meals: S.list(MEAL, { required: true, min: 1, max: 10 }),
};
/** Gives every day / exercise / meal / item a stable id (clients may omit them on create). */
const withIds = (doc) => (doc.days
  ? { ...doc, days: doc.days.map((d) => ({ ...d, id: d.id ?? randomUUID(), exercises: d.exercises.map((e) => ({ ...e, id: e.id ?? randomUUID() })) })) }
  : { ...doc, meals: doc.meals.map((m) => ({ ...m, id: m.id ?? randomUUID(), items: m.items.map((i) => ({ ...i, id: i.id ?? randomUUID() })) })) });

export function registerFitnessRoutes({ router }) {
  // ---- exercise library -------------------------------------------------------------------------------------------
  router.get('/v5/exercises/categories', { perm: 'plansets.read' }, () => EXERCISE_CATEGORIES);
  router.get('/v5/exercises/meta', { perm: 'plansets.read' }, () => ({ categories: EXERCISE_CATEGORIES, equipment: EQUIPMENT, goals: GOALS, levels: LEVELS, dietaryPreferences: DIET_PREFERENCES, conditions: HEALTH_CONDITIONS }));
  // The built-in library is Gymmie's curated set plus openGym's catalogue. It is paged: with ~5,700 entries a
  // client narrows by `q` / `category` and reads `limit` (default 300, max 1000) per `page`.
  router.get('/v5/exercises', { perm: 'plansets.read' }, (ctx) => {
    const q = (ctx.query.q ?? '').toLowerCase().split(/\s+/).filter(Boolean);
    const base = ctx.config.exerciseMediaLicensed ? ctx.config.openGym?.publicUrl : null;
    const custom = ctx.col('exercises').all().map((e) => ({ ...e, builtIn: false }));
    const items = [...EXERCISE_LIBRARY, ...custom, ...OPENGYM_EXERCISES]
      .filter((e) => (!ctx.query.category || e.category === ctx.query.category) && q.every((w) => e.name.toLowerCase().includes(w)))
      .sort((a, b) => a.category.localeCompare(b.category) || a.name.localeCompare(b.name));
    return list(items.map((e) => withImage(e, base)), { page: ctx.query.page, limit: ctx.query.limit ?? '300' }, { maxLimit: 1000, defaultLimit: 300 });
  });
  const EXC = { name: S.str({ required: true, min: 1, max: 100 }), category: S.oneOf(EXERCISE_CATEGORIES, { required: true }), equipment: S.list(S.oneOf(EQUIPMENT), { max: 6 }), instructions: S.str({ max: 1000 }), videoUrl: S.str({ max: 300, pattern: /^https?:\/\/.+/, patternMessage: 'Please enter a valid URL' }) };
  router.post('/v5/exercises', { perm: 'plansets.write' }, (ctx) => {
    const b = validate(EXC, ctx.body);
    if (ctx.col('exercises').findOne((e) => e.name.toLowerCase() === b.name.toLowerCase()) || [...EXERCISE_LIBRARY, ...OPENGYM_EXERCISES].some((e) => e.name.toLowerCase() === b.name.toLowerCase())) throw conflict('An exercise with this name already exists');
    return created({ ...ctx.col('exercises').insert(b), builtIn: false });
  });
  router.patch('/v5/exercises/:id', { perm: 'plansets.write' }, (ctx) => {
    const e = ctx.col('exercises').get(ctx.params.id);
    if (!e) throw notFound('Exercise not found');
    return { ...ctx.col('exercises').update(e.id, validate(EXC, ctx.body, { partial: true })), builtIn: false };
  });
  router.delete('/v5/exercises/:id', { perm: 'plansets.write' }, (ctx) => {
    if (!ctx.col('exercises').remove(ctx.params.id)) throw notFound('Exercise not found');
    return noContent();
  });

  // ---- shared template/member plan machinery ---------------------------------------------------------------------------
  function plansApi({ base, coll, feature, schema, label }) {
    const gate = (ctx) => ensureFeature(ctx.gym, feature);
    const find = (ctx, id) => { const p = ctx.col(coll).get(id); if (!p) throw notFound(`${label} not found`); return p; };
    router.get(`${base}/plans`, { perm: 'plansets.read' }, (ctx) => { gate(ctx); return ctx.col(coll).find((p) => p.ownerType === 'template').sort((a, b) => b.updatedAt.localeCompare(a.updatedAt)); });
    router.get(`${base}/plans/:id`, { perm: 'plansets.read' }, (ctx) => { gate(ctx); return find(ctx, ctx.params.id); });
    router.post(`${base}/plans`, { perm: 'plansets.write' }, (ctx) => {
      gate(ctx);
      const b = withIds(validate(schema, ctx.body));
      if (ctx.col(coll).findOne((p) => p.ownerType === 'template' && p.name.toLowerCase() === b.name.toLowerCase())) throw conflict('A plan with this name already exists');
      return created(ctx.col(coll).insert({ ...b, ownerType: 'template', createdById: ctx.user.id }));
    });
    router.put(`${base}/plans/:id`, { perm: 'plansets.write' }, (ctx) => {
      gate(ctx);
      const p = find(ctx, ctx.params.id);
      const b = withIds(validate(schema, ctx.body));
      if (p.ownerType === 'template' && ctx.col(coll).findOne((x) => x.id !== p.id && x.ownerType === 'template' && x.name.toLowerCase() === b.name.toLowerCase())) throw conflict('A plan with this name already exists');
      return ctx.col(coll).replace(p.id, { ...b, ownerType: p.ownerType, memberId: p.memberId, sourceTemplateId: p.sourceTemplateId, createdById: p.createdById });
    });
    router.delete(`${base}/plans/:id`, { perm: 'plansets.write' }, (ctx) => {
      gate(ctx);
      const p = find(ctx, ctx.params.id);
      if (p.ownerType !== 'template') throw invalid('Use the member endpoint to remove an assigned plan');
      ctx.col(coll).remove(p.id);
      return noContent();
    });
    // Assign: copies the template to the member, replacing any current plan.
    router.post(`${base}/plans/:id/assign`, { perm: 'plansets.write' }, (ctx) => {
      gate(ctx);
      const p = find(ctx, ctx.params.id);
      const b = validate({ memberId: S.str({ required: true }) }, ctx.body);
      const m = ctx.col('members').get(b.memberId);
      if (!m) throw notFound('Member not found');
      if (ctx.role === 'trainer' && m.trainerId !== ctx.user.id) throw invalid('Member is not assigned to this trainer.');
      for (const old of ctx.col(coll).find((x) => x.ownerType === 'member' && x.memberId === m.id)) ctx.col(coll).remove(old.id);
      const { id, createdAt, updatedAt, ...rest } = p;
      return created(ctx.col(coll).insert({ ...withIds(rest), ownerType: 'member', memberId: m.id, sourceTemplateId: p.id, assignedAt: new Date().toISOString(), createdById: ctx.user.id }));
    });
    router.get(`${base}/members/:memberId`, { perm: 'plansets.read' }, (ctx) => {
      gate(ctx);
      const m = ctx.col('members').get(ctx.params.memberId);
      if (!m) throw notFound('Member not found');
      return ctx.col(coll).findOne((x) => x.ownerType === 'member' && x.memberId === m.id);
    });
    router.put(`${base}/members/:memberId`, { perm: 'plansets.write' }, (ctx) => {
      gate(ctx);
      const m = ctx.col('members').get(ctx.params.memberId);
      if (!m) throw notFound('Member not found');
      const b = withIds(validate(schema, ctx.body));
      const cur = ctx.col(coll).findOne((x) => x.ownerType === 'member' && x.memberId === m.id);
      if (cur) return ctx.col(coll).replace(cur.id, { ...b, ownerType: 'member', memberId: m.id, sourceTemplateId: cur.sourceTemplateId, assignedAt: cur.assignedAt, createdById: cur.createdById });
      return created(ctx.col(coll).insert({ ...b, ownerType: 'member', memberId: m.id, assignedAt: new Date().toISOString(), createdById: ctx.user.id }));
    });
    router.delete(`${base}/members/:memberId`, { perm: 'plansets.write' }, (ctx) => {
      gate(ctx);
      const cur = ctx.col(coll).findOne((x) => x.ownerType === 'member' && x.memberId === ctx.params.memberId);
      if (!cur) throw notFound(`${label} not found`);
      ctx.col(coll).remove(cur.id);
      return noContent();
    });
  }
  plansApi({ base: '/v5/workout', coll: 'workoutPlans', feature: 'WORKOUT_PLANS', schema: WORKOUT, label: 'Workout plan' });
  plansApi({ base: '/v5/diet', coll: 'dietPlans', feature: 'DIET_PLANS', schema: DIET, label: 'Diet plan' });

  // ---- generators (unsaved drafts the user reviews before saving) -------------------------------------------------------
  const memberFacts = (ctx, memberId) => {
    if (!memberId) return {};
    const m = ctx.col('members').get(memberId);
    if (!m) throw notFound('Member not found');
    const health = ctx.col('health').find((r) => r.memberId === memberId).sort((a, b) => a.date.localeCompare(b.date));
    const weightKg = health.filter((r) => r.type === 'weight').at(-1)?.value ?? m.weightKg ?? null;
    const heightCm = health.filter((r) => r.type === 'height').at(-1)?.value ?? m.heightCm ?? null;
    const age = m.birthDate ? Math.floor(diffDays(m.birthDate, ctx.today()) / 365.25) : null;
    return { member: m, weightKg, heightCm, age, gender: m.gender, conditions: ctx.col('conditions').find((c) => c.memberId === memberId).map((c) => c.name) };
  };

  router.post('/v5/workout/generate', { perm: 'plansets.write' }, (ctx) => {
    ensureFeature(ctx.gym, 'AI_WORKOUTS');
    const b = validate({
      memberId: S.str(), goal: S.oneOf(GOALS, { default: 'General Fitness' }), level: S.oneOf(LEVELS, { default: 'Beginner' }), daysPerWeek: S.int({ min: 2, max: 6, default: 3 }),
      equipment: S.list(S.oneOf(EQUIPMENT), { max: 6 }), sessionMinutes: S.int({ min: 20, max: 120, default: 60 }), conditions: S.list(S.str({ max: 80 }), { max: 20 }),
    }, ctx.body);
    const f = memberFacts(ctx, b.memberId);
    return generateWorkout({ ...b, equipment: b.equipment?.length ? b.equipment : ['Full Gym'], conditions: [...new Set([...(b.conditions ?? []), ...(f.conditions ?? [])])], memberName: f.member?.name });
  });

  router.post('/v5/diet/generate', { perm: 'plansets.write' }, (ctx) => {
    ensureFeature(ctx.gym, 'AI_WORKOUTS');
    const b = validate({
      memberId: S.str(), goal: S.oneOf(GOALS, { default: 'General Fitness' }), dietaryPreference: S.oneOf(DIET_PREFERENCES, { default: 'Vegetarian' }), calorieTarget: S.int({ min: 800, max: 6000 }),
      mealsPerDay: S.int({ min: 3, max: 6, default: 4 }), allergies: S.list(S.str({ max: 40 }), { max: 15 }),
    }, ctx.body);
    const f = memberFacts(ctx, b.memberId);
    const kcal = b.calorieTarget ?? estimateCalories({ ...f, goal: b.goal }) ?? 2000;
    return generateDiet({ ...b, calorieTarget: kcal, allergies: b.allergies ?? [], weightKg: f.weightKg, memberName: f.member?.name });
  });
}
