import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { openDb, SCHEMA_VERSION } from '../src/db.js';
import { boot, data } from './helpers.js';

test('file-backed transactions roll back nested writes and counters, and keep tenant boundaries after reopen', () => {
  const dir = mkdtempSync(join(tmpdir(), 'gymmie-database-'));
  const file = join(dir, 'test.sqlite');
  let store;
  try {
    store = openDb(file);
    for (const id of ['gym-a', 'gym-b']) {
      store.run('INSERT INTO gyms(id, code, data, created_at, updated_at) VALUES (?,?,?,?,?)', id, id, '{}', 'now', 'now');
    }
    const members = store.col('gym-a', 'members');
    const a = members.insert({ name: 'Alice', balance: 100 });
    assert.throws(() => store.tx(() => {
      members.update(a.id, { balance: 0 });
      store.tx(() => members.insert({ name: 'Must roll back' }));
      store.nextCounter('gym-a', 'invoices');
      throw new Error('payment failed');
    }), /payment failed/);
    assert.equal(members.get(a.id).balance, 100);
    assert.equal(members.count(), 1);
    assert.equal(store.nextCounter('gym-a', 'invoices'), 1);
    const other = store.col('gym-b', 'members');
    assert.equal(other.get(a.id), null);
    assert.equal(other.update(a.id, { name: 'Hijacked' }), null);
    assert.equal(other.remove(a.id), false);
    assert.equal(store.col('gym-a', 'plans').get(a.id), null);
    store.close();
    store = openDb(file);
    assert.equal(store.get('PRAGMA integrity_check').integrity_check, 'ok');
    assert.deepEqual(store.all('PRAGMA foreign_key_check'), []);
    assert.equal(store.get('PRAGMA user_version').user_version, SCHEMA_VERSION);
    assert.equal(store.col('gym-a', 'members').get(a.id).name, 'Alice');
    assert.equal(store.col('gym-b', 'members').count(), 0);
    store.col('gym-a', 'members').remove(a.id);
    assert.equal(store.col('gym-a', 'members').get(a.id), null);
    assert.equal(store.col('gym-a', 'members').getAny(a.id).name, 'Alice');
  } finally {
    store?.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test('owner finance, member workouts and auth survive a real database restart without cross-member writes', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'gymmie-restart-'));
  const file = join(dir, 'test.sqlite');
  let h;
  try {
    h = await boot({ dbFile: file });
    const o = await h.owner({ phone: '+919844440001', gymName: 'Durable Gym' });
    const gym = JSON.parse(h.store.get('SELECT data FROM gyms WHERE id = ?', o.gym).data);
    gym.features.MEMBER_APP = true;
    h.store.run('UPDATE gyms SET data = ? WHERE id = ?', JSON.stringify(gym), o.gym);
    const p = data(await o.as('POST', '/v5/memberships/plans', { name: 'Monthly', price: 1000, durationDays: 30 }));
    const a = data(await o.as('POST', '/v5/members', { name: 'Durable Alice', phone: '+919844440002', membership: { planId: p.id, amountReceived: 400, paymentType: 'cash' } }));
    const b = data(await o.as('POST', '/v5/members', { name: 'Private Bob', phone: '+919844440003' }));
    const code = data(await o.as('POST', `/v5/members/${a.id}/access-code`)).accessCode;
    const login = await h.call('POST', '/v5/member/auth/code', { body: { code } });
    assert.equal(login.status, 200, JSON.stringify(login.body));
    const token = data(login).accessToken;
    const state = { unit: 'kg', workouts: [{ id: 'completed-workout', d: '2026-10-21', entries: [{ id: 'og:1', sets: [{ r: 10, w: 20, done: true }] }] }], routines: [], customExercises: [] };
    const saved = await h.call('PUT', '/v5/member/data', { token, body: { state, baseRev: 0, memberId: b.id, gymId: 'wrong-gym' } });
    assert.equal(saved.status, 200, JSON.stringify(saved.body));
    assert.equal(h.store.get('SELECT rev FROM member_state WHERE gym_id = ? AND member_id = ?', o.gym, a.id).rev, 1);
    assert.equal(h.store.get('SELECT rev FROM member_state WHERE gym_id = ? AND member_id = ?', o.gym, b.id), undefined);
    const finance = await o.as('GET', '/v5/members/transactions');
    assert.equal(finance.status, 200, JSON.stringify(finance.body));
    const beforeFinance = data(finance);
    assert.ok(beforeFinance.length > 0);
    const beforeMember = data(await o.as('GET', `/v5/members/${a.id}`));
    const beforeLog = data(await h.call('GET', '/v5/member/data', { token }));
    assert.equal(beforeLog.state.workouts[0].id, 'completed-workout');
    // Exercise the actual online-backup CLI while the WAL-backed API is running.
    const backup = spawnSync(process.execPath, [fileURLToPath(new URL('../scripts/backup.js', import.meta.url))], {
      env: { ...process.env, NODE_ENV: 'development', JWT_SECRET: 'backup-test-secret', DB_FILE: file, BACKUP_DIR: join(dir, 'backups') },
      encoding: 'utf8',
    });
    assert.equal(backup.status, 0, backup.stderr);
    const snapshot = openDb(JSON.parse(backup.stdout.trim()).file);
    try {
      assert.equal(snapshot.get('PRAGMA integrity_check').integrity_check, 'ok');
      assert.deepEqual(snapshot.all('PRAGMA foreign_key_check'), []);
      assert.equal(snapshot.col(o.gym, 'members').get(a.id).name, 'Durable Alice');
      assert.ok(snapshot.col(o.gym, 'transactions').count() > 0);
      const log = snapshot.get('SELECT data FROM member_state WHERE gym_id = ? AND member_id = ?', o.gym, a.id);
      assert.deepEqual(JSON.parse(log.data), beforeLog.state);
    } finally { snapshot.close(); }
    await h.close(); h = null;
    h = await boot({ dbFile: file });
    assert.equal(h.store.get('PRAGMA integrity_check').integrity_check, 'ok');
    assert.deepEqual(h.store.all('PRAGMA foreign_key_check'), []);
    const afterMember = await h.call('GET', `/v5/members/${a.id}`, { token: o.token, gym: o.gym });
    assert.equal(afterMember.status, 200);
    assert.deepEqual(data(afterMember), beforeMember);
    const afterFinance = await h.call('GET', '/v5/members/transactions', { token: o.token, gym: o.gym });
    assert.equal(afterFinance.status, 200);
    assert.deepEqual(data(afterFinance), beforeFinance);
    assert.deepEqual(data(await h.call('GET', '/v5/member/data', { token })), beforeLog);
    const stale = await h.call('PUT', '/v5/member/data', { token, body: { state: { ...state, unit: 'lb' }, baseRev: 0 } });
    assert.equal(stale.status, 409);
    assert.deepEqual(data(await h.call('GET', '/v5/member/data', { token })), beforeLog);
    assert.equal((await h.call('GET', '/v5/member/me', { token: o.token })).status, 403);
    assert.equal((await h.call('GET', '/v5/members', { token, gym: o.gym })).status, 403);
  } finally {
    if (h) await h.close();
    rmSync(dir, { recursive: true, force: true });
  }
});
