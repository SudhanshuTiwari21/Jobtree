import dotenv from 'dotenv';

dotenv.config();

const config = {
  // Server Configuration
  env: process.env.NODE_ENV || 'development',
  port: parseInt(process.env.PORT, 10) || 3000,

  // Database Configuration (Neon PostgreSQL)
  database: {
    // Neon pooled connection string (recommended)
    url: process.env.DATABASE_URL,
    // Individual params (fallback)
    host: process.env.DB_HOST || 'localhost',
    port: parseInt(process.env.DB_PORT, 10) || 5432,
    name: process.env.DB_NAME || 'jobtree',
    user: process.env.DB_USER || 'postgres',
    password: process.env.DB_PASSWORD || 'postgres',
    // SSL is always required for Neon
    ssl: process.env.DB_SSL !== 'false',
    // Pool settings (keep low for Neon - it handles pooling)
    poolMin: parseInt(process.env.DB_POOL_MIN, 10) || 1,
    poolMax: parseInt(process.env.DB_POOL_MAX, 10) || 5,
  },

  // OTP Configuration
  otp: {
    length: parseInt(process.env.OTP_LENGTH, 10) || 6,
    expiryMinutes: parseInt(process.env.OTP_EXPIRY_MINUTES, 10) || 5,
    maxAttempts: parseInt(process.env.OTP_MAX_ATTEMPTS, 10) || 5,
    resendCooldownSeconds: parseInt(process.env.OTP_RESEND_COOLDOWN_SECONDS, 10) || 30,
    maxResendAttempts: parseInt(process.env.OTP_MAX_RESEND_ATTEMPTS, 10) || 3,
  },

  // JWT Configuration
  jwt: {
    secret: process.env.JWT_SECRET || 'your-super-secret-jwt-key-change-in-production',
    expiresIn: process.env.JWT_EXPIRES_IN || '7d',
    refreshExpiresIn: process.env.JWT_REFRESH_EXPIRES_IN || '30d',
  },

  // AWS S3 Configuration
  aws: {
    region: process.env.AWS_REGION || 'ap-south-1',
    accessKeyId: process.env.AWS_ACCESS_KEY_ID,
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
    s3Bucket: process.env.AWS_S3_BUCKET || 'jobtree-media',
    presignedUrlExpiry: parseInt(process.env.AWS_PRESIGNED_URL_EXPIRY, 10) || 3600, // 1 hour
  },

  // Twilio: SMS (OTP) + voice (call masking). Same account; optional separate SMS sender.
  twilio: {
    accountSid: process.env.TWILIO_ACCOUNT_SID,
    authToken: process.env.TWILIO_AUTH_TOKEN,
    /** Voice caller ID / proxy for masked calls */
    phoneNumber: process.env.TWILIO_PHONE_NUMBER,
    /** SMS sender for OTP; defaults to TWILIO_PHONE_NUMBER */
    smsFrom: process.env.TWILIO_SMS_FROM || process.env.TWILIO_PHONE_NUMBER,
    webhookBaseUrl: process.env.TWILIO_WEBHOOK_BASE_URL || process.env.BASE_URL || 'http://localhost:3000',
    maxCallsPerCandidatePerDay: parseInt(process.env.MAX_CALLS_PER_CANDIDATE_PER_DAY, 10) || 3,
  },

  // Firebase Cloud Messaging (FCM) for push notifications
  firebase: {
    // Path to service account JSON or base64-encoded JSON (do not hardcode credentials)
    serviceAccountPath: process.env.GOOGLE_APPLICATION_CREDENTIALS,
    serviceAccountJson: process.env.FIREBASE_SERVICE_ACCOUNT_JSON, // base64 or raw JSON string
  },

  // Security
  security: {
    bcryptSaltRounds: parseInt(process.env.BCRYPT_SALT_ROUNDS, 10) || 10,
    rateLimitWindowMs: parseInt(process.env.API_RATE_LIMIT_WINDOW_MS, 10) || 900000, // 15 minutes
    rateLimitMaxRequests: parseInt(process.env.API_RATE_LIMIT_MAX_REQUESTS, 10) || 100,
  },

  // CORS
  cors: {
    allowedOrigins: process.env.ALLOWED_ORIGINS?.split(',') || [
      'http://localhost:3000',
      'http://localhost:8080',
    ],
  },

  /** Optional: `PATCH /api/admin/salons/:id/verification` header `X-Admin-Secret` */
  admin: {
    webhookSecret: process.env.ADMIN_WEBHOOK_SECRET || '',
  },
};

// Validate required environment variables in production
if (config.env === 'production') {
  const requiredEnvVars = [
    'JWT_SECRET',
  ];

  // Database: require either DATABASE_URL or individual params
  if (!config.database.url) {
    requiredEnvVars.push('DB_HOST', 'DB_NAME', 'DB_USER', 'DB_PASSWORD');
  }

  const missingVars = requiredEnvVars.filter(
    (varName) => !process.env[varName]
  );

  if (missingVars.length > 0) {
    throw new Error(
      `Missing required environment variables: ${missingVars.join(', ')}`
    );
  }

  const twilioSmsReady =
    config.twilio.accountSid &&
    config.twilio.authToken &&
    (config.twilio.smsFrom || config.twilio.phoneNumber);
  if (!twilioSmsReady) {
    console.warn(
      '⚠️  WARNING: Twilio SMS not configured in production. Set TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, and TWILIO_PHONE_NUMBER (or TWILIO_SMS_FROM for OTP only).'
    );
  }

  // Warn if JWT secret is weak
  if (config.jwt.secret.length < 32) {
    console.warn('⚠️  WARNING: JWT_SECRET should be at least 32 characters for security.');
  }
}

export default config;
