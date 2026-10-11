export class ApiError extends Error {
  constructor(status, code, message, details) {
    super(message);
    this.status = status;
    this.code = code;
    this.details = details;
  }
}
export const badRequest = (message, details) => new ApiError(400, 'BAD_REQUEST', message, details);
export const unauthorized = (message = 'Authentication required') => new ApiError(401, 'UNAUTHORIZED', message);
export const paymentRequired = (code, message, details) => new ApiError(402, code, message, details);
export const forbidden = (message = 'Access denied') => new ApiError(403, 'FORBIDDEN', message);
export const notFound = (message = 'Not found') => new ApiError(404, 'NOT_FOUND', message);
export const conflict = (message, details) => new ApiError(409, 'CONFLICT', message, details);
export const invalid = (message, details) => new ApiError(422, 'VALIDATION_FAILED', message, details);
export const tooMany = (message = 'Too many requests', retryAfterSec) =>
  new ApiError(429, 'RATE_LIMITED', message, retryAfterSec ? { retryAfterSec } : undefined);
