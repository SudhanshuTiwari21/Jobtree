import admin from 'firebase-admin';
import db from '../database/connection.js';
import config from '../config/index.js';
import logger from '../utils/logger.js';

/**
 * Push Notification Service (FCM + APNS via FCM)
 * Production-grade: throttling, retry, token deactivation, logging.
 * Do NOT block request flow; all send operations are fire-and-forget.
 */
let firebaseInitialized = false;

function initFirebase() {
  if (firebaseInitialized) return;

  try {
    if (admin.apps.length > 0) {
      firebaseInitialized = true;
      return;
    }

    const { serviceAccountPath, serviceAccountJson } = config.firebase || {};

    if (serviceAccountJson) {
      let credentials;
      try {
        const decoded = Buffer.from(serviceAccountJson, 'base64').toString('utf8');
        credentials = JSON.parse(decoded);
      } catch {
        credentials = typeof serviceAccountJson === 'string' ? JSON.parse(serviceAccountJson) : serviceAccountJson;
      }
      admin.initializeApp({ credential: admin.credential.cert(credentials) });
      firebaseInitialized = true;
      logger.info('Firebase Admin initialized from FIREBASE_SERVICE_ACCOUNT_JSON');
      return;
    }

    if (serviceAccountPath) {
      admin.initializeApp({ credential: admin.credential.cert(serviceAccountPath) });
      firebaseInitialized = true;
      logger.info('Firebase Admin initialized from GOOGLE_APPLICATION_CREDENTIALS');
      return;
    }

    logger.warn('Firebase not configured. Push notifications will be no-op. Set GOOGLE_APPLICATION_CREDENTIALS or FIREBASE_SERVICE_ACCOUNT_JSON.');
  } catch (error) {
    logger.error('Firebase init error:', error.message);
  }
}

initFirebase();

/** Max notifications per user per minute (anti-spam) */
const MAX_PER_USER_PER_MINUTE = 3;
/** Min seconds between same notification type (anti-duplicate) */
const MIN_SECONDS_SAME_TYPE = 10;

/**
 * Check if we should send (throttle + duplicate prevention)
 * @param {string} userId
 * @param {string} userType
 * @param {string} type
 * @returns {Promise<boolean>}
 */
async function shouldSendNotification(userId, userType, type) {
  try {
    const oneMinuteAgo = new Date(Date.now() - 60 * 1000);
    const tenSecondsAgo = new Date(Date.now() - MIN_SECONDS_SAME_TYPE * 1000);

    const countResult = await db.query(
      `SELECT COUNT(*) FROM push_notification_log
       WHERE user_id = $1 AND user_type = $2 AND created_at > $3`,
      [userId, userType, oneMinuteAgo]
    );
    const countPerMinute = parseInt(countResult.rows[0].count);
    if (countPerMinute >= MAX_PER_USER_PER_MINUTE) {
      logger.info(`Push throttle: user ${userId} (${userType}) exceeded ${MAX_PER_USER_PER_MINUTE}/min`);
      return false;
    }

    const duplicateResult = await db.query(
      `SELECT 1 FROM push_notification_log
       WHERE user_id = $1 AND user_type = $2 AND type = $3 AND created_at > $4
       LIMIT 1`,
      [userId, userType, type, tenSecondsAgo]
    );
    if (duplicateResult.rows.length > 0) {
      logger.info(`Push duplicate skipped: same type ${type} within ${MIN_SECONDS_SAME_TYPE}s`);
      return false;
    }

    return true;
  } catch (error) {
    logger.error('shouldSendNotification check error:', error.message);
    return true;
  }
}

/**
 * Get active FCM tokens for a user
 * @param {string} userId
 * @param {string} userType - 'owner' | 'seeker'
 * @returns {Promise<string[]>}
 */
async function getActiveTokens(userId, userType) {
  const result = await db.query(
    `SELECT fcm_token FROM user_devices
     WHERE user_id = $1 AND user_type = $2 AND is_active = true`,
    [userId, userType]
  );
  return result.rows.map((r) => r.fcm_token).filter(Boolean);
}

/**
 * Deactivate a token (e.g. invalid or unregistered)
 * @param {string} fcmToken
 */
async function deactivateToken(fcmToken) {
  try {
    await db.query(
      `UPDATE user_devices SET is_active = false, updated_at = CURRENT_TIMESTAMP WHERE fcm_token = $1`,
      [fcmToken]
    );
    logger.info('Deactivated invalid FCM token');
  } catch (error) {
    logger.error('Deactivate token error:', error.message);
  }
}

/**
 * Log notification to DB (always, before send)
 * @param {string} userId
 * @param {string} userType
 * @param {object} payload
 * @returns {Promise<string|null>} log id
 */
async function logNotification(userId, userType, payload) {
  const { type, title, body, data = {} } = payload;
  const result = await db.query(
    `INSERT INTO push_notification_log (user_id, user_type, type, title, body, data)
     VALUES ($1, $2, $3, $4, $5, $6)
     RETURNING id`,
    [userId, userType, type, title, body, JSON.stringify(data)]
  );
  return result.rows[0]?.id || null;
}

/**
 * Mark log entry as sent
 * @param {string} logId
 */
async function markLogSent(logId) {
  try {
    await db.query(
      `UPDATE push_notification_log SET sent_at = CURRENT_TIMESTAMP WHERE id = $1`,
      [logId]
    );
  } catch (error) {
    logger.error('markLogSent error:', error.message);
  }
}

/**
 * Send push notification to a user (owner or seeker).
 * Non-blocking: run in background, never throw into caller.
 *
 * @param {string} userId - salon_id (owner) or seeker_id (seeker)
 * @param {string} userType - 'owner' | 'seeker'
 * @param {object} payload
 * @param {string} payload.type - e.g. new_application, shortlisted, interview_scheduled
 * @param {string} payload.title
 * @param {string} payload.body
 * @param {object} [payload.data] - { deepLink, jobId, applicationId, ... }
 */
async function sendNotification(userId, userType, payload) {
  const { type, title, body, data = {} } = payload;

  setImmediate(async () => {
    try {
      const allowed = await shouldSendNotification(userId, userType, type);
      if (!allowed) return;

      const logId = await logNotification(userId, userType, payload);

      const tokens = await getActiveTokens(userId, userType);
      if (tokens.length === 0) {
        logger.info(`No active FCM tokens for user ${userId} (${userType})`);
        return;
      }

      if (!firebaseInitialized || !admin.apps.length) {
        logger.info(`Push skipped (FCM not configured): ${type} to ${userId}`);
        return;
      }

      const message = {
        notification: { title, body },
        data: {
          type: type || '',
          deepLink: (data.deepLink || '').toString(),
          ...Object.fromEntries(
            Object.entries(data).filter(([k, v]) => k !== 'deepLink' && v != null).map(([k, v]) => [k, String(v)])
          ),
        },
        tokens,
        android: { priority: 'high' },
        apns: {
          payload: { aps: { sound: 'default', badge: 1 } },
          fcmOptions: {},
        },
      };

      let response;
      try {
        response = await admin.messaging().sendEachForMulticast(message);
      } catch (firstErr) {
        logger.warn(`Push first attempt failed for ${userId} (${type}), retrying once:`, firstErr.message);
        response = await admin.messaging().sendEachForMulticast(message);
      }

      if (response.failureCount > 0) {
        response.responses.forEach((resp, idx) => {
          if (!resp.success) {
            const token = tokens[idx];
            const err = resp.error;
            if (err?.code === 'messaging/invalid-registration-token' || err?.code === 'messaging/registration-token-not-registered') {
              deactivateToken(token).catch(() => {});
            } else {
              logger.warn(`FCM send failed for token: ${err?.message}`);
            }
          }
        });
      }

      await markLogSent(logId);
      logger.info(`Push sent: ${type} to ${userId} (${response.successCount}/${tokens.length})`);
    } catch (error) {
      logger.error(`Push send error for ${userId} (${type}):`, error.message);
    }
  });
}

/**
 * Register device token (called by API after auth).
 * Partial unique index on (fcm_token) WHERE is_active = true: we deactivate any existing row for this token then insert.
 */
async function registerDevice(userId, userType, fcmToken, platform) {
  if (!fcmToken || !platform) {
    throw Object.assign(new Error('fcmToken and platform required'), { statusCode: 400 });
  }
  if (!['android', 'ios'].includes(platform)) {
    throw Object.assign(new Error('platform must be android or ios'), { statusCode: 400 });
  }
  if (!['owner', 'seeker'].includes(userType)) {
    throw Object.assign(new Error('userType must be owner or seeker'), { statusCode: 400 });
  }

  await db.query(
    `UPDATE user_devices SET is_active = false, updated_at = CURRENT_TIMESTAMP WHERE fcm_token = $1`,
    [fcmToken]
  );
  await db.query(
    `INSERT INTO user_devices (user_id, user_type, fcm_token, platform, is_active)
     VALUES ($1, $2, $3, $4, true)`,
    [userId, userType, fcmToken, platform]
  );
  return { success: true };
}

/**
 * Unregister / deactivate token (e.g. on logout)
 */
async function unregisterDevice(userId, userType, fcmToken) {
  await db.query(
    `UPDATE user_devices SET is_active = false, updated_at = CURRENT_TIMESTAMP
     WHERE user_id = $1 AND user_type = $2 AND fcm_token = $3`,
    [userId, userType, fcmToken]
  );
  return { success: true };
}

/**
 * Deactivate all device tokens for a user (e.g. logout all devices)
 */
async function deactivateAllDevicesForUser(userId, userType) {
  await db.query(
    `UPDATE user_devices SET is_active = false, updated_at = CURRENT_TIMESTAMP
     WHERE user_id = $1 AND user_type = $2`,
    [userId, userType]
  );
  return { success: true };
}

/**
 * Get notification list for a user (in-app center)
 * @param {string} userId
 * @param {string} userType
 * @param {object} options - { limit, offset, unreadOnly }
 */
async function getNotifications(userId, userType, options = {}) {
  const { limit = 50, offset = 0, unreadOnly = false } = options;

  let query = `SELECT id, type, title, body, data, is_read, sent_at, created_at
               FROM push_notification_log
               WHERE user_id = $1 AND user_type = $2`;
  const params = [userId, userType];
  if (unreadOnly) {
    query += ` AND is_read = false`;
  }
  query += ` ORDER BY created_at DESC LIMIT $3 OFFSET $4`;
  params.push(limit, offset);

  const result = await db.query(query, params);
  const countResult = await db.query(
    `SELECT COUNT(*) FROM push_notification_log WHERE user_id = $1 AND user_type = $2${unreadOnly ? ' AND is_read = false' : ''}`,
    [userId, userType]
  );

  return {
    notifications: result.rows,
    total: parseInt(countResult.rows[0].count),
    limit,
    offset,
  };
}

/**
 * Mark notification as read
 */
async function markAsRead(notificationId, userId, userType) {
  const result = await db.query(
    `UPDATE push_notification_log SET is_read = true
     WHERE id = $1 AND user_id = $2 AND user_type = $3
     RETURNING id`,
    [notificationId, userId, userType]
  );
  return result.rows.length > 0 ? { success: true } : { success: false };
}

/**
 * Get unread notification count for in-app badge
 */
async function getUnreadCount(userId, userType) {
  const result = await db.query(
    `SELECT COUNT(*) FROM push_notification_log
     WHERE user_id = $1 AND user_type = $2 AND is_read = false`,
    [userId, userType]
  );
  return parseInt(result.rows[0].count, 10);
}

/**
 * Mark all notifications as read for a user
 */
async function markAllAsRead(userId, userType) {
  await db.query(
    `UPDATE push_notification_log SET is_read = true
     WHERE user_id = $1 AND user_type = $2`,
    [userId, userType]
  );
  return { success: true };
}

export default {
  sendNotification,
  registerDevice,
  unregisterDevice,
  deactivateAllDevicesForUser,
  getNotifications,
  markAsRead,
  markAllAsRead,
  getUnreadCount,
  shouldSendNotification,
  getActiveTokens,
};
export { sendNotification, registerDevice, unregisterDevice, getNotifications, markAsRead, getUnreadCount };
