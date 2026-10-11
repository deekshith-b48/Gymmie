// A member's access code, from the gym's side: issued when a member is registered, re-issued (the old code stops working at
// once) or revoked. The member signs in with it at POST /v5/member/auth/code (routes/signin.js).
import { conflict, notFound } from '../errors.js';
import { noContent } from '../http.js';
import { nowIso } from '../db.js';
import { newAccessCode } from '../domain/access_code.js';

/** A code no other member of this gym holds. Returns { code, hash }. */
export function allocateAccessCode(store, config, gym) {
  return newAccessCode(config.jwtSecret, gym.code, (hash) => !!store.get(
    "SELECT 1 FROM docs WHERE gym_id = ? AND collection = 'members' AND json_extract(data, '$.accessCodeHash') = ? LIMIT 1", gym.id, hash,
  ));
}

export function registerAccessRoutes({ router, store, config, memberSessions, limiter }) {
  const find = (ctx) => {
    const m = ctx.col('members').get(ctx.params.id);
    if (!m) throw notFound('Member not found');
    return m;
  };

  // Issues a new code for the member. Any earlier code and every signed-in session of the member end. The code is in this answer only.
  router.post('/v5/members/:id/access-code', { perm: 'members.write' }, (ctx) => {
    limiter.check(`acode:${ctx.gymId}`, 60, 600);
    const m = find(ctx);
    if (m.blocked) throw conflict('This member is blocked. Unblock them first.');
    const { code, hash } = allocateAccessCode(store, config, ctx.gym);
    store.tx(() => {
      ctx.col('members').update(m.id, { accessCodeHash: hash, accessCodeIssuedAt: nowIso(), accessCodeRevokedAt: undefined, accessCodeIssuedById: ctx.user.id });
      memberSessions.revokeMember(ctx.gymId, m.id);
    });
    return { memberId: m.id, accessCode: code, issuedAt: ctx.col('members').get(m.id).accessCodeIssuedAt };
  });

  // Takes the code away without issuing another: the member can no longer sign in with it, and is signed out everywhere.
  router.delete('/v5/members/:id/access-code', { perm: 'members.write' }, (ctx) => {
    const m = find(ctx);
    store.tx(() => {
      ctx.col('members').update(m.id, { accessCodeHash: undefined, accessCodeRevokedAt: nowIso() });
      memberSessions.revokeMember(ctx.gymId, m.id);
    });
    return noContent();
  });
}
