// A bot challenge in front of the two PUBLIC endpoints that text any number a caller names (portal code, partner registration).
// Cloudflare Turnstile: the app or page obtains a token, this server asks Cloudflare to confirm it. Off until TURNSTILE_SECRET is set;
// once set, the token is mandatory. The sending budgets in auth.js are the hard cost ceiling either way; this stops cheap automation
// from spending them.
import { ApiError } from './errors.js';

const VERIFY = 'https://challenges.cloudflare.com/turnstile/v0/siteverify';

export const challengeEnabled = (config) => !!config.challenge?.secret;

/** Throws unless the token is good. A no-op while no secret is configured. */
export async function requireChallenge(config, token, ip) {
  if (!challengeEnabled(config)) return;
  const fail = () => new ApiError(403, 'CHALLENGE_FAILED', 'Please complete the check and try again.');
  if (typeof token !== 'string' || token.length < 10 || token.length > 2048) throw fail();
  const f = config.challenge.fetchImpl ?? globalThis.fetch;
  let ok = false;
  try {
    const res = await f(VERIFY, {
      method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ secret: config.challenge.secret, response: token, ...(ip ? { remoteip: ip } : {}) }).toString(), signal: AbortSignal.timeout(5000),
    });
    ok = res.ok && (await res.json()).success === true;
  } catch { ok = false; } // the challenge provider being down must not open the door
  if (!ok) throw fail();
}
