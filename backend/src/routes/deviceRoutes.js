import express from 'express';
import { body } from 'express-validator';
import { validate } from '../middleware/validation.js';
import { authenticateOwnerOrSeeker } from '../middleware/auth.js';
import pushService from '../services/pushService.js';
import { ApiError } from '../middleware/errorHandler.js';

const router = express.Router();

router.use(authenticateOwnerOrSeeker);

/**
 * POST /api/device/register
 * Body: { fcmToken, platform: "android" | "ios" }
 * Registers or updates FCM token for the authenticated user (owner or seeker).
 */
router.post(
  '/register',
  [
    body('fcmToken').isString().trim().notEmpty().withMessage('fcmToken is required'),
    body('platform').isIn(['android', 'ios']).withMessage('platform must be android or ios'),
  ],
  validate,
  async (req, res, next) => {
    try {
      const { fcmToken, platform } = req.body;
      await pushService.registerDevice(req.userId, req.userType, fcmToken, platform);
      return res.status(200).json({ success: true, message: 'Device registered' });
    } catch (error) {
      if (error.statusCode) return next(new ApiError(error.statusCode, error.message));
      return next(error);
    }
  }
);

/**
 * POST /api/device/test-push
 * Sends a test notification to the current user's registered device(s).
 * Use for verifying FCM (foreground, background, terminated).
 */
router.post('/test-push', async (req, res, next) => {
  try {
    pushService.sendNotification(req.userId, req.userType, {
      type: 'test',
      title: 'Test Push',
      body: 'If you see this, push notifications are working.',
      data: { deepLink: req.userType === 'owner' ? 'app://owner/job/test' : 'app://seeker/applications' },
    });
    return res.status(200).json({ success: true, message: 'Test notification sent' });
  } catch (error) {
    return next(error);
  }
});

/**
 * POST /api/device/unregister
 * Body: { fcmToken } (optional; if omitted, deactivate all tokens for this user)
 * Deactivates token(s) on logout.
 */
router.post(
  '/unregister',
  [body('fcmToken').optional().isString().trim()],
  validate,
  async (req, res, next) => {
    try {
      const { fcmToken } = req.body || {};
      if (fcmToken) {
        await pushService.unregisterDevice(req.userId, req.userType, fcmToken);
      } else {
        await pushService.deactivateAllDevicesForUser(req.userId, req.userType);
      }
      return res.status(200).json({ success: true, message: 'Device unregistered' });
    } catch (error) {
      return next(error);
    }
  }
);

export default router;
