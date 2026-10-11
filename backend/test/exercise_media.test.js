// Exercise pictures and animations: the owner's library and the member profile only carry media URLs when the operator
// has switched exercise media on (it needs a licence from gymvisual.com), and then both a still and a clip are given.
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { boot, data } from './helpers.js';

const BASE = 'https://media.example.com';
const hs = [];
const make = async (opts) => { const h = await boot({ openGymPublicUrl: BASE, openGymSsoSecret: 'x'.repeat(40), ...opts }); hs.push(h); return h; };
after(async () => { for (const h of hs) await h.close(); });

test('with media on, an openGym exercise carries a still and a matching clip', async () => {
  const h = await make({ exerciseMediaLicensed: true });
  const o = await h.owner({ phone: '+919876509301' });
  const list = data(await o.as('GET', '/v5/exercises?q=1%202%20stick'));
  const e = list.find((x) => x.id === 'og:5965');
  assert.ok(e, 'the exercise is in the library');
  assert.equal(e.imageUrl, `${BASE}/exercise-media/still/5965.webp`);
  assert.equal(e.clipUrl, `${BASE}/exercise-media/clip/5965.mp4`);
  assert.equal(e.clip, undefined, 'the raw path is not leaked next to the URLs');
});

test('with media off (the default) there is no picture or clip URL at all', async () => {
  const h = await make({});
  const o = await h.owner({ phone: '+919876509302' });
  const list = data(await o.as('GET', '/v5/exercises?q=stick'));
  const e = list.find((x) => x.id === 'og:5965');
  assert.ok(e);
  assert.equal(e.imageUrl, undefined);
  assert.equal(e.clipUrl, undefined);
});

test('the member app is only given a media host when media is on', async () => {
  for (const [on, want] of [[true, BASE], [false, null]]) {
    const h = await make({ exerciseMediaLicensed: on });
    const o = await h.owner({ phone: on ? '+919876509303' : '+919876509304' });
    const d = JSON.parse(h.store.get('SELECT data FROM gyms WHERE id = ?', o.gym).data);
    h.store.run('UPDATE gyms SET data = ? WHERE id = ?', JSON.stringify({ ...d, features: { ...d.features, MEMBER_APP: true } }), o.gym);
    const plan = data(await o.as('POST', '/v5/memberships/plans', { name: 'P', price: 100, durationDays: 30 }));
    await o.as('POST', '/v5/members', { name: 'Media Member', phone: on ? '+919900009301' : '+919900009302', membership: { planId: plan.id, amountReceived: 100 } });
    const r = await h.call('POST', '/v5/auth/signin/otp', { body: { phone: on ? '+919900009301' : '+919900009302' } });
    const v = await h.call('POST', '/v5/auth/signin/verify', { body: { requestId: data(r).requestId, otp: '123456' } });
    const me = data(await h.call('GET', '/v5/member/me', { token: data(v).accessToken }));
    assert.equal(me.mediaBase, want);
  }
});
