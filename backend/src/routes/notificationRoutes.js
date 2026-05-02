import express from 'express';
import notificationService from '../services/notificationService.js';
import pushService from '../services/pushService.js';
import { authenticate, authenticateOwnerOrSeeker } from '../middleware/auth.js';

const router = express.Router();

/**
 * GET /api/notifications
 * Get push notification log for authenticated user (owner or seeker). Paginated.
 */
router.get('/', authenticateOwnerOrSeeker, async (req, res) => {
  try {
    const { limit = 50, offset = 0, unreadOnly = false } = req.query;
    const result = await pushService.getNotifications(req.userId, req.userType, {
      limit: parseInt(limit, 10) || 50,
      offset: parseInt(offset, 10) || 0,
      unreadOnly: unreadOnly === 'true',
    });
    res.json({ success: true, data: result });
  } catch (error) {
    console.error('Get notifications error:', error);
    res.status(500).json({ success: false, message: 'Failed to fetch notifications' });
  }
});

/**
 * GET /api/notifications/unread-count
 * Get unread push notification count (owner or seeker).
 */
router.get('/unread-count', authenticateOwnerOrSeeker, async (req, res) => {
  try {
    const count = await pushService.getUnreadCount(req.userId, req.userType);
    res.json({ success: true, data: { count } });
  } catch (error) {
    console.error('Get unread count error:', error);
    res.status(500).json({ success: false, message: 'Failed to get unread count' });
  }
});

/**
 * PATCH /api/notifications/read-all
 * Mark all push notifications as read (owner or seeker). Must be before /:id/read.
 */
router.patch('/read-all', authenticateOwnerOrSeeker, async (req, res) => {
  try {
    await pushService.markAllAsRead(req.userId, req.userType);
    res.json({ success: true, message: 'All notifications marked as read' });
  } catch (error) {
    console.error('Mark all as read error:', error);
    res.status(500).json({ success: false, message: 'Failed to mark all notifications as read' });
  }
});

/**
 * PATCH /api/notifications/:id/read
 * Mark a push notification as read (owner or seeker).
 */
router.patch('/:id/read', authenticateOwnerOrSeeker, async (req, res) => {
  try {
    const notificationId = req.params.id;
    const result = await pushService.markAsRead(notificationId, req.userId, req.userType);
    if (!result.success) {
      return res.status(404).json({ success: false, message: 'Notification not found' });
    }
    res.json({ success: true, data: result });
  } catch (error) {
    console.error('Mark notification as read error:', error);
    res.status(500).json({ success: false, message: 'Failed to mark notification as read' });
  }
});

/**
 * GET /api/notifications/preferences
 * Get notification preferences
 */
router.get('/preferences', authenticate, async (req, res) => {
  try {
    const salonId = req.salon.id;
    const preferences = await notificationService.getPreferences(salonId);

    res.json({
      success: true,
      data: preferences,
    });
  } catch (error) {
    console.error('Get preferences error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch preferences',
    });
  }
});

/**
 * PATCH /api/notifications/preferences
 * Update notification preferences
 */
router.patch('/preferences', authenticate, async (req, res) => {
  try {
    const salonId = req.salon.id;
    const updates = req.body;

    const result = await notificationService.updatePreferences(salonId, updates);

    if (!result.success) {
      return res.status(400).json({
        success: false,
        message: result.message || 'Failed to update preferences',
      });
    }

    res.json({
      success: true,
      data: result.preferences,
    });
  } catch (error) {
    console.error('Update preferences error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update preferences',
    });
  }
});

/**
 * POST /api/notifications/push-token
 * Register push token
 */
router.post('/push-token', authenticate, async (req, res) => {
  try {
    const salonId = req.salon.id;
    const { device_type, push_token } = req.body;

    if (!device_type || !push_token) {
      return res.status(400).json({
        success: false,
        message: 'device_type and push_token are required',
      });
    }

    if (!['ios', 'android', 'web'].includes(device_type)) {
      return res.status(400).json({
        success: false,
        message: 'device_type must be ios, android, or web',
      });
    }

    const result = await notificationService.registerPushToken(
      salonId,
      device_type,
      push_token
    );

    res.json({
      success: true,
      data: result.token,
    });
  } catch (error) {
    console.error('Register push token error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to register push token',
    });
  }
});

export default router;

