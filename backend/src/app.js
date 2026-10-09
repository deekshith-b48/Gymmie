// Application composition: request context (auth → gym tenancy → role permission) + route registration.
import { Router, RateLimiter, readJson, raw } from './http.js';
import { AuthService, can } from './auth.js';
import { ApiError, badRequest, forbidden, notFound, unauthorized } from './errors.js';
import { loadGym } from './helpers.js';
import { todayIn } from './domain/dates.js';

import { registerConfigRoutes } from './routes/config.js';
import { registerAuthRoutes } from './routes/auth.js';
import { registerGymRoutes } from './routes/gyms.js';
import { registerMemberRoutes } from './routes/members.js';
import { registerPlanRoutes } from './routes/plans.js';
import { registerMembershipRoutes } from './routes/memberships.js';
import { registerFinanceRoutes } from './routes/finance.js';
import { registerLeadRoutes } from './routes/leads.js';
import { registerAttendanceRoutes } from './routes/attendance.js';
import { registerStaffRoutes } from './routes/staff.js';
import { registerProductRoutes } from './routes/products.js';
import { registerMessagingRoutes } from './routes/messaging.js';
import { registerFitnessRoutes } from './routes/fitness.js';
import { registerParqRoutes } from './routes/parq.js';
import { registerDeviceRoutes } from './routes/devices.js';
import { registerMiscRoutes } from './routes/misc.js';
import { registerDashboardRoutes } from './routes/dashboards.js';

export function createApp({ store, config }) {
  const router = new Router();
  const auth = new AuthService(store, config);
  const limiter = new RateLimiter(config.rateLimitScale);
  const deps = { store, config, auth, limiter, router };

  registerConfigRoutes(deps);
  registerAuthRoutes(deps);
  registerGymRoutes(deps);
  registerMemberRoutes(deps);
  registerPlanRoutes(deps);
  registerMembershipRoutes(deps);
  registerFinanceRoutes(deps);
  registerLeadRoutes(deps);
  registerAttendanceRoutes(deps);
  registerStaffRoutes(deps);
  registerProductRoutes(deps);
  registerMessagingRoutes(deps);
  registerFitnessRoutes(deps);
  registerParqRoutes(deps);
  registerDeviceRoutes(deps);
  registerMiscRoutes(deps);
  registerDashboardRoutes(deps);

  async function handle(req, url) {
    const { route, params, pathMatched } = router.match(req.method, url.pathname);
    if (!route) {
      if (pathMatched) throw new ApiError(405, 'METHOD_NOT_ALLOWED', 'Method not allowed');
      throw notFound('Route not found');
    }
    const opts = route.opts;
    const ctx = {
      req, url, params, store, config, auth, limiter,
      query: Object.fromEntries(url.searchParams),
      ip: req.socket.remoteAddress ?? 'unknown',
      body: {},
    };
    if (['POST', 'PUT', 'PATCH', 'DELETE'].includes(req.method)) ctx.body = await readJson(req);

    if (opts.auth !== 'none') {
      const header = req.headers.authorization ?? '';
      if (!header.startsWith('Bearer ')) throw unauthorized();
      const payload = auth.verifyAccess(header.slice(7));
      if (!auth.sessionActive(payload.sid)) throw unauthorized('Session ended. Please sign in again.');
      const user = store.get('SELECT * FROM users WHERE id = ?', payload.sub);
      if (!user) throw unauthorized();
      if (user.disabled) throw forbidden('Your account is disabled.');
      ctx.user = user;
      ctx.sessionId = payload.sid;
    }

    if (opts.auth === 'gym') {
      let gymId = req.headers['x-gym-id'];
      if (!gymId) {
        const rows = store.all("SELECT gym_id FROM gym_users WHERE user_id = ? AND status = 'active'", ctx.user.id);
        if (rows.length === 1) gymId = rows[0].gym_id;
        else throw badRequest('Select a gym: the x-gym-id header is required');
      }
      const link = store.get("SELECT * FROM gym_users WHERE gym_id = ? AND user_id = ? AND status = 'active'", gymId, ctx.user.id);
      if (!link) throw forbidden('You do not have access to this gym');
      ctx.gymId = gymId;
      ctx.role = link.role;
      ctx.gymProfile = JSON.parse(link.profile);
      ctx.gym = loadGym(store, gymId);
      ctx.today = () => todayIn(ctx.gym.timezone);
      ctx.col = (name) => store.col(gymId, name);
      if (opts.perm) {
        const perms = Array.isArray(opts.perm) ? opts.perm : [opts.perm];
        if (!perms.some((p) => can(ctx.role, p))) throw forbidden('You do not have sufficient permissions to access this');
      }
    }
    const out = await route.handler(ctx);
    return out === undefined ? { __envelope: true, status: 204 } : out;
  }
  return { handle, router, auth, store, config, raw };
}
