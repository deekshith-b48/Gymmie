import { loadConfig } from './config.js';
import { openDb } from './db.js';
import { createApp } from './app.js';
import { createHttpServer } from './http.js';
import { processOutbox } from './domain/delivery.js';
import { processDueBroadcasts, processExpiryReminders } from './routes/messaging.js';

export function startServer(overrides = {}) {
  const config = loadConfig(overrides);
  const store = openDb(config.dbFile);
  const app = createApp({ store, config });
  const server = createHttpServer(app.handle, config);
  const timer = setInterval(() => { try { processDueBroadcasts(store); } catch (e) { console.error('[scheduler]', e); } }, 30_000);
  timer.unref();
  // membership expiry alerts: checked every 15 minutes (each membership is warned once)
  const expiryTimer = setInterval(() => { try { processExpiryReminders(store); } catch (e) { console.error('[expiry]', e); } }, 15 * 60_000);
  expiryTimer.unref();
  // real delivery of recorded messages (only when a provider is configured)
  let busy = false;
  const deliveryTimer = setInterval(async () => {
    if (busy || !app.messenger.anyText) return;
    busy = true;
    try { await processOutbox(store, app.messenger); } catch (e) { console.error('[delivery]', e); } finally { busy = false; }
  }, 10_000);
  deliveryTimer.unref();
  return new Promise((resolve) => {
    server.listen(config.port, config.host, () => {
      const addr = server.address();
      resolve({ server, store, config, app, port: addr.port, close: () => new Promise((r) => { clearInterval(timer); clearInterval(expiryTimer); clearInterval(deliveryTimer); server.close(() => { store.close(); r(); }); }) });
    });
  });
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const s = await startServer();
  console.log(JSON.stringify({ level: 'info', msg: 'listening', host: s.config.host, port: s.port, env: s.config.env, otpDev: s.config.devExposeOtp, payments: s.app.router && s.config.payments.keyId ? 'razorpay' : (s.config.devPayments ? 'dev' : 'none') }));
  // Deploys send SIGTERM: stop taking requests, let running ones finish, fold the WAL into the main file, then exit.
  let closing = false;
  const stop = async (sig) => {
    if (closing) return;
    closing = true;
    console.log(JSON.stringify({ level: 'info', msg: 'shutting down', signal: sig }));
    const force = setTimeout(() => process.exit(1), 15_000);
    force.unref();
    try {
      s.store.db.exec('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch { /* closing anyway */ }
    await s.close();
    process.exit(0);
  };
  process.on('SIGTERM', () => stop('SIGTERM'));
  process.on('SIGINT', () => stop('SIGINT'));
}
