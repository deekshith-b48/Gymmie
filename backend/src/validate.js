// Small declarative request validator. Unknown keys are stripped (mass-assignment protection).
//
// Field spec: { type, required?, min?, max?, values?, items?, props?, nullable?, default?, pattern? }
// Types: string | number | integer | boolean | date | datetime | enum | phone | email | array | object | any
import { invalid } from './errors.js';

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

export function normalizePhone(raw, defaultDial = '+91') {
  if (typeof raw !== 'string') return null;
  let s = raw.trim().replace(/[\s\-()]/g, '');
  if (!s) return null;
  if (s.startsWith('00')) s = '+' + s.slice(2);
  if (!s.startsWith('+')) s = defaultDial + s.replace(/^0+/, '');
  if (!/^\+\d{8,15}$/.test(s)) return null;
  if (s.startsWith('+91') && !/^\+91[6-9]\d{9}$/.test(s)) return null;
  return s;
}

export function isValidDate(s) {
  if (typeof s !== 'string' || !DATE_RE.test(s)) return false;
  const d = new Date(`${s}T00:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === s;
}

function check(name, spec, value, errors, partial) {
  if (value === undefined || value === null) {
    if (value === null && spec.nullable) return null;
    if (value === undefined && spec.default !== undefined && !partial) {
      return typeof spec.default === 'function' ? spec.default() : spec.default;
    }
    if (spec.required && !partial) errors[name] = 'is required';
    else if (value === null && !spec.nullable) errors[name] = 'must not be null';
    return undefined;
  }
  switch (spec.type) {
    case 'string': {
      if (typeof value !== 'string') return void (errors[name] = 'must be a string');
      const s = value.trim();
      if (spec.required && s.length === 0 && !spec.allowEmpty) return void (errors[name] = 'must not be empty');
      if (spec.min !== undefined && s.length < spec.min) return void (errors[name] = `must be at least ${spec.min} characters`);
      if (spec.max !== undefined && s.length > spec.max) return void (errors[name] = `must be at most ${spec.max} characters`);
      if (spec.pattern && s && !spec.pattern.test(s)) return void (errors[name] = spec.patternMessage ?? 'has an invalid format');
      return s;
    }
    case 'number':
    case 'integer': {
      const n = typeof value === 'string' && value.trim() !== '' ? Number(value) : value;
      if (typeof n !== 'number' || !Number.isFinite(n)) return void (errors[name] = 'must be a number');
      if (spec.type === 'integer' && !Number.isInteger(n)) return void (errors[name] = 'must be a whole number');
      if (spec.min !== undefined && n < spec.min) return void (errors[name] = `must be at least ${spec.min}`);
      if (spec.max !== undefined && n > spec.max) return void (errors[name] = `must be at most ${spec.max}`);
      return n;
    }
    case 'boolean':
      if (typeof value !== 'boolean') return void (errors[name] = 'must be true or false');
      return value;
    case 'date':
      if (!isValidDate(value)) return void (errors[name] = 'must be a date in YYYY-MM-DD format');
      return value;
    case 'datetime': {
      if (typeof value !== 'string' || Number.isNaN(Date.parse(value))) return void (errors[name] = 'must be an ISO-8601 date-time');
      return new Date(value).toISOString();
    }
    case 'enum':
      if (!spec.values.includes(value)) return void (errors[name] = `must be one of: ${spec.values.join(', ')}`);
      return value;
    case 'phone': {
      const p = normalizePhone(value, spec.dial);
      if (!p) return void (errors[name] = 'is not a valid phone number');
      return p;
    }
    case 'email': {
      if (typeof value !== 'string') return void (errors[name] = 'must be a string');
      const e = value.trim().toLowerCase();
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(e) || e.length > 254) return void (errors[name] = 'is not a valid email address');
      return e;
    }
    case 'array': {
      if (!Array.isArray(value)) return void (errors[name] = 'must be a list');
      if (spec.max !== undefined && value.length > spec.max) return void (errors[name] = `must have at most ${spec.max} items`);
      if (spec.min !== undefined && value.length < spec.min) return void (errors[name] = `must have at least ${spec.min} items`);
      const out = [];
      value.forEach((item, i) => {
        const sub = {};
        const r = check(`${name}[${i}]`, spec.items, item, sub, false);
        Object.assign(errors, sub);
        out.push(r);
      });
      return out;
    }
    case 'object': {
      if (typeof value !== 'object' || Array.isArray(value)) return void (errors[name] = 'must be an object');
      if (!spec.props) return value;
      const sub = {};
      const out = validateInto(spec.props, value, sub, false);
      for (const [k, m] of Object.entries(sub)) errors[`${name}.${k}`] = m;
      return out;
    }
    case 'any':
      return value;
    default:
      throw new Error(`unknown spec type ${spec.type}`);
  }
}

function validateInto(schema, input, errors, partial) {
  const out = {};
  for (const [name, spec] of Object.entries(schema)) {
    const r = check(name, spec, input[name], errors, partial);
    if (r !== undefined) out[name] = r;
  }
  return out;
}

export function validate(schema, input, { partial = false } = {}) {
  if (input === null || typeof input !== 'object' || Array.isArray(input)) {
    throw invalid('Request body must be a JSON object');
  }
  const errors = {};
  const out = validateInto(schema, input, errors, partial);
  if (Object.keys(errors).length) {
    const first = Object.entries(errors)[0];
    throw invalid(`${first[0]} ${first[1]}`, errors);
  }
  return out;
}

export const S = {
  str: (o = {}) => ({ type: 'string', ...o }),
  num: (o = {}) => ({ type: 'number', ...o }),
  int: (o = {}) => ({ type: 'integer', ...o }),
  bool: (o = {}) => ({ type: 'boolean', ...o }),
  date: (o = {}) => ({ type: 'date', ...o }),
  dt: (o = {}) => ({ type: 'datetime', ...o }),
  oneOf: (values, o = {}) => ({ type: 'enum', values, ...o }),
  phone: (o = {}) => ({ type: 'phone', ...o }),
  email: (o = {}) => ({ type: 'email', ...o }),
  list: (items, o = {}) => ({ type: 'array', items, ...o }),
  obj: (props, o = {}) => ({ type: 'object', props, ...o }),
  any: (o = {}) => ({ type: 'any', ...o }),
};
