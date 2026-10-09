// PAR-Q (Physical Activity Readiness Questionnaire): versioned form builder, generation, signing, risk flags.
import { randomUUID } from 'node:crypto';
import { S, validate } from '../validate.js';
import { invalid, notFound } from '../errors.js';
import { created } from '../http.js';
import { ensureFeature } from '../helpers.js';
import { storeFile } from './auth.js';

const q = (text, critical = false) => ({ id: randomUUID(), type: 'question', text, answerType: 'yesno', required: true, critical });
export const STANDARD_QUESTIONS = [
  'Has your doctor ever said that you have a heart condition and that you should only do physical activity recommended by a doctor?',
  'Do you feel pain in your chest when you do physical activity?',
  'In the past month, have you had chest pain when you were not doing physical activity?',
  'Do you lose your balance because of dizziness or do you ever lose consciousness?',
  'Do you have a bone or joint problem (for example, back, knee or hip) that could be made worse by a change in your physical activity?',
  'Is your doctor currently prescribing drugs (for example, water pills) for your blood pressure or heart condition?',
  'Do you know of any other reason why you should not do physical activity?',
];
export const AREAS = {
  'Heart / cardiovascular': ['Have you ever been told you have high blood pressure?', 'Do you have a family history of heart disease before the age of 55?'],
  'Diabetes / metabolic': ['Have you been diagnosed with diabetes or pre-diabetes?', 'Do you take insulin or medication that lowers blood sugar?'],
  'Bone or joint': ['Have you had a fracture or joint injury in the last 12 months?', 'Do you have arthritis or osteoporosis?'],
  'Senior / rehab': ['Are you currently under physiotherapy or a rehabilitation programme?', 'Do you use a walking aid or have difficulty with balance?'],
  'HIIT / CrossFit': ['Do you have any condition that high-intensity exercise could aggravate?', 'Have you trained at high intensity during the last 3 months?'],
  'Recent surgery / injury': ['Have you had surgery in the last 12 months?', 'Do you have an injury that is still healing?'],
  'Respiratory (asthma / breathing)': ['Do you have asthma or any breathing difficulty during exercise?', 'Do you carry a reliever inhaler?'],
};
const CONSENT = 'I confirm that the information provided above is accurate and I agree to participate in physical activity at this gym.';

const WIDGET = S.obj({
  id: S.str({ max: 64 }), type: S.oneOf(['heading', 'text', 'question', 'signature'], { required: true }), text: S.str({ max: 600 }),
  answerType: S.oneOf(['yesno', 'text', 'choice'], { default: 'yesno' }), options: S.list(S.str({ max: 80 }), { max: 10 }), required: S.bool({ default: true }), critical: S.bool({ default: false }),
});

export function defaultForm() {
  return {
    title: 'Physical Activity Readiness Questionnaire',
    widgets: [
      { id: randomUUID(), type: 'heading', text: 'Physical Activity Readiness Questionnaire' },
      { id: randomUUID(), type: 'text', text: 'Please read each question carefully and answer honestly. Regular physical activity is fun and healthy, and more people are starting to become more active every day.' },
      ...STANDARD_QUESTIONS.map((t) => q(t, true)),
      { id: randomUUID(), type: 'signature', text: 'Member signature + I Agree', required: true },
    ],
    consent: CONSENT,
  };
}

export function registerParqRoutes({ router, store }) {
  const gate = (ctx) => ensureFeature(ctx.gym, 'MEMBER_HEALTH');
  const forms = (ctx) => ctx.col('parqForms').all().sort((a, b) => a.major - b.major || a.minor - b.minor);
  const current = (ctx) => {
    const all = forms(ctx);
    if (all.length) return all.at(-1);
    return ctx.col('parqForms').insert({ ...defaultForm(), major: 1, minor: 0, changeType: 'initial', createdById: ctx.user.id });
  };
  const versionLabel = (f) => `${f.major}.${f.minor}`;
  const formView = (f) => ({ ...f, version: versionLabel(f) });

  router.get('/v5/parq-form', { perm: 'plansets.read' }, (ctx) => { gate(ctx); return formView(current(ctx)); });
  router.get('/v5/parq-form/versions', { perm: 'plansets.read' }, (ctx) => { gate(ctx); current(ctx); return forms(ctx).map((f) => ({ id: f.id, version: versionLabel(f), changeType: f.changeType, createdAt: f.createdAt })).reverse(); });

  router.put('/v5/parq-form', { perm: 'plansets.write' }, (ctx) => {
    gate(ctx);
    const b = validate({ title: S.str({ required: true, min: 1, max: 120 }), widgets: S.list(WIDGET, { required: true, min: 1, max: 80 }), consent: S.str({ max: 600 }), changeType: S.oneOf(['major', 'minor'], { required: true }) }, ctx.body);
    if (!b.widgets.some((w) => w.type === 'question')) throw invalid('Please add at least one question');
    if (!b.widgets.some((w) => w.type === 'signature')) throw invalid('Please add a signature widget');
    for (const w of b.widgets) {
      if (w.type !== 'signature' && !w.text) throw invalid(w.type === 'question' ? 'Question text *' : 'Please enter the title');
      if (w.type === 'question' && w.answerType === 'choice' && !(w.options?.length >= 2)) throw invalid('Add at least two options');
    }
    const cur = current(ctx);
    const next = b.changeType === 'major' ? { major: cur.major + 1, minor: 0 } : { major: cur.major, minor: cur.minor + 1 };
    const { changeType, ...rest } = b;
    const widgets = rest.widgets.map((w) => ({ ...w, id: w.id ?? randomUUID() }));
    return created(formView(ctx.col('parqForms').insert({ ...rest, widgets, consent: rest.consent ?? CONSENT, ...next, changeType, createdById: ctx.user.id })));
  });

  // Rule-based generator: standard questions + a bank per selected screening area. Draft only; not saved.
  router.post('/v5/parq-form/generate', { perm: 'plansets.write' }, (ctx) => {
    gate(ctx);
    const b = validate({ areas: S.list(S.oneOf(Object.keys(AREAS)), { required: true, min: 1, max: 7 }), extraNotes: S.str({ max: 300 }) }, ctx.body);
    const widgets = defaultForm().widgets;
    const sig = widgets.pop();
    for (const a of b.areas) for (const text of AREAS[a]) widgets.push(q(text, false));
    widgets.push(sig);
    return { title: 'Physical Activity Readiness Questionnaire', widgets, consent: CONSENT, generator: 'rule-based-dev', areas: b.areas };
  });
  router.get('/v5/parq-form/areas', { perm: 'plansets.read' }, () => Object.keys(AREAS));

  // ---- signing --------------------------------------------------------------------------------------------------------
  router.post('/v5/members/:id/parq/sign', { perm: ['members.write', 'plansets.write'] }, (ctx) => {
    gate(ctx);
    const m = ctx.col('members').get(ctx.params.id);
    if (!m) throw notFound('Member not found');
    const b = validate({
      answers: S.list(S.obj({ widgetId: S.str({ required: true }), answer: S.str({ required: true, max: 500, allowEmpty: true }) }), { required: true, max: 100 }),
      signature: S.str({ required: true, max: 1_000_000 }), agreed: S.bool({ required: true }),
    }, ctx.body);
    if (!b.agreed) throw invalid('Please confirm the declaration to continue');
    const form = current(ctx);
    const byId = new Map(b.answers.map((a) => [a.widgetId, a.answer]));
    const flagged = [];
    for (const w of form.widgets.filter((x) => x.type === 'question')) {
      const a = byId.get(w.id);
      if (w.required && (a === undefined || a === '')) throw invalid('Please answer this question', { widgetId: w.id });
      if (w.answerType === 'yesno' && a !== undefined && !['yes', 'no'].includes(a)) throw invalid('Please answer this question', { widgetId: w.id });
      if (w.answerType === 'yesno' && a === 'yes') flagged.push({ widgetId: w.id, text: w.text, critical: !!w.critical });
    }
    const sig = storeFile(store, { gymId: ctx.gymId, ownerId: ctx.user.id, data: b.signature.replace(/^data:image\/png;base64,/, '') });
    if (sig.mime !== 'image/png') throw invalid('Please draw your signature');
    const riskLevel = flagged.some((f) => f.critical) ? 'high' : flagged.length ? 'moderate' : 'low';
    const sub = ctx.col('parqSubmissions').insert({
      memberId: m.id, formId: form.id, formMajor: form.major, formMinor: form.minor, answers: b.answers, flagged, riskLevel, signatureFileId: sig.id, signedById: ctx.user.id,
      signedAt: new Date().toISOString(),
    });
    ctx.col('members').update(m.id, { parqSignedAt: sub.signedAt, parqMajor: form.major, parqSubmissionId: sub.id, parqRisk: riskLevel });
    return created({ ...sub, signatureUrl: `/v5/files/${sig.id}`, version: versionLabel(form) });
  });

  router.get('/v5/parq/submissions', { perm: 'members.read' }, (ctx) => {
    gate(ctx);
    return ctx.col('parqSubmissions').find((s) => !ctx.query.memberId || s.memberId === ctx.query.memberId).map((s) => ({ ...s, signatureUrl: `/v5/files/${s.signatureFileId}`, version: `${s.formMajor}.${s.formMinor}` })).sort((a, b) => b.signedAt.localeCompare(a.signedAt));
  });
  router.get('/v5/parq/submissions/:id', { perm: 'members.read' }, (ctx) => {
    gate(ctx);
    const s = ctx.col('parqSubmissions').get(ctx.params.id);
    if (!s) throw notFound('Submission not found');
    const form = ctx.col('parqForms').get(s.formId);
    return { ...s, signatureUrl: `/v5/files/${s.signatureFileId}`, version: `${s.formMajor}.${s.formMinor}`, form: form ? formView(form) : null };
  });

  // Members need re-signing after a MAJOR revision only.
  router.get('/v5/parq/status', { perm: 'members.read' }, (ctx) => {
    gate(ctx);
    const f = current(ctx);
    const members = ctx.col('members').all();
    return {
      currentVersion: versionLabel(f), signed: members.filter((m) => m.parqMajor === f.major).length,
      needsResign: members.filter((m) => m.parqSignedAt && m.parqMajor !== f.major).length, unsigned: members.filter((m) => !m.parqSignedAt).length,
    };
  });
}
