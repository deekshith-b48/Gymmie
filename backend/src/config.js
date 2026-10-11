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

  const rz = overrides.razorpayKeyId ?? process.env.RAZORPAY_KEY_ID;
  if (production && rz && !(overrides.razorpayWebhookSecret ?? process.env.RAZORPAY_WEBHOOK_SECRET)) {
    throw new Error('RAZORPAY_WEBHOOK_SECRET is required when RAZORPAY_KEY_ID is set (payments are confirmed by webhook)');
  }

  const ogSecret = overrides.openGymSsoSecret ?? process.env.OPENGYM_SSO_SECRET ?? '';
  const ogUrl = overrides.openGymPublicUrl ?? process.env.OPENGYM_PUBLIC_URL ?? '';
  if (ogUrl && ogSecret.length < 32) throw new Error('OPENGYM_SSO_SECRET must be at least 32 characters when OPENGYM_PUBLIC_URL is set');
  if (production && ogUrl && !/^https:\/\//.test(ogUrl)) throw new Error('OPENGYM_PUBLIC_URL must be https:// in production');

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
    dbFile: overrides.dbFile ?? process.env.DB_FILE ?? resolve(dataDir, 'gymmie-dev.sqlite'),
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
    // openGym member module (member-app/): where the app opens it, where this server reaches its
    // API, and the single-sign-on secret shared with it (>= 32 characters).
    openGym: {
      publicUrl: (overrides.openGymPublicUrl ?? process.env.OPENGYM_PUBLIC_URL ?? '').replace(/\/+$/, ''),
      apiUrl: (overrides.openGymApiUrl ?? process.env.OPENGYM_API_URL ?? '').replace(/\/+$/, ''),
      ssoSecret: overrides.openGymSsoSecret ?? process.env.OPENGYM_SSO_SECRET ?? '',
    },
    // Razorpay (real money). Without keys only the development provider exists, and that is refused in production.
    payments: {
      keyId: overrides.razorpayKeyId ?? process.env.RAZORPAY_KEY_ID ?? '',
      keySecret: overrides.razorpayKeySecret ?? process.env.RAZORPAY_KEY_SECRET ?? '',
      webhookSecret: overrides.razorpayWebhookSecret ?? process.env.RAZORPAY_WEBHOOK_SECRET ?? '',
      fetchImpl: overrides.paymentsFetch,
    },
    // Real message delivery. Each channel switches on when its variables are set (see messenger.js).
    messaging: {
      sms: { provider: process.env.SMS_PROVIDER ?? '', authKey: process.env.MSG91_AUTH_KEY ?? '', otpTemplateId: process.env.MSG91_OTP_TEMPLATE_ID ?? '', flowTemplateId: process.env.MSG91_FLOW_TEMPLATE_ID ?? '' },
      whatsapp: {
        token: process.env.WHATSAPP_TOKEN ?? '', phoneNumberId: process.env.WHATSAPP_PHONE_NUMBER_ID ?? '', apiVersion: process.env.WHATSAPP_API_VERSION ?? 'v20.0',
        otpTemplate: process.env.WHATSAPP_OTP_TEMPLATE ?? '', textTemplate: process.env.WHATSAPP_TEXT_TEMPLATE ?? '', language: process.env.WHATSAPP_LANGUAGE ?? 'en',
      },
      email: { apiKey: process.env.RESEND_API_KEY ?? '', from: process.env.EMAIL_FROM ?? '' },
      fetchImpl: overrides.messagingFetch,
      transport: overrides.messagingTransport,
    },
    // The exercise pictures and animations (gymvisual.com) are licensed for openGym only. Set true only if you hold a licence.
    exerciseMediaLicensed: overrides.exerciseMediaLicensed ?? flag('EXERCISE_MEDIA_LICENSED', false),
    pricingFile: overrides.pricingFile ?? process.env.PRICING_FILE ?? '',
    // Who invoices gym owners (printed on Gymmie's own GST invoices).
    seller: {
      name: process.env.PLATFORM_LEGAL_NAME ?? 'Gymmie',
      gstin: process.env.PLATFORM_GSTIN ?? '',
      address: process.env.PLATFORM_ADDRESS ?? '',
    },
    billing: { graceDays: Number(overrides.graceDays ?? process.env.SUBSCRIPTION_GRACE_DAYS ?? 7) },
    publicBaseUrl: overrides.publicBaseUrl ?? process.env.PUBLIC_BASE_URL ?? '',
    // number of reverse proxies in front (1 = Caddy/nginx): the client address is then read from X-Forwarded-For
    trustProxy: Number(overrides.trustProxy ?? process.env.TRUST_PROXY ?? 0),
    // browsers are only let in from this origin (the mobile app needs no CORS). Development allows any.
    corsOrigin: overrides.corsOrigin ?? process.env.CORS_ORIGIN ?? (production ? '' : '*'),
    logRequests: overrides.logRequests ?? flag('LOG_REQUESTS', true),
    // Values served by GET /v5/apps/configs/settings (the app-config contract).
    appSettings: {
      maintenanceMode: flag('MAINTENANCE_MODE', false),
      minimumAppVersion: process.env.MINIMUM_APP_VERSION ?? '1.0.0',
      minimumSuggestedAppVersion: process.env.MINIMUM_SUGGESTED_APP_VERSION ?? '1.9.0',
      helpCenterUrl: process.env.HELP_CENTER_URL ?? '',
      companyWhatsappNumber: process.env.COMPANY_WHATSAPP_NUMBER ?? '',
      // who the "talk to the creator" screen offers; both empty means the app shows no contact at all (nothing is invented)
      supportEmail: process.env.SUPPORT_EMAIL ?? '',
      supportName: process.env.SUPPORT_NAME ?? '',
      signUpContactNumber: process.env.SIGN_UP_CONTACT_NUMBER ?? '',
      selfRegistrationPlatform: process.env.SELF_REGISTRATION_PLATFORM ?? '',
    },
  };
}
