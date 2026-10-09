import { loadConfig } from './config.js';
import { openDb } from './db.js';
import { createApp } from './app.js';
import { createHttpServer } from './http.js';
import { processDueBroadcasts } from './routes/messaging.js';

export function startServer(overrides = {}) {
  const config = loadConfig(overrides);
  const store = openDb(config.dbFile);
  const app = createApp({ store, config });
  const server = createHttpServer(app.handle, config);
  const timer = setInterval(() => { try { processDueBroadcasts(store); } catch (e) { console.error('[scheduler]', e); } }, 30_000);
  timer.unref();
  return new Promise((resolve) => {
    server.listen(config.port, config.host, () => {
      const addr = server.address();
      resolve({ server, store, config, app, port: addr.port, close: () => new Promise((r) => { clearInterval(timer); server.close(() => { store.close(); r(); }); }) });
    });
  });
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const s = await startServer();
  console.log(`Gymmie dev backend listening on http://${s.config.host}:${s.port}  (env=${s.config.env}, otp-dev=${s.config.devExposeOtp})`);
  console.log('This is a DEVELOPMENT backend for the reconstructed app, not the original DGymBook service.');
}
