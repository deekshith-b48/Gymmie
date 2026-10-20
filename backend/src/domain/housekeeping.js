// Deletes what no longer has a reason to exist, so phone numbers, addresses and sign-in records are not kept forever.
//   sign-in codes (they hold the phone number)      kept 26 h (the sending budgets look back 24 h), then deleted
//   abuse-guard rows                                  kept 48 h after the last failure
//   staff and member sessions                         deleted 7 days after they expired, 30 days after they were rotated or revoked
//   security events                                   kept 180 days
//   consent records (they hold the address a person accepted the terms from)  kept: they are the legal evidence of consent
//   messages in the outbox                            sent/failed ones deleted after 90 days
const DAY = 86_400_000;

export function purgeExpired(store, now = Date.now()) {
  const n = {};
  n.otpRequests = store.run('DELETE FROM otp_requests WHERE created_at < ?', now - 26 * 3600_000).changes;
  n.otpGuard = store.run('DELETE FROM otp_guard WHERE last_fail < ? AND locked_until < ?', now - 2 * DAY, now).changes;
  for (const t of ['sessions', 'member_sessions']) {
    n[t] = store.run(`DELETE FROM ${t} WHERE expires_at < ? OR ((revoked = 1 OR replaced = 1) AND created_at < ?)`, now - 7 * DAY, now - 30 * DAY).changes;
  }
  n.securityEvents = store.run('DELETE FROM security_events WHERE at < ?', now - 180 * DAY).changes;
  const cutoff = new Date(now - 90 * DAY).toISOString();
  n.outbox = store.run(
    `DELETE FROM docs WHERE collection = 'outbox' AND json_extract(data, '$.status') IN ('sent', 'failed') AND created_at < ?`, cutoff,
  ).changes;
  return n;
}
