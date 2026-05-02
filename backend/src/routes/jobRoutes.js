import express from 'express';
import { body, param, query, validationResult } from 'express-validator';
import jobService from '../services/jobService.js';
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

/**
 * Validators
 */
const createJobValidation = [
  body('jobRole')
    .isIn(['hair_stylist', 'beautician', 'makeup_artist', 'massage_therapist', 'receptionist', 'helper', 'manager', 'other'])
    .withMessage('Invalid job role'),
  body('location')
    .trim()
    .notEmpty()
    .withMessage('Location is required'),
  body('numberOfStaff')
    .optional()
    .isInt({ min: 1 })
    .withMessage('Number of staff must be at least 1'),
  body('salaryMin')
    .isFloat({ min: 0 })
    .withMessage('Minimum salary must be a positive number'),
  body('salaryMax')
    .isFloat({ min: 0 })
    .withMessage('Maximum salary must be a positive number'),
  body('workType')
    .isIn(['full_time', 'part_time'])
    .withMessage('Work type must be full_time or part_time'),
  body('experience')
    .isIn(['fresher_ok', 'experience_required'])
    .withMessage('Experience must be fresher_ok or experience_required'),
  body('accommodation')
    .optional()
    .isIn(['yes', 'no'])
    .withMessage('Accommodation must be yes or no'),
  body('preferredGender')
    .optional()
    .isIn(['male', 'female', 'any'])
    .withMessage('Preferred gender must be male, female, or any'),
  handleValidationErrors,
];

const updateJobValidation = [
  param('id').isUUID().withMessage('Invalid job ID'),
  body('jobRole')
    .optional()
    .isIn(['hair_stylist', 'beautician', 'makeup_artist', 'massage_therapist', 'receptionist', 'helper', 'manager', 'other'])
    .withMessage('Invalid job role'),
  body('salaryMin')
    .optional()
    .isFloat({ min: 0 })
    .withMessage('Minimum salary must be a positive number'),
  body('salaryMax')
    .optional()
    .isFloat({ min: 0 })
    .withMessage('Maximum salary must be a positive number'),
  body('workType')
    .optional()
    .isIn(['full_time', 'part_time'])
    .withMessage('Work type must be full_time or part_time'),
  body('status')
    .optional()
    .isIn(['draft', 'active', 'paused', 'closed'])
    .withMessage('Invalid status'),
  handleValidationErrors,
];

// ===================== PROTECTED ROUTES (Salon Owner) =====================

/**
 * @route   POST /api/jobs
 * @desc    Create a new job posting
 * @access  Protected (Salon owner)
 */
router.post(
  '/',
  authenticate,
  createJobValidation,
  asyncHandler(async (req, res) => {
    const salonId = req.salonId;
    
    logger.info(`Creating job for salon: ${salonId}`);
    
    const result = await jobService.createJob(salonId, req.body);
    
    res.status(201).json({
      success: true,
      message: 'Job posted successfully',
      job: result.job,
    });
  })
);

/**
 * @route   GET /api/jobs/my-jobs
 * @route   GET /api/jobs/my (alias – same behavior)
 * @desc    Get ALL jobs posted by the authenticated salon (source of truth)
 * @access  Protected (Salon owner)
 */
const getMyJobsHandler = asyncHandler(async (req, res) => {
  const salonId = req.salonId;
  const { status, limit = 20, offset = 0 } = req.query;

  const result = await jobService.getJobsBySalon(salonId, {
    status,
    limit: parseInt(limit, 10),
    offset: parseInt(offset, 10),
  });

  res.json({
    success: true,
    ...result,
  });
});

router.get('/my-jobs', authenticate, getMyJobsHandler);
router.get('/my', authenticate, getMyJobsHandler);

/**
 * @route   GET /api/jobs/:id
 * @desc    Get job by ID (owner view with full details)
 * @access  Protected (Salon owner)
 */
router.get(
  '/:id',
  authenticate,
  param('id').isUUID().withMessage('Invalid job ID'),
  handleValidationErrors,
  asyncHandler(async (req, res) => {
    const { id } = req.params;
    const salonId = req.salonId;
    
    const result = await jobService.getJobById(id, salonId);
    
    if (!result.success) {
      return res.status(404).json(result);
    }
    
    res.json({
      success: true,
      job: result.job,
    });
  })
);

/**
 * @route   PATCH /api/jobs/:id
 * @desc    Update a job posting
 * @access  Protected (Salon owner)
 */
router.patch(
  '/:id',
  authenticate,
  updateJobValidation,
  asyncHandler(async (req, res) => {
    const { id } = req.params;
    const salonId = req.salonId;
    
    logger.info(`Updating job: ${id} by salon: ${salonId}`);
    
    const result = await jobService.updateJob(id, salonId, req.body);
    
    if (!result.success) {
      return res.status(404).json(result);
    }
    
    // Recalculate completion percentage
    await jobService.updateJobCompletion(id, salonId);
    
    // Fetch updated job
    const updatedJob = await jobService.getJobById(id, salonId);
    
    res.json({
      success: true,
      message: 'Job updated successfully',
      job: updatedJob.job,
    });
  })
);

/**
 * @route   DELETE /api/jobs/:id
 * @desc    Close/delete a job posting
 * @access  Protected (Salon owner)
 */
router.delete(
  '/:id',
  authenticate,
  param('id').isUUID().withMessage('Invalid job ID'),
  handleValidationErrors,
  asyncHandler(async (req, res) => {
    const { id } = req.params;
    const salonId = req.salonId;
    
    logger.info(`Closing job: ${id} by salon: ${salonId}`);
    
    const result = await jobService.deleteJob(id, salonId);
    
    if (!result.success) {
      return res.status(404).json(result);
    }
    
    res.json({
      success: true,
      message: 'Job closed successfully',
    });
  })
);

/**
 * @route   GET /api/jobs/:id/completion
 * @desc    Get job completion percentage
 * @access  Protected (Salon owner)
 */
router.get(
  '/:id/completion',
  authenticate,
  param('id').isUUID().withMessage('Invalid job ID'),
  handleValidationErrors,
  asyncHandler(async (req, res) => {
    const { id } = req.params;
    const salonId = req.salonId;
    
    const result = await jobService.getJobCompletion(id, salonId);
    
    if (!result.success) {
      return res.status(404).json(result);
    }
    
    res.json({
      success: true,
      completionPercent: result.completionPercent,
    });
  })
);

// ===================== PUBLIC ROUTES (Job Seekers) =====================

/**
 * @route   GET /api/jobs/search
 * @desc    Search/browse active jobs (for job seekers)
 * @access  Public
 */
router.get(
  '/search',
  [
    query('location').optional().trim(),
    query('jobRole').optional().isIn(['hair_stylist', 'beautician', 'makeup_artist', 'massage_therapist', 'receptionist', 'helper', 'manager', 'other']),
    query('workType').optional().isIn(['full_time', 'part_time']),
    query('experience').optional().isIn(['fresher_ok', 'experience_required']),
    query('salaryMin').optional().isFloat({ min: 0 }),
    query('salaryMax').optional().isFloat({ min: 0 }),
    query('limit').optional().isInt({ min: 1, max: 50 }),
    query('offset').optional().isInt({ min: 0 }),
    handleValidationErrors,
  ],
  asyncHandler(async (req, res) => {
    const {
      location,
      jobRole,
      workType,
      experience,
      salaryMin,
      salaryMax,
      limit = 20,
      offset = 0,
    } = req.query;
    
    const result = await jobService.searchJobs({
      location,
      jobRole,
      workType,
      experience,
      salaryMin: salaryMin ? parseFloat(salaryMin) : undefined,
      salaryMax: salaryMax ? parseFloat(salaryMax) : undefined,
      limit: parseInt(limit),
      offset: parseInt(offset),
    });
    
    res.json({
      success: true,
      ...result,
    });
  })
);

/**
 * @route   GET /api/jobs/public/:id
 * @desc    Get job details for job seeker (public view)
 * @access  Public
 */
router.get(
  '/public/:id',
  param('id').isUUID().withMessage('Invalid job ID'),
  handleValidationErrors,
  asyncHandler(async (req, res) => {
    const { id } = req.params;
    
    const result = await jobService.getJobById(id);
    
    if (!result.success) {
      return res.status(404).json(result);
    }
    
    // Check if job is active
    if (result.job.status !== 'active') {
      return res.status(404).json({
        success: false,
        message: 'Job not available',
      });
    }
    
    // Increment view count
    await jobService.incrementViews(id);
    
    // Return public-safe job data (hide some internal fields)
    const publicJob = {
      id: result.job.id,
      jobRole: result.job.jobRole,
      customRoleName: result.job.customRoleName,
      skills: result.job.skills,
      location: result.job.location,
      numberOfStaff: result.job.numberOfStaff,
      salaryMin: result.job.salaryMin,
      salaryMax: result.job.salaryMax,
      workType: result.job.workType,
      experience: result.job.experience,
      accommodation: result.job.accommodation,
      preferredGender: result.job.preferredGender,
      description: result.job.description,
      shiftType: result.job.shiftType,
      weeklyOff: result.job.weeklyOff,
      facilities: result.job.facilities,
      createdAt: result.job.createdAt,
    };
    
    res.json({
      success: true,
      job: publicJob,
    });
  })
);

export default router;

