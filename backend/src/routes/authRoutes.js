import express from 'express';
import otpService from '../services/otpService.js';
import authService from '../services/authService.js';
import { validatePhoneNumber, validateOTP, validateRefreshToken } from '../middleware/validation.js';
import { otpRateLimiter } from '../middleware/security.js';
import { authenticate } from '../middleware/auth.js';
import { asyncHandler } from '../middleware/errorHandler.js';
import logger from '../utils/logger.js';

const router = express.Router();

/**
 * @route   POST /api/auth/send-otp
 * @desc    Send OTP to phone number
 * @access  Public
 */
router.post(
  '/send-otp',
  otpRateLimiter,
  validatePhoneNumber,
  asyncHandler(async (req, res) => {
    const { phoneNumber, countryCode = '+91', smsAppHash } = req.body;

    logger.info(`OTP send request for: ${phoneNumber}`);

    const result = await otpService.sendOTP(phoneNumber, countryCode, smsAppHash || null);

    if (!result.success) {
      return res.status(429).json({
        success: false,
        message: result.message,
        waitSeconds: result.waitSeconds,
      });
    }

    res.status(200).json({
      success: true,
      message: 'OTP sent successfully',
      expiresIn: result.expiresIn,
    });
  })
);

/**
 * @route   POST /api/auth/resend-otp
 * @desc    Resend OTP to phone number
 * @access  Public
 */
router.post(
  '/resend-otp',
  otpRateLimiter,
  validatePhoneNumber,
  asyncHandler(async (req, res) => {
    const { phoneNumber, countryCode = '+91', smsAppHash } = req.body;

    logger.info(`OTP resend request for: ${phoneNumber}`);

    const result = await otpService.resendOTP(phoneNumber, countryCode, smsAppHash || null);

    if (!result.success) {
      return res.status(429).json({
        success: false,
        message: result.message,
        waitSeconds: result.waitSeconds,
      });
    }

    res.status(200).json({
      success: true,
      message: 'OTP resent successfully',
      expiresIn: result.expiresIn,
    });
  })
);

/**
 * @route   POST /api/auth/verify-otp
 * @desc    Verify OTP and login/signup
 * @access  Public
 */
router.post(
  '/verify-otp',
  validateOTP,
  asyncHandler(async (req, res) => {
    const { phoneNumber, otp, countryCode = '+91', role } = req.body;

    logger.info(`OTP verification request for: ${phoneNumber} (role: ${role || 'unified'})`);

    // Verify OTP first
    const verifyResult = await otpService.verifyOTP(phoneNumber, otp);

    if (!verifyResult.success) {
      return res.status(400).json({
        success: false,
        message: verifyResult.message,
        attemptsRemaining: verifyResult.attemptsRemaining,
      });
    }

    // Job seeker login — issue seeker JWT directly
    if (role === 'seeker') {
      const seekerResult = await authService.seekerLoginOrSignup(phoneNumber, countryCode);
      return res.status(200).json({
        success: true,
        message: seekerResult.isNewUser ? 'Account created successfully' : 'Login successful',
        isNewUser: seekerResult.isNewUser,
        seekerProfileExists: seekerResult.seekerProfileExists,
        seekerExists: seekerResult.seekerProfileExists,
        accessToken: seekerResult.accessToken,
        refreshToken: seekerResult.refreshToken,
        expiresIn: seekerResult.expiresIn,
        seeker: seekerResult.seeker,
      });
    }

    // Unified login — always returns ownerExists + seekerExists (salon JWT)
    const authResult = await authService.unifiedLogin(phoneNumber, countryCode);

    res.status(200).json({
      success: true,
      message: authResult.isNewUser ? 'Account created successfully' : 'Login successful',
      isNewUser: authResult.isNewUser,
      ownerExists: authResult.ownerExists,
      seekerExists: authResult.seekerExists,
      accessToken: authResult.accessToken,
      refreshToken: authResult.refreshToken,
      expiresIn: authResult.expiresIn,
      salon: authResult.salon,
    });
  })
);

/**
 * @route   POST /api/auth/switch-role
 * @desc    Switch between salon and seeker roles. Uses existing auth to issue a new token.
 * @access  Protected (salon token)
 */
router.post(
  '/switch-role',
  authenticate,
  asyncHandler(async (req, res) => {
    const { role } = req.body; // 'seeker' or 'salon'
    const phoneNumber = req.salon.phone_number;

    if (role === 'seeker') {
      const result = await authService.seekerLoginOrSignup(phoneNumber, req.salon.country_code || '+91');
      return res.json({
        success: true,
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        expiresIn: result.expiresIn,
        seekerProfileExists: result.seekerProfileExists,
        seeker: result.seeker,
      });
    }

    // Default: return salon token (already have it)
    res.json({
      success: true,
      message: 'Already authenticated as salon owner',
    });
  })
);

/**
 * @route   POST /api/auth/refresh
 * @desc    Refresh access token
 * @access  Public
 */
router.post(
  '/refresh',
  validateRefreshToken,
  asyncHandler(async (req, res) => {
    const { refreshToken } = req.body;

    const result = await authService.refreshAccessToken(refreshToken);

    res.status(200).json({
      success: true,
      accessToken: result.accessToken,
      expiresIn: result.expiresIn,
    });
  })
);

/**
 * @route   POST /api/auth/logout
 * @desc    Logout - revoke refresh tokens
 * @access  Protected
 */
router.post(
  '/logout',
  authenticate,
  asyncHandler(async (req, res) => {
    const result = await authService.logout(req.salonId);

    res.status(200).json({
      success: true,
      message: result.message,
    });
  })
);

/**
 * @route   GET /api/auth/otp-status/:phoneNumber
 * @desc    Get OTP status (development only)
 * @access  Public (dev only)
 */
router.get(
  '/otp-status/:phoneNumber',
  asyncHandler(async (req, res) => {
    if (process.env.NODE_ENV === 'production') {
      return res.status(404).json({
        success: false,
        message: 'Not found',
      });
    }

    const { phoneNumber } = req.params;
    const status = await otpService.getOTPStatus(phoneNumber);

    if (!status) {
      return res.status(404).json({
        success: false,
        message: 'No active OTP found',
      });
    }

    res.status(200).json({
      success: true,
      data: status,
    });
  })
);

export default router;














