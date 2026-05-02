import express from 'express';
import { body, param } from 'express-validator';
import seekerService from '../services/seekerService.js';
import applicationService from '../services/applicationService.js';
import interviewService from '../services/interviewService.js';
import jobService from '../services/jobService.js';
import { authenticateSeeker } from '../middleware/auth.js';
import { asyncHandler } from '../middleware/errorHandler.js';
import { validate } from '../middleware/validation.js';
import logger from '../utils/logger.js';

const router = express.Router();

// ===================== SEEKER PROFILE =====================

/**
 * @route   GET /api/seeker/profile
 * @desc    Get current seeker profile
 * @access  Protected (Seeker)
 */
router.get(
  '/profile',
  authenticateSeeker,
  asyncHandler(async (req, res) => {
    const seeker = await seekerService.findById(req.seekerId);
    res.json({
      success: true,
      seeker: seekerService.formatSeekerResponse(seeker),
    });
  })
);

/**
 * @route   POST /api/seeker/profile
 * @desc    Create / complete seeker profile (minimal onboarding)
 * @access  Protected (Seeker)
 */
const profileValidation = [
  body('fullName').optional().trim().isLength({ min: 1, max: 100 }).withMessage('Name must be 1-100 characters'),
  body('gender').optional().isIn(['male', 'female', 'other']).withMessage('Invalid gender'),
  body('city').optional().trim().isLength({ min: 1, max: 100 }).withMessage('City must be 1-100 characters'),
  body('preferredRole').optional().trim().isLength({ min: 1, max: 50 }).withMessage('Role must be 1-50 characters'),
  body('experience').optional().trim().isLength({ max: 50 }),
  body('expectedSalary').optional().isFloat({ min: 0 }),
  body('skills').optional().isArray(),
  body('profilePhotoUrl').optional().trim(),
  validate,
];

router.post(
  '/profile',
  authenticateSeeker,
  profileValidation,
  asyncHandler(async (req, res) => {
    const { seeker } = await seekerService.updateProfile(req.seekerId, req.body);
    logger.info(`Seeker profile updated: ${req.seekerId}`);

    res.json({
      success: true,
      message: 'Profile updated successfully',
      seeker: seekerService.formatSeekerResponse(seeker),
    });
  })
);

/**
 * @route   PATCH /api/seeker/profile
 * @desc    Partial profile update (progressive enhancement)
 * @access  Protected (Seeker)
 */
router.patch(
  '/profile',
  authenticateSeeker,
  profileValidation,
  asyncHandler(async (req, res) => {
    const { seeker } = await seekerService.updateProfile(req.seekerId, req.body);

    res.json({
      success: true,
      message: 'Profile updated',
      seeker: seekerService.formatSeekerResponse(seeker),
    });
  })
);

/**
 * @route   GET /api/seeker/completion
 * @desc    Get profile completion breakdown
 * @access  Protected (Seeker)
 */
router.get(
  '/completion',
  authenticateSeeker,
  asyncHandler(async (req, res) => {
    const completion = await seekerService.getCompletion(req.seekerId);
    res.json({ success: true, ...completion });
  })
);

// ===================== SEEKER PREFERENCES =====================

/**
 * @route   GET /api/seeker/preferences
 * @desc    Get seeker preferences
 * @access  Protected (Seeker)
 */
router.get(
  '/preferences',
  authenticateSeeker,
  asyncHandler(async (req, res) => {
    const prefs = await seekerService.getPreferences(req.seekerId);
    res.json({
      success: true,
      preferences: seekerService.formatPreferencesResponse(prefs),
    });
  })
);

/**
 * @route   PATCH /api/seeker/preferences
 * @desc    Update seeker preferences
 * @access  Protected (Seeker)
 */
router.patch(
  '/preferences',
  authenticateSeeker,
  [
    body('jobType').optional().isIn(['full_time', 'part_time', 'any']),
    body('preferredSalary').optional().isFloat({ min: 0 }),
    body('preferredCities').optional().isArray(),
    body('immediateJoin').optional().isBoolean(),
    validate,
  ],
  asyncHandler(async (req, res) => {
    const prefs = await seekerService.updatePreferences(req.seekerId, req.body);
    res.json({
      success: true,
      message: 'Preferences updated',
      preferences: seekerService.formatPreferencesResponse(prefs),
    });
  })
);

// ===================== JOB FEED (for seekers) =====================

/**
 * @route   GET /api/seeker/jobs
 * @desc    Browse active jobs for seekers (with city/role filters)
 * @access  Protected (Seeker)
 */
router.get(
  '/jobs',
  authenticateSeeker,
  asyncHandler(async (req, res) => {
    const { city, role, limit = 20, offset = 0 } = req.query;

    // Use seeker profile defaults if no filters given
    const seeker = req.seeker;
    const filterCity = city || seeker.city || null;
    const filterRole = role || seeker.preferred_role || null;

    const result = await jobService.searchJobs({
      location: filterCity,
      jobRole: filterRole,
      limit: parseInt(limit, 10),
      offset: parseInt(offset, 10),
    });

    // Attach "applied" flag for this seeker
    const appliedJobIds = await applicationService.getAppliedJobIds(req.seekerId);
    const appliedSet = new Set(appliedJobIds);

    const jobs = (result.jobs || []).map((job) => ({
      ...job,
      hasApplied: appliedSet.has(job.id),
    }));

    res.json({
      success: true,
      jobs,
      total: result.total,
    });
  })
);

// ===================== APPLICATIONS =====================

/**
 * @route   POST /api/seeker/apply
 * @desc    Apply to a job
 * @access  Protected (Seeker)
 */
router.post(
  '/apply',
  authenticateSeeker,
  [
    body('jobId').notEmpty().isUUID().withMessage('Valid job ID is required'),
    validate,
  ],
  asyncHandler(async (req, res) => {
    try {
      const application = await applicationService.apply(req.seekerId, req.body.jobId);
      res.status(201).json({
        success: true,
        message: 'Application submitted successfully',
        application,
      });
    } catch (error) {
      const status = error.statusCode || 500;
      res.status(status).json({
        success: false,
        message: error.message,
      });
    }
  })
);

/**
 * @route   GET /api/seeker/applications
 * @desc    Get seeker's applications
 * @access  Protected (Seeker)
 */
router.get(
  '/applications',
  authenticateSeeker,
  asyncHandler(async (req, res) => {
    const { limit = 20, offset = 0 } = req.query;
    const result = await applicationService.getBySeeker(req.seekerId, {
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
 * @route   GET /api/seeker/applications/:applicationId/interview
 * @desc    Get interview details for a specific application
 * @access  Protected (Seeker — must own the application)
 */
router.get(
  '/applications/:applicationId/interview',
  authenticateSeeker,
  asyncHandler(async (req, res) => {
    const { applicationId } = req.params;
    const seekerId = req.seekerId;

    const details = await interviewService.getInterviewDetails(applicationId);

    // Verify seeker owns this application
    if (details.seekerId && details.seekerId !== seekerId) {
      return res.status(403).json({ success: false, message: 'Access denied' });
    }

    res.json({
      success: true,
      interview: details,
    });
  })
);

export default router;
