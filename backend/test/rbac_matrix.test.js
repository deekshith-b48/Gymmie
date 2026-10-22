import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { boot, data } from './helpers.js';
import { can } from '../src/auth.js';

let h, owner, stranger, memberToken;
const actors = {};
const pathFor = (route) => route.path.replace(/:[A-Za-z0-9_]+/g, 'matrix-resource');
const invoke = (route, token, gym) => h.call(route.method, pathFor(route), {
  token, gym, ...(['POST', 'PUT', 'PATCH', 'DELETE'].includes(route.method) ? { body: {} } : {}),
});

before(async () => {
  h = await boot();
  owner = await h.owner({ phone: '+919833330001', gymName: 'Matrix Gym' });
  stranger = await h.owner({ phone: '+919833330002', gymName: 'Other Matrix Gym' });
  for (const [i, role] of ['manager', 'staff', 'trainer'].entries()) {
    const phone = `+91983333001${i}`;
    assert.equal((await owner.as('POST', '/v5/gyms/staffs', { name: role, phone, role })).status, 201);
    actors[role] = await h.loginAs(phone, owner.gym);
  }
  const gym = JSON.parse(h.store.get('SELECT data FROM gyms WHERE id = ?', owner.gym).data);
  gym.features.MEMBER_APP = true;
  h.store.run('UPDATE gyms SET data = ? WHERE id = ?', JSON.stringify(gym), owner.gym);
  const m = data(await owner.as('POST', '/v5/members', { name: 'Matrix Member', phone: '+919833330099' }));
  const issued = await owner.as('POST', `/v5/members/${m.id}/access-code`);
  assert.equal(issued.status, 200, JSON.stringify(issued.body));
  const signed = await h.call('POST', '/v5/member/auth/code', { body: { code: data(issued).accessCode } });
  assert.equal(signed.status, 200, JSON.stringify(signed.body));
  memberToken = data(signed).accessToken;
});
after(async () => { if (h) await h.close(); });

test('all registered protected routes reject anonymous requests', async () => {
  for (const route of h.app.router.routes.filter(r => r.opts.auth !== 'none')) {
    const response = await invoke(route);
    assert.equal(response.status, 401, `${route.method} ${route.path}`);
  }
});

test('member sessions cannot enter any staff or gym endpoint', async () => {
  for (const route of h.app.router.routes.filter(r => !['none', 'member'].includes(r.opts.auth))) {
    const response = await invoke(route, memberToken, owner.gym);
    assert.equal(response.status, 403, `${route.method} ${route.path}`);
  }
});

test('owner sessions cannot impersonate members through member endpoints', async () => {
  for (const route of h.app.router.routes.filter(r => r.opts.auth === 'member')) {
    const response = await invoke(route, owner.token, owner.gym);
    assert.equal(response.status, 403, `${route.method} ${route.path}`);
  }
});

test('every gym endpoint refuses an owner belonging to a different gym', async () => {
  for (const route of h.app.router.routes.filter(r => r.opts.auth === 'gym')) {
    const response = await invoke(route, stranger.token, owner.gym);
    assert.equal(response.status, 403, `${route.method} ${route.path}`);
  }
});

for (const role of ['manager', 'staff', 'trainer']) {
  test(`${role}: every route requiring an ungranted permission is denied`, async () => {
    let checked = 0;
    for (const route of h.app.router.routes.filter(r => r.opts.auth === 'gym' && r.opts.perm)) {
      const permissions = Array.isArray(route.opts.perm) ? route.opts.perm : [route.opts.perm];
      if (permissions.some(permission => can(role, permission))) continue;
      const response = await invoke(route, actors[role].token, owner.gym);
      assert.equal(response.status, 403, `${role} ${route.method} ${route.path}`);
      checked++;
    }
    assert.ok(checked > 0);
  });
}

test('staff role changes and removal take effect on existing access tokens', async () => {
  const payload = h.app.auth.verifyAccess(actors.manager.token);
  h.store.run("UPDATE gym_users SET role = 'trainer' WHERE user_id = ? AND gym_id = ?", payload.sub, owner.gym);
  assert.equal((await actors.manager.as('GET', '/v5/members/transactions')).status, 403);
  h.store.run("UPDATE gym_users SET status = 'inactive' WHERE user_id = ? AND gym_id = ?", payload.sub, owner.gym);
  assert.equal((await actors.manager.as('GET', '/v5/members')).status, 403);
  assert.equal((await owner.as('GET', '/v5/members')).status, 200);
});
