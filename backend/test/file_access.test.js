// V-17: who may read an uploaded file. Nobody from another gym, no member token, no anonymous caller, and inside a gym a trainer only
// sees the gym logo, colleagues' profile photos and the photos of members assigned to them (never ID cards, documents or other uploads).
import { test, after, before } from 'node:test';
import assert from 'node:assert/strict';
import { boot, data } from './helpers.js';

const PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==', 'base64').toString('base64');
const img = { data: PNG, contentType: 'image/png' };
let h; let A; let B; let roles; let files; let memberToken; let outsiderStaff;
const read = (token, id) => h.call('GET', `/v5/files/${id}`, { token, raw: true }).then((r) => r.status);

before(async () => {
  h = await boot();
  A = await h.owner({ phone: '+919876677001', gymName: 'Files A' });
  B = await h.owner({ phone: '+919876677002', gymName: 'Files B' });
  roles = {};
  const ids = {};
  for (const [role, phone] of [['manager', '+919876677011'], ['staff', '+919876677012'], ['trainer', '+919876677013'], ['trainer2', '+919876677014']]) {
    const st = data(await A.as('POST', '/v5/gyms/staffs', { name: `${role} person`, phone, role: role.replace('2', '') }));
    ids[role] = st.userId;
    roles[role] = await h.loginAs(phone, A.gym);
  }
  // gym settings: member app on so a member can sign in
  const gs = JSON.parse(h.store.get('SELECT data FROM gyms WHERE id = ?', A.gym).data);
  const mine = data(await A.as('POST', '/v5/members', { name: 'Assigned Anna', phone: '+919876677021', trainerId: ids.trainer, photo: img, idCard: img }));
  const other = data(await A.as('POST', '/v5/members', { name: 'Other Olga', phone: '+919876677022', trainerId: ids.trainer2, photo: img, idCard: img }));
  const doc = (m) => h.store.col(A.gym, 'members').get(m.id);
  const generic = data(await A.as('POST', '/v5/files', img));
  await A.as('PATCH', `/v5/gyms/${A.gym}`, { logo: img });
  // staff member's own profile photo
  const photoOwner = await h.call('POST', '/v5/users/self/photo', { token: roles.manager.token, body: img });
  const logoId = JSON.parse(h.store.get('SELECT data FROM gyms WHERE id = ?', A.gym).data).logoFileId;
  files = {
    logo: logoId, assignedPhoto: doc(mine).photoFileId, assignedIdCard: doc(mine).idCardFileId,
    otherPhoto: doc(other).photoFileId, otherIdCard: doc(other).idCardFileId, ownerUpload: generic.id,
    managerProfile: h.store.get('SELECT photo_file_id p FROM users WHERE id = ?', ids.manager).p,
  };
  assert.ok(Object.values(files).every(Boolean), `fixtures created: ${JSON.stringify(Object.keys(files).filter((k) => !files[k]))} ${photoOwner.status}`);
  h.store.run('UPDATE gyms SET data = ? WHERE id = ?', JSON.stringify({ ...JSON.parse(h.store.get('SELECT data FROM gyms WHERE id = ?', A.gym).data), features: { ...gs.features, MEMBER_APP: true } }), A.gym);
  const code = data(await A.as('POST', `/v5/members/${mine.id}/access-code`, {})).accessCode;
  memberToken = (await h.call('POST', '/v5/member/auth/code', { body: { code } })).body.data.accessToken;
  outsiderStaff = await h.owner({ phone: '+919876677003', gymName: 'Outsider Gym' });
});
after(async () => { await h.close(); });

test('nobody from another gym can read any file of this gym, of any kind', async () => {
  for (const [name, id] of Object.entries(files)) {
    assert.equal(await read(B.token, id), 403, `gym B owner / ${name}`);
    assert.equal(await read(outsiderStaff.token, id), 403, `outsider owner / ${name}`);
  }
});

test('an anonymous caller and a gym member token cannot read files at all', async () => {
  for (const [name, id] of Object.entries(files)) {
    assert.equal(await read(undefined, id), 401, `anonymous / ${name}`);
    assert.equal(await read(memberToken, id), 403, `member / ${name}`);
  }
});

test('owner, manager and front desk read the gym\'s files; the uploader and a profile photo\'s owner read theirs', async () => {
  for (const who of [A, roles.manager, roles.staff]) for (const [name, id] of Object.entries(files)) assert.equal(await read(who.token, id), 200, name);
});

test('a trainer reads only the logo, colleagues\' photos and their own members\' photos', async () => {
  const t = roles.trainer.token;
  assert.equal(await read(t, files.logo), 200, 'logo');
  assert.equal(await read(t, files.assignedPhoto), 200, 'assigned member photo');
  assert.equal(await read(t, files.managerProfile), 200, 'colleague profile photo');
  for (const name of ['assignedIdCard', 'otherPhoto', 'otherIdCard', 'ownerUpload']) assert.equal(await read(t, files[name]), 403, name);
});

test('the other trainer sees the mirror image, and neither reads the other\'s members', async () => {
  const t = roles.trainer2.token;
  assert.equal(await read(t, files.otherPhoto), 200);
  assert.equal(await read(t, files.assignedPhoto), 403);
  assert.equal(await read(t, files.otherIdCard), 403);
});

test('a trainer can read a file they uploaded themselves', async () => {
  const up = data(await roles.trainer.as('POST', '/v5/files', img));
  assert.equal(await read(roles.trainer.token, up.id), 200);
  assert.equal(await read(roles.trainer2.token, up.id), 403);
});

test('a made-up or malformed file id is a 404, not an error', async () => {
  assert.equal(await read(A.token, '00000000-0000-0000-0000-000000000000'), 404);
  assert.ok((await read(A.token, '%')) < 500);
});
