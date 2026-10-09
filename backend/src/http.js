// Minimal router + JSON HTTP plumbing (no external dependencies).
import { createServer } from 'node:http';
import { ApiError, badRequest, tooMany } from './errors.js';

const MAX_BODY = 12 * 1024 * 1024; // photo uploads arrive as base64 JSON

export class Router {
  constructor() { this.routes = []; }

  add(method, path, opts, handler) {
    if (typeof opts === 'function') { handler = opts; opts = {}; }
    const keys = [];
    const re = new RegExp(
      '^' + path.replace(/\/:([A-Za-z0-9_]+)/g, (_, k) => { keys.push(k); return '/([^/]+)'; }) + '/?$',
    );
    this.routes.push({ method, re, keys, opts: { auth: 'gym', ...opts }, handler, path });
    return this;
  }

  get(p, o, h) { return this.add('GET', p, o, h); }
  post(p, o, h) { return this.add('POST', p, o, h); }
  put(p, o, h) { return this.add('PUT', p, o, h); }
  patch(p, o, h) { return this.add('PATCH', p, o, h); }
  delete(p, o, h) { return this.add('DELETE', p, o, h); }

  /** Most specific route wins: fewer :params first, then registration order. */
  match(method, pathname) {
    let pathMatched = false;
    let best = null;
    for (const r of this.routes) {
      const m = r.re.exec(pathname);
      if (!m) continue;
      pathMatched = true;
      if (r.method !== method) continue;
      if (!best || r.keys.length < best.route.keys.length) {
        const params = {};
        r.keys.forEach((k, i) => { params[k] = decodeURIComponent(m[i + 1]); });
        best = { route: r, params };
      }
    }
    return best ?? { route: null, pathMatched };
  }
}

export async function readJson(req) {
  const chunks = [];
  let size = 0;
  for await (const c of req) {
    size += c.length;
    if (size > MAX_BODY) throw new ApiError(413, 'PAYLOAD_TOO_LARGE', 'Request body too large');
    chunks.push(c);
  }
  if (size === 0) return {};
  const ct = req.headers['content-type'] ?? '';
  if (ct.includes('application/x-www-form-urlencoded')) {
    return Object.fromEntries(new URLSearchParams(Buffer.concat(chunks).toString('utf8')));
  }
  if (!ct.includes('application/json')) throw new ApiError(415, 'UNSUPPORTED_MEDIA_TYPE', 'Content-Type must be application/json');
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch {
    throw badRequest('Request body is not valid JSON');
  }
}

export class RateLimiter {
  constructor(scale = 1) { this.hits = new Map(); this.scale = scale; }
  check(key, max, windowSec) {
    max = Math.max(1, Math.round(max * this.scale));
    const now = Date.now();
    const cutoff = now - windowSec * 1000;
    const arr = (this.hits.get(key) ?? []).filter((t) => t > cutoff);
    if (arr.length >= max) {
      this.hits.set(key, arr);
      throw tooMany('Too many attempts. Please try again later.', Math.ceil((arr[0] + windowSec * 1000 - now) / 1000));
    }
    arr.push(now);
    this.hits.set(key, arr);
    if (this.hits.size > 5000) {
      for (const [k, v] of this.hits) if (!v.some((t) => t > cutoff)) this.hits.delete(k);
    }
  }
}

export function send(res, status, body, headers = {}) {
  const payload = body === undefined ? '' : JSON.stringify(body);
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
    ...headers,
  });
  res.end(payload);
}

export function paginate(items, query, { defaultLimit = 20, maxLimit = 200 } = {}) {
  const page = Math.max(1, parseInt(query.page ?? '1', 10) || 1);
  const limit = Math.min(maxLimit, Math.max(1, parseInt(query.limit ?? String(defaultLimit), 10) || defaultLimit));
  const total = items.length;
  const start = (page - 1) * limit;
  return {
    items: items.slice(start, start + limit),
    meta: { page, limit, total, totalPages: Math.max(1, Math.ceil(total / limit)) },
  };
}

/** Helper return types for handlers. */
export const list = (items, query, opts) => {
  const p = paginate(items, query, opts);
  return { __envelope: true, status: 200, body: { data: p.items, meta: p.meta } };
};
export const created = (data) => ({ __envelope: true, status: 201, body: { data } });
export const noContent = () => ({ __envelope: true, status: 204 });
export const raw = (status, contentType, body, headers = {}) => ({ __raw: true, status, contentType, body, headers });

export function createHttpServer(handle, config) {
  return createServer(async (req, res) => {
    const started = Date.now();
    const cors = {
      'access-control-allow-origin': config.corsOrigin,
      'access-control-allow-headers': 'authorization, content-type, x-gym-id, x-app-version, x-device-id',
      'access-control-allow-methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS',
      'access-control-max-age': '600',
      'x-content-type-options': 'nosniff',
    };
    try {
      if (req.method === 'OPTIONS') { res.writeHead(204, cors); return res.end(); }
      const url = new URL(req.url, 'http://localhost');
      const out = await handle(req, url);
      if (out?.__raw) {
        res.writeHead(out.status, { 'content-type': out.contentType, 'x-content-type-options': 'nosniff', ...cors, ...out.headers });
        res.end(out.body);
      } else if (out?.__envelope) {
        if (out.status === 204) { res.writeHead(204, cors); res.end(); }
        else send(res, out.status, out.body, cors);
      } else {
        send(res, 200, { data: out ?? null }, cors);
      }
    } catch (err) {
      if (err instanceof ApiError) {
        send(res, err.status, { error: { code: err.code, message: err.message, details: err.details } }, {
          ...cors,
          ...(err.status === 429 && err.details?.retryAfterSec ? { 'retry-after': String(err.details.retryAfterSec) } : {}),
        });
      } else {
        console.error('[unhandled]', err);
        send(res, 500, { error: { code: 'INTERNAL', message: 'Something went wrong' } }, cors);
      }
    } finally {
      if (config.logRequests) console.log(`${req.method} ${req.url} ${res.statusCode} ${Date.now() - started}ms`);
    }
  });
}
