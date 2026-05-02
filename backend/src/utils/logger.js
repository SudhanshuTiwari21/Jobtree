import winston from 'winston';

const { combine, timestamp, errors, json, colorize, printf } = winston.format;

// Custom format for console output
const consoleFormat = printf(({ level, message, timestamp, stack, ...meta }) => {
  // Handle object messages properly
  let output = typeof message === 'object' ? JSON.stringify(message, null, 2) : message;
  
  // Add stack trace if available
  if (stack) {
    output = stack;
  }
  
  // Add metadata if present
  const metaKeys = Object.keys(meta).filter(k => k !== 'service');
  if (metaKeys.length > 0) {
    const metaStr = JSON.stringify(
      metaKeys.reduce((acc, k) => ({ ...acc, [k]: meta[k] }), {}),
      null,
      2
    );
    output += `\n${metaStr}`;
  }
  
  return `${timestamp} [${level}]: ${output}`;
});

// Create logger instance
const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: combine(
    timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }),
    errors({ stack: true }),
    json()
  ),
  defaultMeta: { service: 'jobtree-backend' },
  transports: [
    // Write all logs to console
    new winston.transports.Console({
      format: combine(
        colorize(),
        timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }),
        consoleFormat
      ),
    }),
    // Write all logs with level 'error' and below to error.log
    new winston.transports.File({
      filename: 'logs/error.log',
      level: 'error',
    }),
    // Write all logs to combined.log
    new winston.transports.File({
      filename: 'logs/combined.log',
    }),
  ],
});

// If we're not in production, log to the console with simpler format
if (process.env.NODE_ENV !== 'production') {
  logger.add(
    new winston.transports.Console({
      format: combine(colorize(), consoleFormat),
    })
  );
}

export default logger;


