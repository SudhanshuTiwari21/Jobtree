import express from 'express';
import { param, body, query, validationResult } from 'express-validator';
import ownerApplicationService from '../services/ownerApplicationService.js';
import interviewService from '../services/interviewService.js';
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

// ===================== OWNER APPLICATION MANAGEMENT =====================

/**
 * @route   GET /api/owner/jobs/:jobId/applications
 * @desc    Get all candidates (applications) for a specific job
 * @access  Protected (Salon owner — must own the job)
 *
 * Query params:
 *   - status (optional): filter by application status
 *   - limit (optional, default 20)
 *   - offset (optional, default 0)
 *
 * Response: { success, job, applications[], total, statusBreakdown }
 */
router.get(
  '/jobs/:jobId/applications',
  authenticate,
  [
    param('jobId').isUUID().withMessage('Invalid job ID'),
    query('status')
      .optional()
      .isIn(['applied', 'shortlisted', 'interview', 'rejected', 'hired'])
      .withMessage('Invalid status filter'),
    query('limit').optional().isInt({ min: 1, max: 100 }).withMessage('Limit must be 1-100'),
    query('offset').optional().isInt({ min: 0 }).withMessage('Offset must be >= 0'),
    handleValidationErrors,
  ],
  asyncHandler(async (req, res) => {
    const { jobId } = req.params;
    const salonId = req.salonId;
    const { status, limit = 20, offset = 0 } = req.query;

    logger.info(`Owner ${salonId} fetching candidates for job ${jobId}`);

    const result = await ownerApplicationService.getCandidatesForJob(jobId, salonId, {
      status,
      limit: parseInt(limit, 10),
      offset: parseInt(offset, 10),
    });

    res.json({
      success: true,
      ...result,
    });
  })
);

/**
 * @route   PATCH /api/owner/applications/:applicationId/status
 * @desc    Update a candidate's application status
 * @access  Protected (Salon owner — must own the job this application belongs to)
 *
 * Body: { status: "shortlisted" | "interview" | "rejected" | "hired" }
 *
 * Transition rules:
 *   applied     → shortlisted, rejected
 *   shortlisted → interview, rejected
 *   interview   → hired, rejected
 *   rejected    → (terminal, no transitions)
 *   hired       → (terminal, no transitions)
 *
 * Response: { success, application }
 */
router.patch(
  '/applications/:applicationId/status',
  authenticate,
  [
    param('applicationId').isUUID().withMessage('Invalid application ID'),
    body('status')
      .isIn(['applied', 'shortlisted', 'interview', 'rejected', 'hired'])
      .withMessage('Invalid status. Must be one of: applied, shortlisted, interview, rejected, hired'),
    handleValidationErrors,
  ],
  asyncHandler(async (req, res) => {
    const { applicationId } = req.params;
    const { status } = req.body;
    const salonId = req.salonId;

    logger.info(`Owner ${salonId} updating application ${applicationId} to status: ${status}`);

    const result = await ownerApplicationService.updateApplicationStatus(applicationId, status, salonId);

    res.json({
      success: true,
      message: `Application status updated to '${status}'`,
      application: result,
    });
  })
);

// ===================== INTERVIEW SCHEDULING =====================

/**
 * @route   POST /api/owner/applications/:applicationId/schedule-interview
 * @desc    Schedule an interview for a shortlisted candidate
 * @access  Protected (Salon owner)
 *
 * Body: { interviewAt, mode?, notes? }
 * Rules: application status must be 'shortlisted'
 */
router.post(
  '/applications/:applicationId/schedule-interview',
  authenticate,
  [
    param('applicationId').isUUID().withMessage('Invalid application ID'),
    body('interviewAt').isISO8601().withMessage('interviewAt must be a valid ISO date'),
    body('mode')
      .optional()
      .isIn(['in_person', 'phone_call', 'video_call'])
      .withMessage('mode must be in_person, phone_call, or video_call'),
    body('notes').optional().isString().trim(),
    handleValidationErrors,
  ],
  asyncHandler(async (req, res) => {
    const { applicationId } = req.params;
    const { interviewAt, mode, notes } = req.body;
    const salonId = req.salonId;

    logger.info(`Owner ${salonId} scheduling interview for application ${applicationId}`);

    const result = await interviewService.scheduleInterview(applicationId, salonId, {
      interviewAt,
      mode,
      notes,
    });

    res.status(201).json({
      success: true,
      message: 'Interview scheduled successfully',
      interview: result,
    });
  })
);

/**
 * @route   PATCH /api/owner/applications/:applicationId/reschedule-interview
 * @desc    Reschedule an existing interview
 * @access  Protected (Salon owner)
 *
 * Body: { interviewAt, mode?, notes? }
 * Rules: interview_status must be 'scheduled'
 */
router.patch(
  '/applications/:applicationId/reschedule-interview',
  authenticate,
  [
    param('applicationId').isUUID().withMessage('Invalid application ID'),
    body('interviewAt').isISO8601().withMessage('interviewAt must be a valid ISO date'),
    body('mode')
      .optional()
      .isIn(['in_person', 'phone_call', 'video_call'])
      .withMessage('mode must be in_person, phone_call, or video_call'),
    body('notes').optional().isString().trim(),
    handleValidationErrors,
  ],
  asyncHandler(async (req, res) => {
    const { applicationId } = req.params;
    const { interviewAt, mode, notes } = req.body;
    const salonId = req.salonId;

    logger.info(`Owner ${salonId} rescheduling interview for application ${applicationId}`);

    const result = await interviewService.rescheduleInterview(applicationId, salonId, {
      interviewAt,
      mode,
      notes,
    });

    res.json({
      success: true,
      message: 'Interview rescheduled successfully',
      interview: result,
    });
  })
);

/**
 * @route   PATCH /api/owner/applications/:applicationId/complete-interview
 * @desc    Mark an interview as completed (owner must then hire or reject)
 * @access  Protected (Salon owner)
 */
router.patch(
  '/applications/:applicationId/complete-interview',
  authenticate,
  [
    param('applicationId').isUUID().withMessage('Invalid application ID'),
    handleValidationErrors,
  ],
  asyncHandler(async (req, res) => {
    const { applicationId } = req.params;
    const salonId = req.salonId;

    logger.info(`Owner ${salonId} completing interview for application ${applicationId}`);

    const result = await interviewService.completeInterview(applicationId, salonId);

    res.json({
      success: true,
      message: 'Interview marked as completed. You can now hire or reject this candidate.',
      interview: result,
    });
  })
);

export default router;
