import jwt from 'jsonwebtoken';
import bcrypt from 'bcrypt';
import config from '../config/index.js';
import db from '../database/connection.js';
import salonService from './salonService.js';
import seekerService from './seekerService.js';
import logger from '../utils/logger.js';

class AuthService {
  /**
   * Generate JWT access token
   * @param {object} salon - Salon data
   * @returns {string} JWT token
   */
  generateAccessToken(salon) {
    const payload = {
      salonId: salon.id,
      phoneNumber: salon.phone_number,
      role: 'salon',
      type: 'access',
    };

    return jwt.sign(payload, config.jwt.secret, {
      expiresIn: config.jwt.expiresIn,
    });
  }

  /**
   * Generate JWT access token for a seeker
   */
  generateSeekerAccessToken(seeker) {
    const payload = {
      seekerId: seeker.id,
      phoneNumber: seeker.phone_number,
      role: 'seeker',
      type: 'access',
    };

    return jwt.sign(payload, config.jwt.secret, {
      expiresIn: config.jwt.expiresIn,
    });
  }

  /**
   * Generate refresh token for a seeker
   */
  async generateSeekerRefreshToken(seeker) {
    const payload = {
      seekerId: seeker.id,
      role: 'seeker',
      type: 'refresh',
    };

    const token = jwt.sign(payload, config.jwt.secret, {
      expiresIn: config.jwt.refreshExpiresIn,
    });

    const tokenHash = await bcrypt.hash(token, config.security.bcryptSaltRounds);
    const expiresAt = new Date(Date.now() + this.parseExpiresIn(config.jwt.refreshExpiresIn));

    await db.query(
      `INSERT INTO seeker_refresh_tokens (seeker_id, token_hash, expires_at)
       VALUES ($1, $2, $3)`,
      [seeker.id, tokenHash, expiresAt]
    );

    return token;
  }

  /**
   * Generate JWT refresh token
   * @param {object} salon - Salon data
   * @returns {Promise<string>} Refresh token
   */
  async generateRefreshToken(salon) {
    const payload = {
      salonId: salon.id,
      type: 'refresh',
    };

    const token = jwt.sign(payload, config.jwt.secret, {
      expiresIn: config.jwt.refreshExpiresIn,
    });

    // Hash and store refresh token
    const tokenHash = await bcrypt.hash(token, config.security.bcryptSaltRounds);
    const expiresAt = new Date(Date.now() + this.parseExpiresIn(config.jwt.refreshExpiresIn));

    await db.query(
      `INSERT INTO refresh_tokens (salon_id, token_hash, expires_at)
       VALUES ($1, $2, $3)`,
      [salon.id, tokenHash, expiresAt]
    );

    return token;
  }

  /**
   * Parse JWT expiresIn string to milliseconds
   * @param {string} expiresIn - e.g., '7d', '24h', '60m'
   * @returns {number} Milliseconds
   */
  parseExpiresIn(expiresIn) {
    const match = expiresIn.match(/^(\d+)([dhms])$/);
    if (!match) return 7 * 24 * 60 * 60 * 1000; // Default 7 days

    const value = parseInt(match[1]);
    const unit = match[2];

    const multipliers = {
      s: 1000,
      m: 60 * 1000,
      h: 60 * 60 * 1000,
      d: 24 * 60 * 60 * 1000,
    };

    return value * (multipliers[unit] || multipliers.d);
  }

  /**
   * Verify JWT token
   * @param {string} token - JWT token
   * @returns {object|null} Decoded payload or null
   */
  verifyToken(token) {
    try {
      return jwt.verify(token, config.jwt.secret);
    } catch (error) {
      logger.warn('Token verification failed:', error.message);
      return null;
    }
  }

  /**
   * Login or signup with verified phone number
   * @param {string} phoneNumber - Verified phone number (unique per salon profile)
   * @param {string} countryCode - Country code
   * @returns {Promise<object>} Auth result with tokens
   * 
   * Note: Salon profile is unique per phone number.
   * - If salon exists (isNewUser = false): User has an existing profile
   * - If salon is new (isNewUser = true): User needs to create profile
   */
  async loginOrSignup(phoneNumber, countryCode = '+91') {
    // Find or create salon (salon profile is unique per phone number)
    const { salon, isNew } = await salonService.findOrCreate(phoneNumber, countryCode);

    // Generate tokens
    const accessToken = this.generateAccessToken(salon);
    const refreshToken = await this.generateRefreshToken(salon);

    logger.info(`User ${isNew ? 'signed up' : 'logged in'}: ${phoneNumber} (isNew: ${isNew})`);

    return {
      success: true,
      isNewUser: isNew, // false = existing profile, true = new profile
      accessToken,
      refreshToken,
      expiresIn: config.jwt.expiresIn,
      salon: salonService.formatSalonResponse(salon),
    };
  }

  /**
   * Unified login — checks both salon and seeker profiles.
   * Returns ownerExists + seekerExists so the client can route immediately.
   */
  async unifiedLogin(phoneNumber, countryCode = '+91') {
    // Check owner (salon) profile
    const existingSalon = await salonService.findByPhoneNumber(phoneNumber);
    const ownerExists = !!existingSalon && !!(existingSalon.salon_name || existingSalon.city);

    // Check seeker profile
    const existingSeeker = await seekerService.findByPhone(phoneNumber);
    const seekerExists = !!existingSeeker && seekerService.hasBasicProfile(existingSeeker);

    // Create salon record if none (to store the phone number)
    const { salon, isNew } = await salonService.findOrCreate(phoneNumber, countryCode);

    // Also ensure a seeker record exists (phone-only stub)
    await seekerService.findOrCreate(phoneNumber, countryCode);

    // Generate a salon token by default (owner-perspective)
    const accessToken = this.generateAccessToken(salon);
    const refreshToken = await this.generateRefreshToken(salon);

    logger.info(`Unified login: ${phoneNumber} ownerExists=${ownerExists} seekerExists=${seekerExists} isNew=${isNew}`);

    return {
      success: true,
      isNewUser: isNew && !seekerExists,
      ownerExists,
      seekerExists,
      accessToken,
      refreshToken,
      expiresIn: config.jwt.expiresIn,
      salon: salonService.formatSalonResponse(salon),
    };
  }

  /**
   * Login or signup for a job seeker
   */
  async seekerLoginOrSignup(phoneNumber, countryCode = '+91') {
    const { seeker, isNew } = await seekerService.findOrCreate(phoneNumber, countryCode);

    const accessToken = this.generateSeekerAccessToken(seeker);
    const refreshToken = await this.generateSeekerRefreshToken(seeker);

    const seekerProfileExists = seekerService.hasBasicProfile(seeker);

    logger.info(`Seeker ${isNew ? 'signed up' : 'logged in'}: ${phoneNumber} (profileExists: ${seekerProfileExists})`);

    return {
      success: true,
      isNewUser: isNew,
      seekerProfileExists,
      accessToken,
      refreshToken,
      expiresIn: config.jwt.expiresIn,
      seeker: seekerService.formatSeekerResponse(seeker),
    };
  }

  /**
   * Refresh access token
   * @param {string} refreshToken - Refresh token
   * @returns {Promise<object>} New access token
   */
  async refreshAccessToken(refreshToken) {
    // Verify refresh token
    const decoded = this.verifyToken(refreshToken);
    if (!decoded || decoded.type !== 'refresh') {
      throw new Error('Invalid refresh token');
    }

    // Handle seeker refresh tokens
    if (decoded.role === 'seeker') {
      const result = await db.query(
        `SELECT * FROM seeker_refresh_tokens
         WHERE seeker_id = $1 AND is_revoked = false AND expires_at > NOW()
         ORDER BY created_at DESC LIMIT 1`,
        [decoded.seekerId]
      );
      if (result.rows.length === 0) throw new Error('Refresh token not found or expired');

      const seeker = await seekerService.findById(decoded.seekerId);
      if (!seeker) throw new Error('Seeker not found');

      return {
        success: true,
        accessToken: this.generateSeekerAccessToken(seeker),
        expiresIn: config.jwt.expiresIn,
      };
    }

    // Salon refresh tokens (existing logic)
    const result = await db.query(
      `SELECT * FROM refresh_tokens
       WHERE salon_id = $1
       AND is_revoked = false
       AND expires_at > NOW()
       ORDER BY created_at DESC
       LIMIT 1`,
      [decoded.salonId]
    );

    if (result.rows.length === 0) {
      throw new Error('Refresh token not found or expired');
    }

    // Get salon
    const salon = await salonService.findById(decoded.salonId);
    if (!salon) {
      throw new Error('Salon not found');
    }

    // Generate new access token
    const newAccessToken = this.generateAccessToken(salon);

    return {
      success: true,
      accessToken: newAccessToken,
      expiresIn: config.jwt.expiresIn,
    };
  }

  /**
   * Logout - revoke all refresh tokens for salon
   * @param {string} salonId - Salon UUID
   * @returns {Promise<object>} Logout result
   */
  async logout(salonId) {
    await db.query(
      `UPDATE refresh_tokens
       SET is_revoked = true
       WHERE salon_id = $1`,
      [salonId]
    );

    logger.info(`User logged out: ${salonId}`);

    return {
      success: true,
      message: 'Logged out successfully',
    };
  }

  /**
   * Clean up expired refresh tokens
   */
  async cleanupExpiredTokens() {
    try {
      await db.query(
        'DELETE FROM refresh_tokens WHERE expires_at < NOW()',
        []
      );
    } catch (error) {
      logger.error('Error cleaning up expired tokens:', error);
    }
  }
}

export default new AuthService();








