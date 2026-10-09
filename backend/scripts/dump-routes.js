// Prints the route table (method, path, auth, required permission) as Markdown.
// Usage: node scripts/dump-routes.js > ../docs/API_ROUTES.md
import { openDb } from '../src/db.js';
import { createApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';

const config = loadConfig({ dbFile: ':memory:', jwtSecret: 'x'.repeat(40), env: 'development' });
const { router } = createApp({ store: openDb(':memory:'), config });
const rows = router.routes.map((r) => ({ method: r.method, path: r.path, auth: r.opts.auth, perm: [].concat(r.opts.perm ?? []).join(' | ') || (r.opts.auth === 'gym' ? '(any gym member)' : '') }));
rows.sort((a, b) => a.path.localeCompare(b.path) || a.method.localeCompare(b.method));
console.log('| Method | Path | Auth | Permission |');
console.log('|---|---|---|---|');
for (const r of rows) console.log(`| ${r.method} | \`${r.path}\` | ${r.auth} | ${r.perm} |`);
console.error(`${rows.length} routes`);
