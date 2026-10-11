// The gym's side of the member app: the requests members send, a member's shared training summary, inviting a member to
// the app, and switching it back on for a member who closed their app account. Everything is scoped to the caller's gym
// (ctx.col), and every role check is on the server.
import { S, validate } from '../validate.js';
import { conflict, forbidden, notFound } from '../errors.js';
import { currentMembership } from '../domain/membership.js';
import { buildIndex, memberSummary } from '../domain/views.js';
import { assertTrainerScope, shareLevelOf, trainingSummary } from '../domain/privacy.js';
import { enqueue } from '../domain/notify.js';
import { nowIso } from '../db.js';

export function registerMemberStaffRoutes({ router, store }) {
  const findMember = (ctx, id) => {
    const m = ctx.col('members').get(id);
    if (!m) throw notFound('Member not found');
    return m;
  };

  // ---- requests -------------------------------------------------------------------------------------------------------------
  const view = (ctx, q, members) => {
    const m = members.get(q.memberId);
    const cur = m ? currentMembership(ctx.col('memberships').find((x) => x.memberId === m.id), ctx.today()) : null;
    return {
      id: q.id, type: q.type, status: q.status, note: q.note ?? null, planId: q.planId ?? null, planName: q.planName ?? null, planPrice: q.planPrice ?? null,
      createdAt: q.createdAt, decidedAt: q.decidedAt ?? null, decisionNote: q.decisionNote ?? null, decidedById: q.decidedById ?? null,
      member: m ? { id: m.id, name: m.name, phone: m.phone, photoUrl: m.photoFileId ? `/v5/files/${m.photoFileId}` : null } : { id: q.memberId, name: '(removed)', phone: null, photoUrl: null },
      currentMembership: cur ? { id: cur.m.id, planName: cur.m.planName, status: cur.s, startDate: cur.m.startDate, endDate: cur.m.endDate } : null,
    };
  };

  router.get('/v5/membership-requests', { perm: 'requests.read' }, (ctx) => {
    const members = new Map(ctx.col('members').all().map((m) => [m.id, m]));
    const status = ctx.query.status;
    const rows = ctx.col('membershipRequests')
      .find((q) => (!status || q.status === status) && (!ctx.query.memberId || q.memberId === ctx.query.memberId))
      .sort((a, b) => (a.status === 'pending' ? 0 : 1) - (b.status === 'pending' ? 0 : 1) || b.createdAt.localeCompare(a.createdAt));
    const page = Math.max(1, parseInt(ctx.query.page ?? '1', 10) || 1);
    const limit = Math.min(100, Math.max(1, parseInt(ctx.query.limit ?? '30', 10) || 30));
    return {
      __envelope: true, status: 200,
      body: {
        data: rows.slice((page - 1) * limit, page * limit).map((q) => view(ctx, q, members)),
        meta: { page, limit, total: rows.length, pending: ctx.col('membershipRequests').count((q) => q.status === 'pending') },
      },
    };
  });

  router.get('/v5/membership-requests/:id', { perm: 'requests.read' }, (ctx) => {
    const q = ctx.col('membershipRequests').get(ctx.params.id);
    if (!q) throw notFound('Request not found');
    return view(ctx, q, new Map(ctx.col('members').all().map((m) => [m.id, m])));
  });

  // Approving records the gym's answer. It does not move money or change the membership: the owner does that with the
  // usual renew / upgrade / end actions, so a member's request can never alter what they pay, when they are valid until,
  // or what they are entitled to.
  router.post('/v5/membership-requests/:id/decision', { perm: 'requests.write' }, (ctx) => {
    const q = ctx.col('membershipRequests').get(ctx.params.id);
    if (!q) throw notFound('Request not found');
    const b = validate({ decision: S.oneOf(['approve', 'reject'], { required: true }), note: S.str({ max: 300 }) }, ctx.body);
    if (q.status !== 'pending') throw conflict('This request has already been decided.');
    const updated = ctx.col('membershipRequests').update(q.id, {
      status: b.decision === 'approve' ? 'approved' : 'rejected', decidedById: ctx.user.id, decidedAt: nowIso(), decisionNote: b.note ?? null,
    });
    return view(ctx, updated, new Map(ctx.col('members').all().map((m) => [m.id, m])));
  });

  // ---- a member's shared training summary -----------------------------------------------------------------------------------
  // Off unless the member chose to share. "trainer": their own trainer and the gym's owner/manager. "gym": also the front desk.
  router.get('/v5/members/:id/training', { perm: 'members.read' }, (ctx) => {
    const m = findMember(ctx, ctx.params.id);
    assertTrainerScope(ctx, m);
    const level = shareLevelOf(m);
    const allowed = level === 'gym' || (level === 'trainer' && ['owner', 'manager', 'trainer'].includes(ctx.role));
    if (!allowed) throw forbidden('This member keeps their training log private.');
    const row = store.get('SELECT data FROM member_state WHERE gym_id = ? AND member_id = ?', ctx.gymId, m.id);
    const state = row ? JSON.parse(row.data) : null;
    return { shared: level, ...trainingSummary(state, ctx.today()) };
  });

  // ---- inviting a member to the app ---------------------------------------------------------------------------------------------
  router.post('/v5/members/:id/app-invite', { perm: 'members.write' }, (ctx) => {
    const m = findMember(ctx, ctx.params.id);
    if (!ctx.gym.features?.MEMBER_APP) throw conflict('Switch on the member app for this gym first.');
    if (m.blocked) throw conflict('This member is blocked.');
    if (m.appClosedAt) throw conflict('This member closed their app account. Switch it back on first.');
    if (!ctx.gym.whatsapp?.enabled) throw conflict('Turn on WhatsApp messaging to send invitations.');
    const body = `Hi ${m.name}, ${ctx.gym.name} now has a member app. Open it and sign in with ${m.phone} to see your membership, log workouts and more. Gym code: ${ctx.gym.code}.`;
    const row = enqueue(ctx, { key: 'MEMBER_APP_INVITE', to: m.phone, memberId: m.id, body });
    if (row.status === 'failed') throw conflict("You don't have enough message credits. Please recharge.");
    ctx.col('members').update(m.id, { appInvitedAt: nowIso() });
    return { sent: true, invitedAt: ctx.col('members').get(m.id).appInvitedAt };
  });

  // ---- a member who closed their app account ------------------------------------------------------------------------------------
  router.post('/v5/members/:id/member-app/reopen', { perm: 'members.write' }, (ctx) => {
    const m = findMember(ctx, ctx.params.id);
    if (!m.appClosedAt) throw conflict('Their app account is not closed.');
    ctx.col('members').update(m.id, { appClosedAt: undefined, appClosedBy: undefined });
    return memberSummary(ctx.col('members').get(m.id), buildIndex(ctx));
  });
}

