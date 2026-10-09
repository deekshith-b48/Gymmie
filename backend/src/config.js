// Runtime configuration for the development backend.
//
// SECURITY MODEL
//  * In production mode (NODE_ENV=production) JWT_SECRET is mandatory and every DEV_* switch is
//    refused at start-up, so the development conveniences cannot leak into a real deployment.
//  * In development mode a random JWT secret is generated once and persisted under data/.
import { randomBytes } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const dataDir = resolve(here, '..', 'data');

function flag(name, fallback = false) {
  const v = process.env[name];
  if (v === undefined) return fallback;
  return ['1', 'true', 'yes', 'on'].includes(v.toLowerCase());
}

export function loadConfig(overrides = {}) {
  const env = overrides.env ?? process.env.NODE_ENV ?? 'development';
  const production = env === 'production';
  const devOtp = overrides.devOtp ?? flag('DEV_EXPOSE_OTP', !production);
  const fixedOtp = overrides.fixedOtp ?? process.env.DEV_FIXED_OTP ?? (production ? '' : '123456');

  if (production) {
    if (!process.env.JWT_SECRET && !overrides.jwtSecret) {
      throw new Error('JWT_SECRET is required when NODE_ENV=production');
    }
    if (flag('DEV_EXPOSE_OTP') || process.env.DEV_FIXED_OTP || flag('DEV_PAYMENTS', false)) {
      throw new Error('DEV_* switches are not allowed when NODE_ENV=production');
    }
  }

  let jwtSecret = overrides.jwtSecret ?? process.env.JWT_SECRET;
  if (!jwtSecret) {
    mkdirSync(dataDir, { recursive: true });
    const file = resolve(dataDir, 'jwt.secret');
    if (existsSync(file)) jwtSecret = readFileSync(file, 'utf8').trim();
    else {
      jwtSecret = randomBytes(48).toString('hex');
      writeFileSync(file, jwtSecret, { mode: 0o600 });
    }
  }

  return {
    env,
    production,
    port: Number(overrides.port ?? process.env.PORT ?? 8787),
    host: overrides.host ?? process.env.HOST ?? '0.0.0.0',
    dbFile: overrides.dbFile ?? process.env.DB_FILE ?? resolve(dataDir, 'dgymbook-dev.sqlite'),
    jwtSecret,
    accessTtlSec: Number(overrides.accessTtlSec ?? process.env.ACCESS_TTL_SEC ?? 15 * 60),
    refreshTtlSec: Number(overrides.refreshTtlSec ?? process.env.REFRESH_TTL_SEC ?? 30 * 24 * 3600),
    otpTtlSec: 10 * 60,
    otpMaxAttempts: 5,
    otpResendSec: overrides.otpResendSec ?? 30,
    // Per-IP request budgets (per 10 minutes). Tests raise these; production keeps the defaults.
    rateLimitScale: overrides.rateLimitScale ?? Number(process.env.RATE_LIMIT_SCALE ?? 1),
    // Development conveniences (refused in production, see above).
    devExposeOtp: devOtp,
    fixedOtp,
    devPayments: overrides.devPayments ?? flag('DEV_PAYMENTS', !production),
    publicBaseUrl: overrides.publicBaseUrl ?? process.env.PUBLIC_BASE_URL ?? '',
    corsOrigin: overrides.corsOrigin ?? process.env.CORS_ORIGIN ?? '*',
    logRequests: overrides.logRequests ?? flag('LOG_REQUESTS', !production),
    // Values served by GET /v5/apps/configs/settings (reconstructed app-config contract).
    appSettings: {
      maintenanceMode: flag('MAINTENANCE_MODE', false),
      minimumAppVersion: process.env.MINIMUM_APP_VERSION ?? '1.0.0',
      minimumSuggestedAppVersion: process.env.MINIMUM_SUGGESTED_APP_VERSION ?? '1.9.0',
      helpCenterUrl: process.env.HELP_CENTER_URL ?? 'https://dgymbook.com/faq',
      companyWhatsappNumber: process.env.COMPANY_WHATSAPP_NUMBER ?? '',
      signUpContactNumber: process.env.SIGN_UP_CONTACT_NUMBER ?? '',
      selfRegistrationPlatform: process.env.SELF_REGISTRATION_PLATFORM ?? '',
    },
  };
}
