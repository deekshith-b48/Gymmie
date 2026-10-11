// Feedback, video links, push-notification tokens, feature announcements, member documents, masters, public gym portal.
import { createHmac, timingSafeEqual } from 'node:crypto';
import { S, validate } from '../validate.js';
import { ApiError, conflict, forbidden, invalid, notFound } from '../errors.js';
import { created, noContent } from '../http.js';
import { parseGym, loadGym } from '../helpers.js';
import { storeFile } from './auth.js';
import { COUNTRIES } from './config.js';

const URL_RE = /^https?:\/\/[^\s/$.?#].[^\s]*$/i;
export const ANNOUNCEMENTS = [
  { id: 'ann-2-0-0', title: "Gymmie 2.0", body: 'A member app with access codes, a 14-day free trial, online fee collection with your own Razorpay account, and a new look.', kind: 'major', createdAt: '2026-10-11T00:00:00.000Z', catalog: 'dev' },
  { id: 'ann-1-9-4', title: "What's New in 1.9.4", body: 'Trainer session bookings, PAR-Q forms and balance reminders are now available.', kind: 'major', createdAt: '2026-09-01T00:00:00.000Z', catalog: 'dev' },
  { id: 'ann-1-9-0', title: 'AI diet and workout plans', body: 'Generate plans for members from their goals and health profile.', kind: 'minor', createdAt: '2026-07-01T00:00:00.000Z', catalog: 'dev' },
];

export function registerMiscRoutes({ router, store, auth, limiter, config }) {
  // ---- feedback -----------------------------------------------------------------------------------------------------------
  const fbList = (ctx) => ctx.col('feedbacks').all().filter((f) => (ctx.query.favorite !== 'true' || f.isFavorite) && (!ctx.query.rating || f.rating === Number(ctx.query.rating)))
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  router.get('/v5/feedbacks', { perm: 'feedback.read' }, (ctx) => fbList(ctx));
  router.get('/v5/feedbacks/stats', { perm: 'feedback.read' }, (ctx) => {
    const all = ctx.col('feedbacks').all();
    const dist = [1, 2, 3, 4, 5].map((r) => ({ rating: r, count: all.filter((f) => f.rating === r).length }));
    return { total: all.length, unseen: all.filter((f) => !f.seen).length, average: all.length ? Math.round((all.reduce((s, f) => s + f.rating, 0) / all.length) * 10) / 10 : null, distribution: dist };
  });
  router.get('/v5/feedbacks/latest-unseen', { perm: 'feedback.read' }, (ctx) => fbList(ctx).find((f) => !f.seen) ?? null);
  router.get('/v5/feedbacks/:id', { perm: 'feedback.read' }, (ctx) => { const f = ctx.col('feedbacks').get(ctx.params.id); if (!f) throw notFound('Feedback not found'); return f; });
  router.post('/v5/feedbacks/:id/seen', { perm: 'feedback.read' }, (ctx) => { const f = ctx.col('feedbacks').get(ctx.params.id); if (!f) throw notFound('Feedback not found'); return ctx.col('feedbacks').update(f.id, { seen: true }); });
  router.post('/v5/feedbacks/:id/favorite', { perm: 'feedback.read' }, (ctx) => {
    const f = ctx.col('feedbacks').get(ctx.params.id);
    if (!f) throw notFound('Feedback not found');
    return ctx.col('feedbacks').update(f.id, { isFavorite: validate({ isFavorite: S.bool({ required: true }) }, ctx.body).isFavorite });
  });

  // ---- video links ------------------------------------------------------------------------------------------------------------
  const VID = { title: S.str({ required: true, min: 1, max: 100 }), url: S.str({ required: true, max: 400, pattern: URL_RE, patternMessage: 'Please enter a valid URL' }), category: S.str({ max: 40 }) };
  router.get('/v5/video-links', { perm: 'plans.read' }, (ctx) => ctx.col('videoLinks').all());
  router.post('/v5/video-links', { perm: 'videos.write' }, (ctx) => created(ctx.col('videoLinks').insert(validate(VID, ctx.body))));
  router.patch('/v5/video-links/:id', { perm: 'videos.write' }, (ctx) => {
    const v = ctx.col('videoLinks').get(ctx.params.id);
    if (!v) throw notFound('Video link not found');
    return ctx.col('videoLinks').update(v.id, validate(VID, ctx.body, { partial: true }));
  });
  router.delete('/v5/video-links/:id', { perm: 'videos.write' }, (ctx) => { if (!ctx.col('videoLinks').remove(ctx.params.id)) throw notFound('Video link not found'); return noContent(); });

  // ---- push notification tokens (FCM) --------------------------------------------------------------------------------------------
  router.post('/v5/notifiers', { auth: 'user' }, (ctx) => {
    const b = validate({ fcmToken: S.str({ required: true, min: 20, max: 4096 }), platform: S.oneOf(['android', 'ios', 'web'], { default: 'android' }), deviceId: S.str({ max: 120 }) }, ctx.body);
    store.run('DELETE FROM docs WHERE collection = ? AND gym_id = ? AND json_extract(data, ?) = ?', 'notifiers', ctx.user.id, '$.fcmToken', b.fcmToken);
    const existing = store.col(ctx.user.id, 'notifiers').findOne((n) => b.deviceId && n.deviceId === b.deviceId);
    if (existing) return store.col(ctx.user.id, 'notifiers').update(existing.id, b);
    return created(store.col(ctx.user.id, 'notifiers').insert(b));
  });
  router.delete('/v5/notifiers', { auth: 'user' }, (ctx) => {
    const token = ctx.query.fcmToken;
    if (token) for (const n of store.col(ctx.user.id, 'notifiers').find((x) => x.fcmToken === token)) store.col(ctx.user.id, 'notifiers').remove(n.id);
    return noContent();
  });

  // ---- feature announcements ("What's New") ------------------------------------------------------------------------------------------
  router.get('/v5/me/feature-announcements', { auth: 'user' }, (ctx) => {
    const seen = new Set(store.col(ctx.user.id, 'announcementsSeen').all().map((s) => s.announcementId));
    return ANNOUNCEMENTS.map((a) => ({ ...a, seen: seen.has(a.id) }));
  });
  router.post('/v5/me/feature-announcements/:id/seen', { auth: 'user' }, (ctx) => {
    if (!ANNOUNCEMENTS.some((a) => a.id === ctx.params.id)) throw notFound('Announcement not found');
    const c = store.col(ctx.user.id, 'announcementsSeen');
    if (!c.findOne((s) => s.announcementId === ctx.params.id)) c.insert({ announcementId: ctx.params.id });
    return noContent();
  });

  // ---- member documents ("Documents & invoices": file uploads or links) ---------------------------------------------------------------------
  router.get('/v5/members/:id/documents', { perm: 'members.read' }, (ctx) => {
    if (!ctx.col('members').get(ctx.params.id)) throw notFound('Member not found');
    return ctx.col('documents').find((d) => d.memberId === ctx.params.id).map((d) => ({ ...d, fileUrl: d.fileId ? `/v5/files/${d.fileId}` : null }));
  });
  router.post('/v5/members/:id/documents', { perm: 'members.write' }, (ctx) => {
    if (!ctx.col('members').get(ctx.params.id)) throw notFound('Member not found');
    const b = validate({
      title: S.str({ required: true, min: 1, max: 100 }), type: S.oneOf(['file', 'url'], { required: true }), url: S.str({ max: 400, pattern: URL_RE, patternMessage: 'Please enter a valid URL' }),
      file: S.obj({ data: S.str({ required: true, max: 8_000_000 }), contentType: S.str({ max: 60 }) }),
    }, ctx.body);
    if (b.type === 'url' && !b.url) throw invalid('URL cannot be empty');
    if (b.type === 'file' && !b.file) throw invalid('Please upload a file');
    const fileId = b.type === 'file' ? storeFile(store, { gymId: ctx.gymId, ownerId: ctx.user.id, data: b.file.data, declared: b.file.contentType }).id : null;
    const d = ctx.col('documents').insert({ memberId: ctx.params.id, title: b.title, type: b.type, url: b.url ?? null, fileId, uploadedById: ctx.user.id });
    return created({ ...d, fileUrl: fileId ? `/v5/files/${fileId}` : null });
  });
  router.delete('/v5/members/:id/documents/:docId', { perm: 'members.write' }, (ctx) => {
    const d = ctx.col('documents').get(ctx.params.docId);
    if (!d || d.memberId !== ctx.params.id) throw notFound('Document not found');
    ctx.col('documents').remove(d.id);
    return noContent();
  });

  // ---- masters ------------------------------------------------------------------------------------------------------------------------------------
  router.get('/v5/masters/timezones', { auth: 'none' }, () => Intl.supportedValuesOf('timeZone'));
  router.get('/v5/masters/languages', { auth: 'none' }, () => [
    { code: 'en', name: 'English' }, { code: 'hi', name: 'हिन्दी' }, { code: 'bn', name: 'বাংলা' }, { code: 'gu', name: 'ગુજરાતી' },
    { code: 'kn', name: 'ಕನ್ನಡ' }, { code: 'mr', name: 'मराठी' }, { code: 'ta', name: 'தமிழ்' }, { code: 'te', name: 'తెలుగు' },
  ]);
  router.get('/v5/masters/countries', { auth: 'none' }, () => COUNTRIES);

  // ---- public gym portal (scan the gym QR: browse plans, leave feedback, register interest) --------------------------------------------------
  const gymByCode = (code) => {
    const row = store.get('SELECT * FROM gyms WHERE code = ?', String(code));
    if (!row) throw notFound('Gym not found');
    return parseGym(row);
  };
  const sign = (payload) => createHmac('sha256', config.jwtSecret).update(`portal:${payload}`).digest('base64url');
  const portalToken = (gymId, phone) => {
    const body = Buffer.from(JSON.stringify({ g: gymId, p: phone, e: Date.now() + 30 * 60 * 1000 })).toString('base64url');
    return `${body}.${sign(body)}`;
  };
  const readPortalToken = (token, gymId) => {
    const [body, sig] = String(token ?? '').split('.');
    if (!body || !sig) throw forbidden('Please verify your number first');
    const a = Buffer.from(sig); const b = Buffer.from(sign(body));
    if (a.length !== b.length || !timingSafeEqual(a, b)) throw forbidden('Please verify your number first');
    const d = JSON.parse(Buffer.from(body, 'base64url').toString());
    if (d.g !== gymId || d.e < Date.now()) throw forbidden('Your verification expired. Please verify again.');
    return d;
  };
  router.get('/v5/portal/:code', { auth: 'none' }, (ctx) => {
    const g = gymByCode(ctx.params.code);
    return {
      gym: { name: g.name, city: g.city, logoUrl: null }, feedbackEnabled: true,
      plans: store.col(g.id, 'plans').find((p) => p.active !== false).map((p) => ({ name: p.name, price: p.price, durationDays: p.durationDays, description: p.description ?? null })),
      currencySymbol: g.currencySymbol,
    };
  });
  router.post('/v5/portal/:code/otp', { auth: 'none' }, (ctx) => {
    const g = gymByCode(ctx.params.code);
    const b = validate({ phone: S.phone({ required: true }) }, ctx.body);
    limiter.check(`portal-ip:${ctx.ip}`, 20, 600);
    limiter.check(`portal-phone:${b.phone}`, 5, 600);
    const o = auth.createOtp({ purpose: 'portal', channel: 'sms', target: b.phone, context: { gymId: g.id } });
    return { requestId: o.requestId, expiresIn: o.expiresIn, devOtp: o.devOtp };
  });
  router.post('/v5/portal/:code/verify', { auth: 'none' }, (ctx) => {
    const g = gymByCode(ctx.params.code);
    const b = validate({ requestId: S.str({ required: true }), otp: S.str({ required: true, min: 4, max: 8 }) }, ctx.body);
    const r = auth.verifyOtp(b.requestId, b.otp, 'portal');
    if (r.context.gymId !== g.id) throw forbidden('This code is not valid for this gym');
    return { portalToken: portalToken(g.id, r.target) };
  });
  router.post('/v5/portal/:code/feedback', { auth: 'none' }, (ctx) => {
    const g = gymByCode(ctx.params.code);
    const b = validate({ portalToken: S.str({ required: true }), rating: S.int({ required: true, min: 1, max: 5 }), comment: S.str({ max: 1000 }), category: S.oneOf(['Facilities', 'Trainers', 'Cleanliness', 'Equipment', 'Staff', 'Other']) }, ctx.body);
    const t = readPortalToken(b.portalToken, g.id);
    const col = store.col(g.id, 'feedbacks');
    if (col.findOne((f) => f.phone === t.p && Date.now() - Date.parse(f.createdAt) < 24 * 3600 * 1000)) throw conflict('You have already shared feedback today. Thank you!');
    const member = store.col(g.id, 'members').findOne((m) => m.phone === t.p);
    return created(col.insert({ phone: t.p, name: member?.name ?? null, memberId: member?.id ?? null, rating: b.rating, comment: b.comment ?? null, category: b.category ?? 'Other', seen: false, isFavorite: false }));
  });
  router.post('/v5/portal/:code/register', { auth: 'none' }, (ctx) => {
    const g = gymByCode(ctx.params.code);
    const b = validate({ portalToken: S.str({ required: true }), name: S.str({ required: true, min: 2, max: 80 }), interestedPlanName: S.str({ max: 60 }) }, ctx.body);
    const t = readPortalToken(b.portalToken, g.id);
    const leads = store.col(g.id, 'leads');
    if (store.col(g.id, 'members').findOne((m) => m.phone === t.p)) throw conflict('You are already a member of this gym.');
    if (leads.findOne((l) => l.phone === t.p && !l.convertedMemberId)) throw conflict('Your details are already with the gym. They will contact you soon.');
    const plan = b.interestedPlanName ? store.col(g.id, 'plans').findOne((p) => p.name === b.interestedPlanName) : null;
    leads.insert({ name: b.name, phone: t.p, source: 'Other', chanceOfJoining: 'Medium', interestedPlanId: plan?.id, labelIds: [], disabled: false, notes: 'Self-registered via gym QR', followUpDate: new Date().toISOString().slice(0, 10) });
    return created({ registered: true });
  });
}
