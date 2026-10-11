// Membership plan definitions and plan groups.
import { S, validate } from '../validate.js';
import { conflict, forbidden, invalid, notFound } from '../errors.js';
import { created, noContent } from '../http.js';
import { membershipStatus } from '../domain/membership.js';

export function registerPlanRoutes({ router }) {
  const PLAN = {
    name: S.str({ required: true, min: 1, max: 60 }),
    price: S.num({ required: true, min: 0, max: 10_000_000 }),
    durationDays: S.int({ required: true, min: 1, max: 3650 }),
    description: S.str({ max: 300 }),
    benefits: S.list(S.str({ min: 1, max: 80 }), { max: 12 }),
    groupId: S.str({ max: 64 }),
    sessions: S.obj({ enabled: S.bool({ default: true }), count: S.int({ required: true, min: 1, max: 1000 }) }, { nullable: true }),
  };

  const view = (ctx, p, today, mems) => {
    const group = p.groupId ? ctx.col('planGroups').get(p.groupId) : null;
    return {
      ...p, groupName: group?.name ?? null,
      activeMembers: mems.filter((m) => m.planId === p.id && membershipStatus(m, today) === 'active').length,
    };
  };

  router.get('/v5/memberships/plans', { perm: 'plans.read' }, (ctx) => {
    const today = ctx.today();
    const mems = ctx.col('memberships').all();
    const showDisabled = ctx.query.includeDisabled === 'true';
    return ctx.col('plans')
      .find((p) => (showDisabled || p.active !== false) && (!ctx.query.groupId || p.groupId === ctx.query.groupId))
      .sort((a, b) => (a.price - b.price) || a.name.localeCompare(b.name))
      .map((p) => view(ctx, p, today, mems));
  });

  router.get('/v5/memberships/plans/keys', { perm: 'plans.read' }, (ctx) =>
    ctx.col('plans').find((p) => p.active !== false).map((p) => ({ id: p.id, name: p.name, groupId: p.groupId ?? null })));

  router.get('/v5/memberships/plans/:id', { perm: 'plans.read' }, (ctx) => {
    const p = ctx.col('plans').get(ctx.params.id);
    if (!p) throw notFound('Plan not found');
    return view(ctx, p, ctx.today(), ctx.col('memberships').all());
  });

  const checkGroup = (ctx, groupId) => {
    if (groupId && !ctx.col('planGroups').get(groupId)) throw invalid('Please select the plan group');
  };
  const checkName = (ctx, name, ignoreId) => {
    if (ctx.col('plans').findOne((p) => p.id !== ignoreId && p.active !== false && p.name.toLowerCase() === name.toLowerCase())) {
      throw conflict('A plan with this name already exists');
    }
  };

  router.post('/v5/memberships/plans', { perm: 'plans.write' }, (ctx) => {
    const b = validate(PLAN, ctx.body);
    checkGroup(ctx, b.groupId);
    checkName(ctx, b.name);
    const limit = ctx.gym.subscription?.limits?.plans;
    if (limit && ctx.col('plans').count((p) => p.active !== false) >= limit) {
      throw forbidden('You are running out of limits for membership plans.');
    }
    if (b.sessions === null) delete b.sessions;
    return created(ctx.col('plans').insert({ ...b, active: true }));
  });

  router.patch('/v5/memberships/plans/:id', { perm: 'plans.write' }, (ctx) => {
    const p = ctx.col('plans').get(ctx.params.id);
    if (!p) throw notFound('Plan not found');
    const b = validate(PLAN, ctx.body, { partial: true });
    if (b.groupId !== undefined) checkGroup(ctx, b.groupId);
    if (b.name) checkName(ctx, b.name, p.id);
    const patch = { ...b };
    if (b.sessions === null) patch.sessions = undefined;
    return ctx.col('plans').update(p.id, patch);
  });

  router.post('/v5/memberships/plans/:id/duplicate', { perm: 'plans.write' }, (ctx) => {
    const p = ctx.col('plans').get(ctx.params.id);
    if (!p) throw notFound('Plan not found');
    const { id, createdAt, updatedAt, ...rest } = p;
    let name = `${p.name} (Copy)`;
    let i = 2;
    while (ctx.col('plans').findOne((x) => x.name.toLowerCase() === name.toLowerCase() && x.active !== false)) name = `${p.name} (Copy ${i++})`;
    return created(ctx.col('plans').insert({ ...rest, name, active: true }));
  });

  for (const [action, active] of [['disable', false], ['enable', true]]) {
    router.post(`/v5/memberships/plans/:id/${action}`, { perm: 'plans.write' }, (ctx) => {
      const p = ctx.col('plans').get(ctx.params.id);
      if (!p) throw notFound('Plan not found');
      if (active) checkName(ctx, p.name, p.id);
      return ctx.col('plans').update(p.id, { active });
    });
  }

  router.delete('/v5/memberships/plans/:id', { perm: 'plans.write' }, (ctx) => {
    // Memberships keep a snapshot of the plan (name, price, duration) so history survives deletion.
    if (!ctx.col('plans').remove(ctx.params.id)) throw notFound('Plan not found');
    return noContent();
  });

  // ---- plan groups ----------------------------------------------------------------------------------
  router.get('/v5/memberships/plan-groups', { perm: 'plans.read' }, (ctx) =>
    ctx.col('planGroups').all().map((g) => ({ ...g, planCount: ctx.col('plans').count((p) => p.groupId === g.id && p.active !== false) })));

  router.post('/v5/memberships/plan-groups', { perm: 'plans.write' }, (ctx) => {
    const b = validate({ name: S.str({ required: true, min: 1, max: 40 }) }, ctx.body);
    if (ctx.col('planGroups').findOne((g) => g.name.toLowerCase() === b.name.toLowerCase())) throw conflict('A plan group with this name already exists');
    return created(ctx.col('planGroups').insert(b));
  });

  router.patch('/v5/memberships/plan-groups/:id', { perm: 'plans.write' }, (ctx) => {
    const g = ctx.col('planGroups').get(ctx.params.id);
    if (!g) throw notFound('Plan group not found');
    const b = validate({ name: S.str({ required: true, min: 1, max: 40 }) }, ctx.body);
    if (ctx.col('planGroups').findOne((x) => x.id !== g.id && x.name.toLowerCase() === b.name.toLowerCase())) throw conflict('A plan group with this name already exists');
    return ctx.col('planGroups').update(g.id, b);
  });

  router.post('/v5/memberships/plan-groups/:id/move-plans', { perm: 'plans.write' }, (ctx) => {
    const g = ctx.col('planGroups').get(ctx.params.id);
    if (!g) throw notFound('Plan group not found');
    const b = validate({ toGroupId: S.str({ nullable: true }) }, ctx.body);
    if (b.toGroupId === g.id) throw invalid('Target path and source path cannot be the same.');
    if (b.toGroupId) checkGroup(ctx, b.toGroupId);
    let moved = 0;
    for (const p of ctx.col('plans').find((x) => x.groupId === g.id)) {
      ctx.col('plans').update(p.id, { groupId: b.toGroupId ?? undefined });
      moved++;
    }
    return { moved };
  });

  router.delete('/v5/memberships/plan-groups/:id', { perm: 'plans.write' }, (ctx) => {
    const g = ctx.col('planGroups').get(ctx.params.id);
    if (!g) throw notFound('Plan group not found');
    const inside = ctx.col('plans').find((p) => p.groupId === g.id);
    if (inside.length) {
      const to = ctx.query.moveTo;
      if (!to) throw conflict('Please select the plan group where you would like to move the exiting plans to.', { planCount: inside.length });
      checkGroup(ctx, to);
      if (to === g.id) throw invalid('Target path and source path cannot be the same.');
      for (const p of inside) ctx.col('plans').update(p.id, { groupId: to });
    }
    ctx.col('planGroups').remove(g.id);
    return noContent();
  });
}
