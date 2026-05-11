import logger from '../utils/logger.js';

/**
 * Custom error class for API errors
 */
export class ApiError extends Error {
  constructor(statusCode, message, isOperational = true, stack = '') {
    super(message);
    this.statusCode = statusCode;
    this.isOperational = isOperational;
    if (stack) {
      this.stack = stack;
    } else {
      Error.captureStackTrace(this, this.constructor);
    }
  }
}

/**
 * Error handling middleware
 */
export const errorHandler = (err, req, res, next) => {
  let statusCode = err.statusCode || 500;
  let message = err.message || 'Internal server error';

  /** AWS SDK / S3: IAM user lacks PutObject etc. — safe to surface (no secrets). */
  const isS3AccessDenied =
    err.name === 'AccessDenied' ||
    err.Code === 'AccessDenied' ||
    (typeof err.message === 'string' &&
      err.message.includes('not authorized to perform: s3:'));

  if (isS3AccessDenied) {
    statusCode = 503;
    message =
      'Media storage rejected the upload: attach an IAM policy allowing s3:PutObject (and s3:GetObject, s3:DeleteObject if you delete media) on arn:aws:s3:::jobtree-media/* for the API AWS user.';
  }

  // Log error
  logger.error({
    error: err.message,
    stack: err.stack,
    url: req.originalUrl,
    method: req.method,
    ip: req.ip,
  });

  // In production, don't leak error details (except operational / known cases)
  const treatAsOperational =
    err.isOperational || isS3AccessDenied || (err.statusCode && err.statusCode < 500);
  if (process.env.NODE_ENV === 'production' && !treatAsOperational) {
    message = 'Internal server error';
  }

  res.status(statusCode).json({
    success: false,
    error: {
      message,
      ...(process.env.NODE_ENV === 'development' && { stack: err.stack }),
    },
  });
};

/**
 * 404 Not Found handler
 */
export const notFoundHandler = (req, res, next) => {
  const error = new ApiError(404, `Route ${req.originalUrl} not found`);
  next(error);
};

/**
 * Async handler wrapper to catch errors in async route handlers
 */
export const asyncHandler = (fn) => {
  return (req, res, next) => {
    Promise.resolve(fn(req, res, next)).catch(next);
  };
};


