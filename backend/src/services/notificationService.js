import db from '../database/connection.js';
import logger from '../utils/logger.js';
import pushService from './pushService.js';

/** Convert internal deep link (e.g. /candidates/jobId) to app scheme for push (app://owner/job/jobId) */
function toAppDeepLink(deepLink) {
  if (!deepLink) return '';
  if (deepLink.startsWith('app://')) return deepLink;
  const match = deepLink.match(/^\/candidates\/([^/]+)/);
  return match ? `app://owner/job/${match[1]}` : `app://owner${deepLink}`;
}

/**
 * Notification Service
 * Handles all notification-related business logic for job owners (salon owners)
 * 
 * IMPORTANT: This service is ONLY for job owners, not job seekers
 */
class NotificationService {
  /**
   * Create a notification for a salon
   * @param {string} salonId - Salon UUID
   * @param {string} type - Notification type (from notification_type enum)
   * @param {string} title - Notification title
   * @param {string} message - Notification message
   * @param {string} deepLink - Optional deep link
   * @returns {Promise<object>} Created notification
   */
  async createNotification(salonId, type, title, message, deepLink = null) {
    try {
      // Check if salon has preferences enabled for this notification type
      const shouldNotify = await this.shouldSendNotification(salonId, type);
      
      if (!shouldNotify) {
        logger.info(`Notification skipped for salon ${salonId}, type ${type} (preference disabled)`);
        return { success: false, skipped: true };
      }

      const result = await db.query(
        `INSERT INTO notifications (salon_id, type, title, message, deep_link)
         VALUES ($1, $2, $3, $4, $5)
         RETURNING *`,
        [salonId, type, title, message, deepLink]
      );

      const notification = result.rows[0];

      // Track analytics: NOTIFICATION_SENT
      await this.trackEvent(salonId, 'NOTIFICATION_SENT', notification.id);

      // Send push via single source of truth (pushService: FCM, log, retry, token deactivation)
      if (this.shouldSendPush(type)) {
        pushService.sendNotification(salonId, 'owner', {
          type,
          title,
          body: message,
          data: { deepLink: toAppDeepLink(deepLink) },
        });
      }

      logger.info(`Notification created: ${notification.id} for salon: ${salonId}, type: ${type}`);
      
      return { success: true, notification };
    } catch (error) {
      logger.error('Create notification error:', error.message);
      throw error;
    }
  }

  /**
   * Check if notification should be sent based on preferences
   * @param {string} salonId - Salon UUID
   * @param {string} type - Notification type
   * @returns {Promise<boolean>} Whether to send notification
   */
  async shouldSendNotification(salonId, type) {
    try {
      // Get or create preferences
      const prefs = await this.getPreferences(salonId);
      
      // Map notification types to preference fields
      const typeToPreference = {
        'CANDIDATE_APPLIED': 'hiring_updates',
        'CANDIDATE_REPLIED': 'hiring_updates',
        'INTERVIEW_REMINDER': 'hiring_updates',
        'JOB_PERFORMANCE_TIP': 'job_tips',
        'PROFILE_INCOMPLETE': 'profile_improvements',
        'ACCOUNT_ALERT': 'account_alerts',
        'PROMOTION': 'promotions',
      };

      const preferenceField = typeToPreference[type];
      if (!preferenceField) {
        return true; // Default to true if type not mapped
      }

      // hiring_updates must always be true (cannot be disabled)
      if (preferenceField === 'hiring_updates') {
        return true;
      }

      return prefs[preferenceField] === true;
    } catch (error) {
      logger.error('Error checking notification preference:', error.message);
      return true; // Default to true on error
    }
  }

  /**
   * Check if push notification should be sent (only for high-intent events)
   * @param {string} type - Notification type
   * @returns {boolean} Whether to send push
   */
  shouldSendPush(type) {
    const pushTypes = [
      'CANDIDATE_APPLIED',
      'CANDIDATE_REPLIED',
      'INTERVIEW_REMINDER',
    ];
    return pushTypes.includes(type);
  }

  /**
   * Get notifications for a salon
   * @param {string} salonId - Salon UUID
   * @param {object} options - Query options
   * @returns {Promise<object>} Notifications with pagination
   */
  async getNotifications(salonId, options = {}) {
    const { limit = 50, offset = 0, unreadOnly = false } = options;

    try {
      let query = `
        SELECT * FROM notifications 
        WHERE salon_id = $1
      `;
      const params = [salonId];
      let paramIndex = 2;

      if (unreadOnly) {
        query += ` AND is_read = false`;
      }

      query += ` ORDER BY created_at DESC LIMIT $${paramIndex} OFFSET $${paramIndex + 1}`;
      params.push(limit, offset);

      const result = await db.query(query, params);

      // Get total count
      let countQuery = 'SELECT COUNT(*) FROM notifications WHERE salon_id = $1';
      const countParams = [salonId];
      if (unreadOnly) {
        countQuery += ' AND is_read = false';
      }
      const countResult = await db.query(countQuery, countParams);

      return {
        success: true,
        notifications: result.rows,
        total: parseInt(countResult.rows[0].count),
        limit,
        offset,
      };
    } catch (error) {
      logger.error('Get notifications error:', error.message);
      throw error;
    }
  }

  /**
   * Mark notification as read
   * @param {string} notificationId - Notification UUID
   * @param {string} salonId - Salon UUID (for security)
   * @returns {Promise<object>} Updated notification
   */
  async markAsRead(notificationId, salonId) {
    try {
      const result = await db.query(
        `UPDATE notifications 
         SET is_read = true 
         WHERE id = $1 AND salon_id = $2
         RETURNING *`,
        [notificationId, salonId]
      );

      if (result.rows.length === 0) {
        return { success: false, message: 'Notification not found' };
      }

      const notification = result.rows[0];

      // Track analytics: NOTIFICATION_OPENED
      await this.trackEvent(salonId, 'NOTIFICATION_OPENED', notificationId);

      return { success: true, notification };
    } catch (error) {
      logger.error('Mark notification as read error:', error.message);
      throw error;
    }
  }

  /**
   * Mark all notifications as read for a salon
   * @param {string} salonId - Salon UUID
   * @returns {Promise<object>} Result
   */
  async markAllAsRead(salonId) {
    try {
      await db.query(
        `UPDATE notifications 
         SET is_read = true 
         WHERE salon_id = $1 AND is_read = false`,
        [salonId]
      );

      return { success: true };
    } catch (error) {
      logger.error('Mark all as read error:', error.message);
      throw error;
    }
  }

  /**
   * Get notification preferences for a salon
   * @param {string} salonId - Salon UUID
   * @returns {Promise<object>} Preferences
   */
  async getPreferences(salonId) {
    try {
      const result = await db.query(
        `SELECT * FROM notification_preferences WHERE salon_id = $1`,
        [salonId]
      );

      if (result.rows.length === 0) {
        // Create default preferences
        return await this.createDefaultPreferences(salonId);
      }

      return result.rows[0];
    } catch (error) {
      logger.error('Get preferences error:', error.message);
      throw error;
    }
  }

  /**
   * Create default notification preferences
   * @param {string} salonId - Salon UUID
   * @returns {Promise<object>} Created preferences
   */
  async createDefaultPreferences(salonId) {
    try {
      const result = await db.query(
        `INSERT INTO notification_preferences (
          salon_id, hiring_updates, job_tips, profile_improvements, account_alerts, promotions
        ) VALUES ($1, true, true, true, true, false)
        RETURNING *`,
        [salonId]
      );

      return result.rows[0];
    } catch (error) {
      logger.error('Create default preferences error:', error.message);
      throw error;
    }
  }

  /**
   * Update notification preferences
   * @param {string} salonId - Salon UUID
   * @param {object} updates - Preference updates
   * @returns {Promise<object>} Updated preferences
   */
  async updatePreferences(salonId, updates) {
    try {
      // Ensure hiring_updates cannot be disabled
      if (updates.hiring_updates === false) {
        return { success: false, message: 'Hiring updates cannot be disabled' };
      }

      const allowedFields = [
        'job_tips',
        'profile_improvements',
        'account_alerts',
        'promotions',
      ];

      const validUpdates = {};
      for (const [key, value] of Object.entries(updates)) {
        if (allowedFields.includes(key) && typeof value === 'boolean') {
          validUpdates[key] = value;
        }
      }

      if (Object.keys(validUpdates).length === 0) {
        return { success: false, message: 'No valid updates provided' };
      }

      const setClause = Object.keys(validUpdates)
        .map((key, index) => `${key} = $${index + 2}`)
        .join(', ');

      const values = [salonId, ...Object.values(validUpdates)];

      const result = await db.query(
        `UPDATE notification_preferences 
         SET ${setClause}, updated_at = NOW()
         WHERE salon_id = $1
         RETURNING *`,
        values
      );

      if (result.rows.length === 0) {
        // Create if doesn't exist
        await this.createDefaultPreferences(salonId);
        return await this.updatePreferences(salonId, updates);
      }

      return { success: true, preferences: result.rows[0] };
    } catch (error) {
      logger.error('Update preferences error:', error.message);
      throw error;
    }
  }

  /**
   * Register push token for a salon
   * @param {string} salonId - Salon UUID
   * @param {string} deviceType - Device type (ios, android, web)
   * @param {string} pushToken - Push token
   * @returns {Promise<object>} Registered token
   */
  async registerPushToken(salonId, deviceType, pushToken) {
    try {
      // Deactivate old tokens for same device type
      await db.query(
        `UPDATE push_tokens 
         SET is_active = false 
         WHERE salon_id = $1 AND device_type = $2`,
        [salonId, deviceType]
      );

      // Insert new token
      const result = await db.query(
        `INSERT INTO push_tokens (salon_id, device_type, push_token, is_active)
         VALUES ($1, $2, $3, true)
         ON CONFLICT (salon_id, device_type) WHERE is_active = true
         DO UPDATE SET push_token = $3, updated_at = NOW()
         RETURNING *`,
        [salonId, deviceType, pushToken]
      );

      return { success: true, token: result.rows[0] };
    } catch (error) {
      logger.error('Register push token error:', error.message);
      throw error;
    }
  }

  /**
   * Track analytics event
   * @param {string} salonId - Salon UUID
   * @param {string} eventType - Event type
   * @param {string} notificationId - Optional notification ID
   * @param {object} metadata - Optional metadata
   * @returns {Promise<void>}
   */
  async trackEvent(salonId, eventType, notificationId = null, metadata = {}) {
    try {
      await db.query(
        `INSERT INTO analytics_events (salon_id, notification_id, event_type, metadata)
         VALUES ($1, $2, $3, $4)`,
        [salonId, notificationId, eventType, JSON.stringify(metadata)]
      );
    } catch (error) {
      logger.error('Track analytics event error:', error.message);
      // Don't throw - analytics failures shouldn't block operations
    }
  }

  /**
   * Get unread notification count
   * @param {string} salonId - Salon UUID
   * @returns {Promise<number>} Unread count
   */
  async getUnreadCount(salonId) {
    try {
      const result = await db.query(
        `SELECT COUNT(*) as count 
         FROM notifications 
         WHERE salon_id = $1 AND is_read = false`,
        [salonId]
      );

      return parseInt(result.rows[0].count) || 0;
    } catch (error) {
      logger.error('Get unread count error:', error.message);
      return 0;
    }
  }
}

export default new NotificationService();





