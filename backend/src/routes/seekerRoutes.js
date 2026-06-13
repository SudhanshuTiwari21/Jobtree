import express from 'express';
import { body, param } from 'express-validator';
import seekerService from '../services/seekerService.js';
import applicationService from '../services/applicationService.js';
import interviewService from '../services/interviewService.js';
import jobService from '../services/jobService.js';
import { authenticateSeeker } from '../middleware/auth.js';
import { asyncHandler } from '../middleware/errorHandler.js';
import { validate, validateMediaPresign } from '../middleware/validation.js';
import logger from '../utils/logger.js';
import s3Service from '../services/s3Service.js';

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
    const seeker = await seekerService.syncStoredCompletion(req.seekerId);
    const prefs = await seekerService.getPreferences(req.seekerId);
    res.json({
      success: true,
      seeker: await seekerService.formatSeekerResponse(seeker, prefs),
    });
  })
);

/**
 * @route   POST /api/seeker/media/presign
 * @desc    Presigned URL for seeker profile photo upload
 * @access  Protected (Seeker)
 */
router.post(
  '/media/presign',
  authenticateSeeker,
  validateMediaPresign,
  asyncHandler(async (req, res) => {
    const { mediaType, contentType, filename } = req.body;
    const presignedData = await s3Service.generateSeekerUploadUrl(
      req.seekerId,
      mediaType,
      contentType,
      filename
    );
    res.status(200).json({
      success: true,
      message: 'Presigned URL generated',
      data: presignedData,
    });
  })
);

const seekerDirectUploadAllowedTypes = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/gif',
  'image/heic',
  'image/heif',
  'video/mp4',
  'video/quicktime',
  'video/webm',
]);

/**
 * @route   POST /api/seeker/media/upload
 * @desc    Upload image/video bytes through API; returns fileUrl for profile PATCH (no S3 presigned PUT from client)
 * @access  Protected (Seeker)
 */
router.post(
  '/media/upload',
  authenticateSeeker,
  express.raw({ limit: '20mb', type: '*/*' }),
  asyncHandler(async (req, res) => {
    const rawCt = (req.get('Content-Type') || '').split(';')[0].trim().toLowerCase();
    if (!Buffer.isBuffer(req.body) || req.body.length === 0) {
      return res.status(400).json({ success: false, message: 'Empty body' });
    }
    if (!seekerDirectUploadAllowedTypes.has(rawCt)) {
      return res.status(400).json({ success: false, message: 'Unsupported content type' });
    }

    const mediaType = String(req.get('X-Media-Type') || 'photo').toLowerCase();
    if (!['photo', 'video'].includes(mediaType)) {
      return res.status(400).json({ success: false, message: 'Invalid X-Media-Type' });
    }

    const filename = req.get('X-Filename')?.trim() || '';

    const fileUrl = await s3Service.uploadSeekerBuffer(req.seekerId, mediaType, rawCt, req.body, {
      filename,
    });

    const displayUrl = await s3Service.presignGetUrl(fileUrl);

    res.status(201).json({
      success: true,
      message: 'Media uploaded successfully',
      data: { fileUrl, displayUrl: displayUrl || fileUrl },
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
  body('preferredRole').optional().trim().isLength({ min: 1, max: 100 }).withMessage('Role must be 1-100 characters'),
  body('experience').optional().trim().isLength({ max: 50 }),
  body('experienceYears').optional().isInt({ min: 0, max: 50 }),
  body('expectedSalary').optional().isFloat({ min: 0 }),
  body('expectedSalaryMax').optional().isFloat({ min: 0 }),
  body('currentSalary').optional().isFloat({ min: 0 }),
  body('maritalStatus').optional().isIn(['single', 'married', 'widowed', 'divorced', 'prefer_not_say']),
  body('email').optional({ values: 'falsy' }).trim().isEmail().isLength({ max: 255 }),
  body('hasProfessionalCourse').optional().isBoolean(),
  body('professionalCourseCertificateUrl').optional().trim(),
  body('workPortfolioUrls').optional().isArray(),
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
    const prefs = await seekerService.getPreferences(req.seekerId);

    res.json({
      success: true,
      message: 'Profile updated successfully',
      seeker: await seekerService.formatSeekerResponse(seeker, prefs),
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
    const prefs = await seekerService.getPreferences(req.seekerId);

    res.json({
      success: true,
      message: 'Profile updated',
      seeker: await seekerService.formatSeekerResponse(seeker, prefs),
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
    const { city, role, limit = 20, offset = 0, browseAll } = req.query;

    const seeker = req.seeker;
    const showAll = browseAll === 'true' || browseAll === '1';
    const filterCity = showAll ? (city || null) : (city || seeker.city || null);
    const filterRole = showAll ? (role || null) : (role || seeker.preferred_role || null);

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
