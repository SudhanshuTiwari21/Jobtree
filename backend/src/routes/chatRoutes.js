import express from 'express';
import { param, query } from 'express-validator';
import { authenticateOwnerOrSeeker } from '../middleware/auth.js';
import { asyncHandler } from '../middleware/errorHandler.js';
import { validate } from '../middleware/validation.js';
import chatService from '../services/chatService.js';

const router = express.Router();

/**
 * @route GET /api/chat/threads
 * @desc List application threads for owner (salon) or seeker
 */
router.get(
  '/threads',
  authenticateOwnerOrSeeker,
  asyncHandler(async (req, res) => {
    const threads = req.userType === 'owner'
      ? await chatService.listThreadsForSalon(req.salonId)
      : await chatService.listThreadsForSeeker(req.seekerId);
    res.json({ success: true, threads });
  })
);

/**
 * @route GET /api/chat/applications/:applicationId/messages
 * @desc Paginated chat history (oldest-first in response array)
 */
router.get(
  '/applications/:applicationId/messages',
  authenticateOwnerOrSeeker,
  param('applicationId').isUUID().withMessage('Invalid application id'),
  query('limit').optional().isInt({ min: 1, max: 100 }),
  validate,
  asyncHandler(async (req, res) => {
    const { applicationId } = req.params;
    const userId = req.userType === 'owner' ? req.salonId : req.seekerId;
    await chatService.assertParticipant(applicationId, req.userType, userId);
    const limit = parseInt(req.query.limit, 10) || 50;
    const messages = await chatService.listMessages(applicationId, { limit });
    res.json({ success: true, messages });
  })
);

export default router;
