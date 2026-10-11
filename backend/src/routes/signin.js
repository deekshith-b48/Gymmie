// One sign-in for everybody. The person types a phone number (or a staff email), proves it with ONE code, and only then
// does the server say who that number is: gym staff, a gym member, or both (or several gyms), in which case the app
// asks which one to open. Nothing about who has an account is revealed before the code is proven: an unknown number
// gets exactly the same answer as a known one. The staff and member principals underneath are unchanged (own tokens,
// own sessions, own route guards); this only decides which of them to start.
import { randomUUID } from 'node:crypto';
import { S, validate } from '../validate.js';
import { forbidden, invalid } from '../errors.js';
import { publicUser, userGyms } from '../helpers.js';
import { findMembersByPhone, makeSelectionToken, memberAllowed, readSelectionToken } from '../member_auth.js';
import { gymBriefForMember } from './member_app.js';
import { hashCode, parseCode } from '../domain/access_code.js';

const maskPhone = (t) => `${t.slice(0, 3)}${'*'.repeat(Math.max(0, t.length - 6))}${t.slice(-3)}`;

export function registerSigninRoutes({ router, store, auth, config, limiter, memberSessions }) {
  const staffBundle = (user, device) => ({
    status: 'signed_in', kind: 'staff',
    ...auth.startSession(user.id, device), tokenType: 'Bearer', user: publicUser(user), gyms: userGyms(store, user.id),
  });
  const memberBundle = (c, device, phone) => {
    const ok = memberAllowed(store, c.gymId, c.memberId, phone);
    return {
      status: 'signed_in', kind: 'member',
      ...memberSessions.start({ gymId: c.gymId, memberId: c.memberId, phone }, device),
      member: { id: ok.member.id, name: ok.member.name }, gym: gymBriefForMember(ok.gym),
    };
  };

  // Who can this verified phone be right now? Judged again at verification: a person may have been blocked since the code was sent.
  const rolesFor = (phone, candidates, staffUserId) => {
    const user = staffUserId ? store.get('SELECT * FROM users WHERE id = ?', staffUserId) : null;
    const staff = user && !user.disabled ? user : null;
    const members = (candidates ?? []).filter((c) => memberAllowed(store, c.gymId, c.memberId, phone));
    return { staff, members };
  };

  router.post('/v5/auth/signin/otp', { auth: 'none' }, (ctx) => {
    const b = validate({ phone: S.phone({ required: true }), channel: S.oneOf(['sms', 'whatsapp']), gymCode: S.str({ max: 12 }) }, ctx.body);
    limiter.check(`sin-ip:${ctx.ip}`, 30, 600);
    limiter.check(`sin-target:${b.phone}`, 6, 600);
    const channel = b.channel ?? 'sms';
    const shape = { expiresIn: config.otpTtlSec, resendIn: config.otpResendSec, maskedTarget: maskPhone(b.phone), channel };
    const staff = auth.findUserByIdentifier({ phone: b.phone });
    const candidates = findMembersByPhone(store, b.phone, b.gymCode);
    const staffId = staff && !staff.disabled ? staff.id : null;
    if (!staffId && !candidates.length) return { requestId: randomUUID(), ...shape }; // same answer: nothing is revealed
    const otp = auth.createOtp({ purpose: 'signin', channel, target: b.phone, userId: staffId ?? undefined, context: { staffUserId: staffId, candidates } });
    return { ...shape, requestId: otp.requestId, devOtp: config.devExposeOtp ? otp.devOtp : undefined };
  });

  router.post('/v5/auth/signin/verify', { auth: 'none' }, (ctx) => {
    const b = validate({ requestId: S.str({ required: true }), otp: S.str({ required: true, min: 4, max: 8 }), device: S.str({ max: 120 }) }, ctx.body);
    limiter.check(`sinv-ip:${ctx.ip}`, 60, 600);
    const r = auth.verifyOtp(b.requestId, b.otp, 'signin');
    const { staff, members } = rolesFor(r.target, r.context.candidates, r.context.staffUserId);
    if (staff) store.run('UPDATE users SET phone_verified = 1 WHERE id = ?', staff.id);
    if (!staff && !members.length) throw forbidden('Access is not available for this number. Ask your gym.');
    if (staff && !members.length) {
      store.run("UPDATE gym_users SET status = 'active' WHERE user_id = ? AND status = 'invited'", staff.id);
      return staffBundle(store.get('SELECT * FROM users WHERE id = ?', staff.id), b.device);
    }
    if (!staff && members.length === 1) return memberBundle(members[0], b.device, r.target);
    // more than one way in: the person chooses (the choice is signed, so it cannot be forged or widened)
    const options = [];
    if (staff) options.push({ id: 'staff', kind: 'staff', title: 'Manage a gym', subtitle: 'Owner or staff account' });
    for (const c of members) {
      const ok = memberAllowed(store, c.gymId, c.memberId, r.target);
      options.push({ id: `member:${c.gymId}`, kind: 'member', title: ok.gym.name, subtitle: ['Member', ok.gym.city].filter(Boolean).join(' · ') });
    }
    return { status: 'choose', options, selectionToken: makeSelectionToken(config.jwtSecret, { p: r.target, s: staff?.id ?? null, c: members }) };
  });

  router.post('/v5/auth/signin/choose', { auth: 'none' }, (ctx) => {
    const b = validate({ selectionToken: S.str({ required: true, max: 4000 }), option: S.str({ required: true, max: 80 }), device: S.str({ max: 120 }) }, ctx.body);
    limiter.check(`sinv-ip:${ctx.ip}`, 60, 600);
    const t = readSelectionToken(config.jwtSecret, b.selectionToken);
    if (b.option === 'staff') {
      const { staff } = rolesFor(t.p, [], t.s);
      if (!staff) throw forbidden('Staff access is not available for this number.');
      return staffBundle(store.get('SELECT * FROM users WHERE id = ?', staff.id), b.device);
    }
    if (!b.option.startsWith('member:')) throw invalid('Unknown choice');
    const c = (t.c ?? []).find((x) => `member:${x.gymId}` === b.option);
    if (!c || !memberAllowed(store, c.gymId, c.memberId, t.p)) throw forbidden('Member access is not available for this gym.');
    return memberBundle(c, b.device, t.p);
  });

  // ---- sign in with the access code the gym gave the member ----------------------------------------------------------------------
  // One answer for every failure (wrong, revoked, blocked, gym unknown, member app off) so the screen cannot be used to learn which
  // gyms or codes exist. Tries are limited per address, per gym, and per code guess pattern.
  router.post('/v5/member/auth/code', { auth: 'none' }, (ctx) => {
    const b = validate({ code: S.str({ required: true, max: 40 }), device: S.str({ max: 120 }) }, ctx.body);
    limiter.check(`mcode-ip:${ctx.ip}`, 20, 600);
    const bad = () => forbidden('This access code is not valid. Ask your gym for a new one.');
    const parsed = parseCode(b.code);
    if (!parsed) throw bad();
    limiter.check(`mcode-gym:${parsed.gymCode}`, 120, 600); // a gym under guessing attack slows down for everyone, not just one phone
    limiter.check(`mcode-gym-ip:${parsed.gymCode}:${ctx.ip}`, 10, 600);
    const gymRow = store.get('SELECT id FROM gyms WHERE code = ?', parsed.gymCode);
    if (!gymRow) throw bad();
    const hash = hashCode(config.jwtSecret, parsed.gymCode, parsed.tail);
    const row = store.get(
      "SELECT id FROM docs WHERE gym_id = ? AND collection = 'members' AND deleted_at IS NULL AND json_extract(data, '$.accessCodeHash') = ? LIMIT 1", gymRow.id, hash,
    );
    const member = row ? store.col(gymRow.id, 'members').get(row.id) : null;
    if (!member || !memberAllowed(store, gymRow.id, member.id, member.phone)) throw bad();
    return memberBundle({ gymId: gymRow.id, memberId: member.id }, b.device, member.phone);
  });
}
