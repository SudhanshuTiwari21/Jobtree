import bcrypt from 'bcrypt';
import config from '../config/index.js';
import db from '../database/connection.js';
import logger from '../utils/logger.js';
import otpSender from './otpSenderService.js';

class OTPService {
  constructor() {
    logger.info('OTP Service initialized');
  }

  /**
   * Generate a random OTP
   * @param {number} length - Length of OTP
   * @returns {string} Generated OTP
   */
  generateOTP(length = config.otp.length) {
    const digits = '0123456789';
    let otp = '';
    for (let i = 0; i < length; i++) {
      otp += digits[Math.floor(Math.random() * digits.length)];
    }
    return otp;
  }

  /**
   * Hash OTP for secure storage
   * @param {string} otp - Plain OTP
   * @returns {Promise<string>} Hashed OTP
   */
  async hashOTP(otp) {
    return bcrypt.hash(otp, config.security.bcryptSaltRounds);
  }

  /**
   * Verify OTP against hash
   * @param {string} otp - Plain OTP
   * @param {string} hash - Stored hash
   * @returns {Promise<boolean>} Verification result
   */
  async verifyOTPHash(otp, hash) {
    return bcrypt.compare(otp, hash);
  }

  /**
   * Clean up expired OTPs
   */
  async cleanupExpiredOTPs() {
    try {
      await db.query(
        'DELETE FROM otp_requests WHERE expires_at < NOW()',
        []
      );
    } catch (error) {
      logger.error('Error cleaning up expired OTPs:', error);
    }
  }

  /**
   * Get active OTP record for a phone number
   * @param {string} phoneNumber - Phone number
   * @returns {Promise<object|null>} OTP record
   */
  async getActiveOTPRecord(phoneNumber) {
    const result = await db.query(
      `SELECT * FROM otp_requests 
       WHERE phone_number = $1 
       AND expires_at > NOW() 
       AND is_verified = false
       ORDER BY created_at DESC 
       LIMIT 1`,
      [phoneNumber]
    );
    return result.rows[0] || null;
  }

  /**
   * Send OTP request - generates, stores, and sends OTP
   * @param {string} phoneNumber - Phone number (10 digits)
   * @param {string} countryCode - Country code (default: +91)
   * @returns {Promise<object>} Request result
   */
  async sendOTP(phoneNumber, countryCode = '+91', smsAppHash = null) {
    // Sanitize phone number
    const sanitizedPhone = phoneNumber.replace(/\D/g, '').replace(/^0+/, '');
    const sanitizedCountryCode = countryCode.replace('+', '');
    
    // Check for existing active OTP
    const existingOTP = await this.getActiveOTPRecord(sanitizedPhone);
    
    if (existingOTP) {
      // Check resend cooldown
      const lastResend = existingOTP.last_resend_at 
        ? new Date(existingOTP.last_resend_at) 
        : new Date(existingOTP.created_at);
      
      const cooldownMs = config.otp.resendCooldownSeconds * 1000;
      const timeSinceLastResend = Date.now() - lastResend.getTime();
      
      if (timeSinceLastResend < cooldownMs) {
        const waitSeconds = Math.ceil((cooldownMs - timeSinceLastResend) / 1000);
        return {
          success: false,
          message: `Please wait ${waitSeconds} seconds before requesting a new OTP.`,
          waitSeconds,
        };
      }

      // Check max resend attempts
      if (existingOTP.resend_count >= config.otp.maxResendAttempts) {
        return {
          success: false,
          message: 'Maximum OTP requests exceeded. Please try again after some time.',
        };
      }
    }

    // Generate new OTP
    const otp = this.generateOTP();
    const otpHash = await this.hashOTP(otp);
    const expiresAt = new Date(Date.now() + config.otp.expiryMinutes * 60 * 1000);

    // Store OTP in database BEFORE sending
    // This ensures we don't send OTP if database fails
    if (existingOTP) {
      // Update existing record
      await db.query(
        `UPDATE otp_requests 
         SET otp_hash = $1, 
             expires_at = $2, 
             resend_count = resend_count + 1,
             last_resend_at = NOW(),
             attempts = 0
         WHERE id = $3`,
        [otpHash, expiresAt, existingOTP.id]
      );
    } else {
      // Create new record
      await db.query(
        `INSERT INTO otp_requests (phone_number, otp_hash, expires_at, resend_count)
         VALUES ($1, $2, $3, 0)`,
        [sanitizedPhone, otpHash, expiresAt]
      );
    }

    // Send OTP via SMS provider (Twilio in production, console in dev)
    await otpSender.sendOtp(sanitizedPhone, otp, sanitizedCountryCode, smsAppHash);

    // Clean up old expired OTPs periodically (async, non-blocking)
    this.cleanupExpiredOTPs().catch(() => {});

    return {
      success: true,
      message: 'OTP sent successfully',
      expiresIn: config.otp.expiryMinutes * 60, // seconds
    };
  }

  /**
   * Resend OTP
   * @param {string} phoneNumber - Phone number
   * @param {string} countryCode - Country code
   * @returns {Promise<object>} Request result
   */
  async resendOTP(phoneNumber, countryCode = '+91', smsAppHash = null) {
    return this.sendOTP(phoneNumber, countryCode, smsAppHash);
  }

  /**
   * Verify OTP
   * @param {string} phoneNumber - Phone number
   * @param {string} inputOTP - OTP entered by user
   * @returns {Promise<object>} Verification result
   */
  async verifyOTP(phoneNumber, inputOTP) {
    // Sanitize phone number
    const sanitizedPhone = phoneNumber.replace(/\D/g, '').replace(/^0+/, '');
    
    // Get active OTP record
    const otpRecord = await this.getActiveOTPRecord(sanitizedPhone);

    if (!otpRecord) {
      return {
        success: false,
        message: 'OTP not found or expired. Please request a new OTP.',
      };
    }

    // Check max attempts
    if (otpRecord.attempts >= config.otp.maxAttempts) {
      await db.query('DELETE FROM otp_requests WHERE id = $1', [otpRecord.id]);
      return {
        success: false,
        message: 'Maximum verification attempts exceeded. Please request a new OTP.',
      };
    }

    // Increment attempts
    await db.query(
      'UPDATE otp_requests SET attempts = attempts + 1 WHERE id = $1',
      [otpRecord.id]
    );

    // Verify OTP
    const isValid = await this.verifyOTPHash(inputOTP, otpRecord.otp_hash);

    if (!isValid) {
      const attemptsRemaining = config.otp.maxAttempts - (otpRecord.attempts + 1);
      return {
        success: false,
        message: 'Invalid OTP. Please try again.',
        attemptsRemaining,
      };
    }

    // Mark OTP as verified and clean up
    await db.query(
      'UPDATE otp_requests SET is_verified = true WHERE id = $1',
      [otpRecord.id]
    );

    return {
      success: true,
      message: 'OTP verified successfully.',
    };
  }

  /**
   * Get OTP status (for debugging/testing)
   * @param {string} phoneNumber - Phone number
   * @returns {Promise<object|null>} OTP info
   */
  async getOTPStatus(phoneNumber) {
    if (config.env === 'production') {
      return null;
    }

    const sanitizedPhone = phoneNumber.replace(/\D/g, '').replace(/^0+/, '');
    const otpRecord = await this.getActiveOTPRecord(sanitizedPhone);
    if (!otpRecord) return null;

    return {
      phoneNumber: sanitizedPhone,
      expiresAt: otpRecord.expires_at,
      attempts: otpRecord.attempts,
      maxAttempts: config.otp.maxAttempts,
      resendCount: otpRecord.resend_count,
      maxResendAttempts: config.otp.maxResendAttempts,
      createdAt: otpRecord.created_at,
      provider: otpSender.getProvider(),
    };
  }
}

export default new OTPService();
