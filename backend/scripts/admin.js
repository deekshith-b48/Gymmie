#!/usr/bin/env node
// Operator console for the one person running Gymmie. Works on the database file directly, so run it on the server:
//   DB_FILE=/data/gymmie.sqlite node scripts/admin.js <command>
//   gyms                         list gyms with plan, end date, members and credits
//   revenue [YYYY-MM]            paid orders (all time, or one month), total and GST
//   grant-plan <code> <PLAN> [days]    set a plan (STARTER|GROWTH|PRO) for a gym code, default 30 days from today or its end date
//   grant-credits <code> <n>     add message credits
//   extend <code> <days>         extend the subscription (free days, goodwill)
//   delete-gym <code> <code>     erase a gym and all its data (support request to close an owner account)
//   enable <code> <FLAG> | disable <code> <FLAG>   switch a feature flag for a gym
import { openDb, nowIso } from '../src/db.js';
import { loadConfig } from '../src/config.js';
import { addDays, todayIn } from '../src/domain/dates.js';
import { SUBSCRIPTION_PLANS } from '../src/domain/catalog.js';
import { loadGym, saveGym } from '../src/helpers.js';
import { addCredits } from '../src/domain/notify.js';

const config = loadConfig();
const store = openDb(config.dbFile);
const [cmd, ...args] = process.argv.slice(2);
const byCode = (code) => {
  const row = store.get('SELECT id FROM gyms WHERE code = ?', String(code));
  if (!row) { console.error(`No gym with code ${code}`); process.exit(1); }
  return loadGym(store, row.id);
};
const table = (rows) => console.table(rows);

switch (cmd) {
  case 'gyms': {
    table(store.all('SELECT id FROM gyms ORDER BY created_at').map(({ id }) => {
      const g = loadGym(store, id);
      return { code: g.code, name: g.name, city: g.city, plan: g.subscription?.plan ?? '-', ends: g.subscription?.endsAt ?? '-', members: store.col(id, 'members').count(), credits: g.creditBalance ?? 0 };
    }));
    break;
  }
  case 'revenue': {
    const month = args[0];
    const rows = [];
    for (const { id } of store.all('SELECT id FROM gyms')) {
      for (const o of store.col(id, 'orders').find((x) => x.status === 'paid' && (!month || (x.completedAt ?? '').startsWith(month)))) {
        rows.push({ date: (o.completedAt ?? '').slice(0, 10), gym: loadGym(store, id).name, type: o.type, item: o.ref, amount: o.amount, gst: o.tax?.gst ?? 0, invoice: o.invoiceNo ?? '', provider: o.provider });
      }
    }
    rows.sort((a, b) => a.date.localeCompare(b.date));
    table(rows);
    console.log(`Total ₹${rows.reduce((s, r) => s + r.amount, 0)}  (GST ₹${rows.reduce((s, r) => s + r.gst, 0).toFixed(2)})  across ${rows.length} orders`);
    break;
  }
  case 'grant-plan': {
    const [code, planName, days = '30'] = args;
    const plan = SUBSCRIPTION_PLANS.find((p) => p.plan === String(planName).toUpperCase());
    if (!plan) { console.error('Plan must be STARTER, GROWTH or PRO'); process.exit(1); }
    const g = byCode(code);
    const today = todayIn(g.timezone);
    const base = g.subscription?.endsAt >= today ? g.subscription.endsAt : today;
    saveGym(store, g.id, { subscription: { ...(g.subscription ?? {}), plan: plan.plan, startsAt: g.subscription?.startsAt ?? today, endsAt: addDays(base, Number(days)), limits: plan.limits } });
    console.log(`${g.name}: ${plan.plan} until ${addDays(base, Number(days))}`);
    break;
  }
  case 'extend': {
    const g = byCode(args[0]);
    const today = todayIn(g.timezone);
    const base = g.subscription?.endsAt >= today ? g.subscription.endsAt : today;
    saveGym(store, g.id, { subscription: { ...(g.subscription ?? {}), endsAt: addDays(base, Number(args[1])) } });
    console.log(`${g.name}: now ends ${addDays(base, Number(args[1]))}`);
    break;
  }
  case 'grant-credits': {
    const g = byCode(args[0]);
    addCredits({ store, gymId: g.id, gym: g, col: (n) => store.col(g.id, n) }, Number(args[1]), `admin:${nowIso()}`, 'grant');
    console.log(`${g.name}: +${args[1]} credits`);
    break;
  }
  case 'enable':
  case 'disable': {
    const g = byCode(args[0]);
    saveGym(store, g.id, { features: { ...g.features, [args[1]]: cmd === 'enable' } });
    console.log(`${g.name}: ${args[1]} ${cmd}d`);
    break;
  }
  case 'delete-gym': {
    // Erases a gym and everything in it (members, payments, files, staff links). Asks for the code twice on purpose.
    const [code, again] = args;
    const g = byCode(code);
    if (again !== code) { console.error(`This permanently deletes "${g.name}" and all its data. Repeat the code to confirm: delete-gym ${code} ${code}`); process.exit(1); }
    store.tx(() => {
      for (const t of ['docs', 'files', 'counters', 'member_sessions', 'member_state', 'gym_users']) store.run(`DELETE FROM ${t} WHERE gym_id = ?`, g.id);
      store.run('DELETE FROM gyms WHERE id = ?', g.id);
    });
    console.log(`Deleted gym ${g.name} (${code}).`);
    break;
  }
  default:
    console.log('Commands: gyms | revenue [YYYY-MM] | grant-plan <code> <PLAN> [days] | extend <code> <days> | grant-credits <code> <n> | enable|disable <code> <FLAG>');
}
store.close();
