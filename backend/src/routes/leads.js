// Leads ("prospects"): enquiries that may be converted into members.
// Filter and sort options mirror the original lead filter sheet (screenshot recovered from the APK).
import { S, validate } from '../validate.js';
import { conflict, invalid, notFound } from '../errors.js';
import { created, noContent, raw } from '../http.js';
import { addDays, nextMonday, addMonths } from '../domain/dates.js';
import { toCsv } from '../helpers.js';
import { sendAutomated } from '../domain/notify.js';
import { createMembership, PURCHASE_SCHEMA } from './memberships.js';
import { storeFile } from './auth.js';

export const LEAD_SOURCES = ['Walk-in', 'Social Media', 'Friend', 'Existing Member', 'Google', 'Campaign', 'Other'];
export const CHANCES = ['Low', 'Medium', 'High'];
const CHANCE_RANK = { Low: 1, Medium: 2, High: 3 };

const LEAD = {
  name: S.str({ required: true, min: 2, max: 80 }), phone: S.phone({ required: true }), email: S.email(),
  gender: S.oneOf(['male', 'female', 'other']), source: S.oneOf(LEAD_SOURCES, { default: 'Walk-in' }),
  chanceOfJoining: S.oneOf(CHANCES, { default: 'Medium' }), followUpDate: S.date(), notes: S.str({ max: 500 }),
  interestedPlanId: S.str({ max: 64, nullable: true }), labelIds: S.list(S.str({ max: 64 }), { max: 20 }),
  photo: S.obj({ data: S.str({ required: true, max: 8_000_000 }), contentType: S.str({ max: 60 }) }),
};

const SORTS = {
  createdAtAsc: (a, b) => a.createdAt.localeCompare(b.createdAt), createdAtDesc: (a, b) => b.createdAt.localeCompare(a.createdAt),
  nameAsc: (a, b) => a.name.localeCompare(b.name), nameDesc: (a, b) => b.name.localeCompare(a.name),
  chanceOfJoiningAsc: (a, b) => CHANCE_RANK[a.chanceOfJoining] - CHANCE_RANK[b.chanceOfJoining],
  chanceOfJoiningDesc: (a, b) => CHANCE_RANK[b.chanceOfJoining] - CHANCE_RANK[a.chanceOfJoining],
  followupDateAsc: (a, b) => (a.followUpDate ?? '9999').localeCompare(b.followUpDate ?? '9999'),
  followupDateDesc: (a, b) => (b.followUpDate ?? '').localeCompare(a.followUpDate ?? ''),
};

export function registerLeadRoutes({ router, store }) {
  const view = (l, tags) => ({
    ...l, status: l.disabled ? 'disabled' : 'active', photoUrl: l.photoFileId ? `/v5/files/${l.photoFileId}` : null,
    labels: (l.labelIds ?? []).map((id) => tags.get(id)).filter(Boolean).map((t) => ({ id: t.id, name: t.name, color: t.color })),
  });
  const tagMap = (ctx) => new Map(ctx.col('tags').all().map((t) => [t.id, t]));
  const find = (ctx, id) => {
    const l = ctx.col('leads').get(id);
    if (!l) throw notFound('Lead member not found');
    return l;
  };

  function listLeads(ctx) {
    const today = ctx.today();
    const q = (ctx.query.q ?? '').trim().toLowerCase();
    const status = ctx.query.status ?? 'active';
    const labelIds = (ctx.query.labelIds ?? '').split(',').filter(Boolean);
    const tags = tagMap(ctx);
    const followUp = ctx.query.followUp ?? 'all';
    const followOk = (l) => {
      if (followUp === 'all') return true;
      if (!l.followUpDate) return false;
      if (followUp === 'today') return l.followUpDate === today;
      if (followUp === 'overdue') return l.followUpDate < today;
      if (followUp === 'nextMonday') return l.followUpDate === nextMonday(today);
      if (followUp === 'nextMonth') return l.followUpDate > today && l.followUpDate <= addMonths(today, 1);
      return true;
    };
    return ctx.col('leads').all()
      .filter((l) => !l.convertedMemberId)
      .filter((l) => status === 'all' || (status === 'disabled') === !!l.disabled)
      .filter((l) => !ctx.query.source || ctx.query.source === 'All' || l.source === ctx.query.source)
      .filter((l) => !ctx.query.chance || ctx.query.chance === 'All' || l.chanceOfJoining === ctx.query.chance)
      .filter((l) => !labelIds.length || labelIds.some((id) => l.labelIds?.includes(id)))
      .filter(followOk)
      .filter((l) => !q || l.name.toLowerCase().includes(q) || l.phone.replace(/\D/g, '').includes(q.replace(/\D/g, '') || '\u0000'))
      .sort(SORTS[ctx.query.sort] ?? SORTS.createdAtDesc).map((l) => view(l, tags));
  }

  router.get('/v5/prospects/members', { perm: 'leads.read' }, (ctx) => {
    const all = listLeads(ctx);
    const page = Math.max(1, parseInt(ctx.query.page ?? '1', 10) || 1);
    const limit = Math.min(200, Math.max(1, parseInt(ctx.query.limit ?? '20', 10) || 20));
    return { __envelope: true, status: 200, body: { data: all.slice((page - 1) * limit, page * limit), meta: { page, limit, total: all.length, totalPages: Math.max(1, Math.ceil(all.length / limit)) } } };
  });

  router.get('/v5/prospects/members/export', { perm: 'leads.read' }, (ctx) => raw(200, 'text/csv; charset=utf-8', toCsv(listLeads(ctx), [
    { header: 'Name', value: (l) => l.name }, { header: 'Phone', value: (l) => l.phone }, { header: 'Email', value: (l) => l.email },
    { header: 'Source', value: (l) => l.source }, { header: 'Chance of Joining', value: (l) => l.chanceOfJoining }, { header: 'Follow Up', value: (l) => l.followUpDate },
    { header: 'Status', value: (l) => l.status }, { header: 'Created', value: (l) => l.createdAt.slice(0, 10) },
  ]), { 'content-disposition': `attachment; filename="leads-${ctx.today()}.csv"` }));

  router.get('/v5/prospects/members/:id', { perm: 'leads.read' }, (ctx) => view(find(ctx, ctx.params.id), tagMap(ctx)));

  const checkRefs = (ctx, b) => {
    if (b.interestedPlanId && !ctx.col('plans').get(b.interestedPlanId)) throw invalid('Please select a plan');
    for (const id of b.labelIds ?? []) if (!ctx.col('tags').get(id)) throw invalid('Unknown label');
  };

  router.post('/v5/prospects/members', { perm: 'leads.write' }, (ctx) => {
    const b = validate(LEAD, ctx.body);
    checkRefs(ctx, b);
    if (ctx.col('leads').findOne((l) => l.phone === b.phone && !l.convertedMemberId)) throw conflict('A lead with this phone number already exists');
    if (ctx.col('members').findOne((m) => m.phone === b.phone)) throw conflict('Member Contact Already Exists');
    const { photo, ...rest } = b;
    const patch = { ...rest, labelIds: rest.labelIds ?? [], disabled: false, createdById: ctx.user.id };
    if (photo) patch.photoFileId = storeFile(store, { gymId: ctx.gymId, ownerId: ctx.user.id, data: photo.data, declared: photo.contentType }).id;
    const doc = ctx.col('leads').insert(patch);
    sendAutomated(ctx, 'PROSPECT_GYM_MEMBER_WELCOME_SMS', { ...doc, name: doc.name, phone: doc.phone });
    return created(view(doc, tagMap(ctx)));
  });

  router.patch('/v5/prospects/members/:id', { perm: 'leads.write' }, (ctx) => {
    const l = find(ctx, ctx.params.id);
    const b = validate(LEAD, ctx.body, { partial: true });
    checkRefs(ctx, b);
    if (b.phone && b.phone !== l.phone && ctx.col('leads').findOne((x) => x.phone === b.phone && x.id !== l.id && !x.convertedMemberId)) throw conflict('A lead with this phone number already exists');
    const { photo, ...rest } = b;
    const patch = { ...rest };
    if (photo) patch.photoFileId = storeFile(store, { gymId: ctx.gymId, ownerId: ctx.user.id, data: photo.data, declared: photo.contentType }).id;
    if (b.interestedPlanId === null) patch.interestedPlanId = undefined;
    return view(ctx.col('leads').update(l.id, patch), tagMap(ctx));
  });

  router.delete('/v5/prospects/members/:id', { perm: 'leads.write' }, (ctx) => {
    find(ctx, ctx.params.id);
    ctx.col('leads').remove(ctx.params.id);
    return noContent();
  });

  router.post('/v5/prospects/members/:id/disable', { perm: 'leads.write' }, (ctx) => view(ctx.col('leads').update(find(ctx, ctx.params.id).id, { disabled: true }), tagMap(ctx)));
  router.post('/v5/prospects/members/:id/enable', { perm: 'leads.write' }, (ctx) => view(ctx.col('leads').update(find(ctx, ctx.params.id).id, { disabled: false }), tagMap(ctx)));

  // "Snooze this person so you can get alerted later": presets nextWeek / nextMonth / custom.
  router.post('/v5/prospects/members/:id/snooze', { perm: 'leads.write' }, (ctx) => {
    const l = find(ctx, ctx.params.id);
    const b = validate({ preset: S.oneOf(['nextWeek', 'nextMonth', 'custom'], { required: true }), date: S.date() }, ctx.body);
    const today = ctx.today();
    let date;
    if (b.preset === 'nextWeek') date = nextMonday(today);
    else if (b.preset === 'nextMonth') date = addMonths(today, 1);
    else {
      if (!b.date) throw invalid('date is required for a custom snooze');
      date = b.date;
    }
    if (date <= today) throw invalid('Select a future date');
    return view(ctx.col('leads').update(l.id, { followUpDate: date, snoozedAt: new Date().toISOString() }), tagMap(ctx));
  });

  router.post('/v5/prospects/members/:id/contacted', { perm: 'leads.write' }, (ctx) => {
    const l = find(ctx, ctx.params.id);
    const b = validate({ nextFollowUpDate: S.date(), notes: S.str({ max: 300 }) }, ctx.body);
    return view(ctx.col('leads').update(l.id, { lastContactedAt: new Date().toISOString(), followUpDate: b.nextFollowUpDate ?? l.followUpDate, notes: b.notes ?? l.notes }), tagMap(ctx));
  });

  router.post('/v5/prospects/members/:id/convert', { perm: ['leads.write', 'members.write'] }, (ctx) => {
    const l = find(ctx, ctx.params.id);
    const b = validate({ membership: S.obj(PURCHASE_SCHEMA), email: S.email(), birthDate: S.date(), gender: S.oneOf(['male', 'female', 'other']) }, ctx.body);
    if (ctx.col('members').findOne((m) => m.phone === l.phone)) throw conflict('Member Contact Already Exists');
    const member = store.tx(() => {
      const m = ctx.col('members').insert({
        name: l.name, phone: l.phone, email: b.email ?? l.email, gender: b.gender ?? l.gender, birthDate: b.birthDate, joinedAt: ctx.today(), admissionNo: store.nextCounter(ctx.gymId, 'admission'),
        labelIds: l.labelIds ?? [], blocked: false, photoFileId: l.photoFileId, notes: l.notes, referralCode: undefined, convertedFromLeadId: l.id,
      });
      if (b.membership) createMembership(ctx, m.id, b.membership, { kind: 'new' });
      ctx.col('leads').update(l.id, { convertedMemberId: m.id, convertedAt: new Date().toISOString() });
      return m;
    });
    return created({ memberId: member.id, admissionNo: member.admissionNo });
  });

  router.get('/v5/prospects/meta', { perm: 'leads.read' }, () => ({ sources: LEAD_SOURCES, chances: CHANCES }));
}
