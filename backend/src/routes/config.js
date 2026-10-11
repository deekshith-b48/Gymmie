// Public app configuration + feature-announcement + master data.
import { FEATURE_CATALOG } from '../helpers.js';

export const COUNTRIES = [
  { code: 'IN', name: 'India', dialCode: '+91', currencyCode: 'INR', currencySymbol: '₹', timezone: 'Asia/Kolkata' },
  { code: 'AE', name: 'United Arab Emirates', dialCode: '+971', currencyCode: 'AED', currencySymbol: 'AED', timezone: 'Asia/Dubai' },
  { code: 'US', name: 'United States', dialCode: '+1', currencyCode: 'USD', currencySymbol: '$', timezone: 'America/New_York' },
  { code: 'GB', name: 'United Kingdom', dialCode: '+44', currencyCode: 'GBP', currencySymbol: '£', timezone: 'Europe/London' },
  { code: 'SG', name: 'Singapore', dialCode: '+65', currencyCode: 'SGD', currencySymbol: 'S$', timezone: 'Asia/Singapore' },
  { code: 'AU', name: 'Australia', dialCode: '+61', currencyCode: 'AUD', currencySymbol: 'A$', timezone: 'Australia/Sydney' },
  { code: 'NP', name: 'Nepal', dialCode: '+977', currencyCode: 'NPR', currencySymbol: 'Rs', timezone: 'Asia/Kathmandu' },
  { code: 'LK', name: 'Sri Lanka', dialCode: '+94', currencyCode: 'LKR', currencySymbol: 'Rs', timezone: 'Asia/Colombo' },
  { code: 'BD', name: 'Bangladesh', dialCode: '+880', currencyCode: 'BDT', currencySymbol: '৳', timezone: 'Asia/Dhaka' },
];

export function registerConfigRoutes({ router, config, store }) {
  router.get('/healthcheck', { auth: 'none' }, () => ({ status: 'ok', time: new Date().toISOString() }));
  router.get('/health', { auth: 'none' }, () => ({ status: 'ok' }));
  // Readiness for the load balancer / uptime monitor: answers only if the database does.
  router.get('/ready', { auth: 'none' }, () => {
    store.get('SELECT 1 AS ok');
    return { status: 'ready', uptimeSec: Math.round(process.uptime()) };
  });

  // Reconstructed app-config contract. Keys mirror the remote-config constants found in the app binary
  // (MAINTENANCE_MODE, MINIMUM_APP_VERSION, MINIMUM_SUGGESTED_APP_VERSION, HELP_CENTER_URL, ...).
  router.get('/v5/apps/configs/settings', { auth: 'none' }, () => ({
    ...config.appSettings,
    featureCatalog: FEATURE_CATALOG,
    backend: { name: 'gymmie-backend', environment: config.env, devOtpEnabled: config.devExposeOtp },
  }));

  router.get('/v5/masters/country/phone-code', { auth: 'none' }, () => COUNTRIES);
}
