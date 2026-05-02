import express from 'express';
import { param, validationResult } from 'express-validator';
import callMaskingService from '../services/callMaskingService.js';
import { authenticate } from '../middleware/auth.js';
import { asyncHandler } from '../middleware/errorHandler.js';
import logger from '../utils/logger.js';

const router = express.Router();

/**
 * Validation middleware
 */
const handleValidationErrors = (req, res, next) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({
      success: false,
      message: 'Validation failed',
      errors: errors.array(),
    });
  }
  next();
};

// ===================== PROTECTED ROUTES (Salon Owner) =====================

/**
 * @route   POST /api/calls/initiate/:applicationId
 * @desc    Initiate a masked call to a candidate
 * @access  Protected (Salon owner — must own the job)
 *
 * Rules:
 *   - Application status must be 'shortlisted' or 'interview'
 *   - Max 3 calls per candidate per day (configurable)
 *   - Neither party sees the other's real number
 *
 * Response: { success, sessionId, callStatus, remainingCallsToday }
 */
router.post(
  '/initiate/:applicationId',
  authenticate,
  [
    param('applicationId').isUUID().withMessage('Invalid application ID'),
    handleValidationErrors,
  ],
  asyncHandler(async (req, res) => {
    const { applicationId } = req.params;
    const salonId = req.salonId;

    logger.info(`Owner ${salonId} initiating masked call for application ${applicationId}`);

    const result = await callMaskingService.initiateCall(applicationId, salonId);

    res.status(201).json({
      success: true,
      message: result.isDryRun
        ? 'Call session created (dry-run mode — Twilio not configured)'
        : 'Call initiated — connecting you now',
      ...result,
    });
  })
);

/**
 * @route   GET /api/calls/history/:applicationId
 * @desc    Get call history for a specific application
 * @access  Protected (Salon owner)
 */
router.get(
  '/history/:applicationId',
  authenticate,
  [
    param('applicationId').isUUID().withMessage('Invalid application ID'),
    handleValidationErrors,
  ],
  asyncHandler(async (req, res) => {
    const { applicationId } = req.params;
    const salonId = req.salonId;

    const result = await callMaskingService.getCallHistory(applicationId, salonId);

    res.json({
      success: true,
      ...result,
    });
  })
);

// ===================== TWILIO WEBHOOKS (Public — called by Twilio) =====================

/**
 * @route   POST /api/calls/webhook/connect/:sessionId
 * @desc    Twilio webhook — called when owner picks up. Bridges call to seeker.
 * @access  Public (Twilio calls this URL)
 *
 * Returns TwiML XML that tells Twilio to dial the seeker.
 */
router.post(
  '/webhook/connect/:sessionId',
  asyncHandler(async (req, res) => {
    const { sessionId } = req.params;

    logger.info(`Twilio connect webhook for session: ${sessionId}`);

    const twiml = await callMaskingService.handleConnectWebhook(sessionId);

    res.type('text/xml');
    res.send(twiml);
  })
);

/**
 * @route   POST /api/calls/webhook/status/:sessionId
 * @desc    Twilio status callback — updates call status and duration
 * @access  Public (Twilio calls this URL)
 *
 * Twilio POST body includes: CallStatus, CallDuration, CallSid, etc.
 */
router.post(
  '/webhook/status/:sessionId',
  asyncHandler(async (req, res) => {
    const { sessionId } = req.params;

    logger.info(`Twilio status webhook for session: ${sessionId}, status: ${req.body.CallStatus}`);

    await callMaskingService.handleStatusWebhook(sessionId, req.body);

    res.status(200).send('OK');
  })
);

export default router;
