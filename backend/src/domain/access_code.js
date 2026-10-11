// A member's access code: "<gym code>-XXXX-XXXX", for example 885409-K7Q2-M9XD. The gym code says which gym, the rest is random
// (32 unambiguous characters, 8 of them: about a trillion codes per gym). Only an HMAC of the code is kept, so a database copy does
// not contain usable codes; the code itself is shown once, to the owner, when it is issued.
import { createHmac, randomInt } from 'node:crypto';

const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no I, O, 0, 1
const hashOf = (secret, normalised) => createHmac('sha256', secret).update(`member-access:${normalised}`).digest('hex');

export const normaliseCode = (input) => String(input ?? '').toUpperCase().replace(/[^A-Z0-9]/g, '');

/** "885409-K7Q2-M9XD" shaped output from the normalised form. */
export const prettyCode = (gymCode, tail) => `${gymCode}-${tail.slice(0, 4)}-${tail.slice(4, 8)}`;

/** Splits a typed code into { gymCode, tail }, or null when it cannot be one of ours. */
export function parseCode(input) {
  const n = normaliseCode(input);
  const m = /^(\d{6})([A-Z2-9]{8})$/.exec(n);
  return m ? { gymCode: m[1], tail: m[2], normalised: n } : null;
}

export function hashCode(secret, gymCode, tail) { return hashOf(secret, `${gymCode}${tail}`); }

/** A fresh code for [gymCode] that no member of the gym holds. Returns { code, hash }. */
export function newAccessCode(secret, gymCode, taken) {
  for (let i = 0; i < 20; i++) {
    let tail = '';
    for (let j = 0; j < 8; j++) tail += ALPHABET[randomInt(ALPHABET.length)];
    const hash = hashCode(secret, gymCode, tail);
    if (!taken(hash)) return { code: prettyCode(gymCode, tail), hash };
  }
  throw new Error('could not allocate an access code');
}
