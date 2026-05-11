import db from '../database/connection.js';
import logger from '../utils/logger.js';

const MAX_BODY = 2000;

class ChatService {
  async getApplicationRow(applicationId) {
    const r = await db.query(
      `SELECT a.id, a.job_id, a.seeker_id, a.status, j.salon_id
       FROM applications a
       INNER JOIN jobs j ON j.id = a.job_id
       WHERE a.id = $1`,
      [applicationId]
    );
    return r.rows[0] || null;
  }

  /**
   * @param {'owner'|'seeker'} userType
   * @param {string} userId — salon id (owner) or seeker id
   * @returns {{ role: 'owner'|'seeker', row: object }}
   */
  async assertParticipant(applicationId, userType, userId) {
    const row = await this.getApplicationRow(applicationId);
    if (!row) {
      const err = new Error('Application not found');
      err.statusCode = 404;
      throw err;
    }
    if (userType === 'owner' && row.salon_id === userId) {
      return { role: 'owner', row };
    }
    if (userType === 'seeker' && row.seeker_id === userId) {
      return { role: 'seeker', row };
    }
    const err = new Error('Not allowed to access this chat');
    err.statusCode = 403;
    throw err;
  }

  async listMessages(applicationId, { limit = 50, before = null } = {}) {
    const lim = Math.min(Math.max(parseInt(limit, 10) || 50, 1), 100);
    const params = [applicationId, lim];
    let beforeClause = '';
    if (before) {
      beforeClause = 'AND created_at < $3';
      params.push(before);
    }
    const r = await db.query(
      `SELECT id, application_id, sender_role, body, created_at
       FROM chat_messages
       WHERE application_id = $1 ${beforeClause}
       ORDER BY created_at DESC
       LIMIT $2`,
      params
    );
    return r.rows.map((m) => ({
      id: m.id,
      applicationId: m.application_id,
      senderRole: m.sender_role,
      body: m.body,
      createdAt: m.created_at,
    })).reverse();
  }

  async insertMessage(applicationId, senderRole, body) {
    const text = String(body || '').trim();
    if (!text) {
      const err = new Error('Message body required');
      err.statusCode = 400;
      throw err;
    }
    const safe = text.slice(0, MAX_BODY);
    const r = await db.query(
      `INSERT INTO chat_messages (application_id, sender_role, body)
       VALUES ($1, $2, $3)
       RETURNING id, application_id, sender_role, body, created_at`,
      [applicationId, senderRole, safe]
    );
    const m = r.rows[0];
    logger.info(`Chat message ${m.id} on application ${applicationId} (${senderRole})`);
    return {
      id: m.id,
      applicationId: m.application_id,
      senderRole: m.sender_role,
      body: m.body,
      createdAt: m.created_at,
    };
  }

  async listThreadsForSalon(salonId) {
    const r = await db.query(
      `SELECT
         a.id AS "applicationId",
         a.status,
         j.id AS "jobId",
         j.job_role AS "jobRole",
         j.custom_role_name AS "customRoleName",
         j.location,
         sp.full_name AS "seekerName",
         (SELECT m.body FROM chat_messages m WHERE m.application_id = a.id ORDER BY m.created_at DESC LIMIT 1) AS "lastBody",
         (SELECT m.created_at FROM chat_messages m WHERE m.application_id = a.id ORDER BY m.created_at DESC LIMIT 1) AS "lastMessageAt"
       FROM applications a
       INNER JOIN jobs j ON j.id = a.job_id
       INNER JOIN seeker_profiles sp ON sp.id = a.seeker_id
       WHERE j.salon_id = $1
       ORDER BY COALESCE(
         (SELECT MAX(created_at) FROM chat_messages m WHERE m.application_id = a.id),
         a.created_at
       ) DESC`,
      [salonId]
    );
    return r.rows;
  }

  async listThreadsForSeeker(seekerId) {
    const r = await db.query(
      `SELECT
         a.id AS "applicationId",
         a.status,
         j.id AS "jobId",
         j.job_role AS "jobRole",
         j.custom_role_name AS "customRoleName",
         j.location,
         s.salon_name AS "salonName",
         (SELECT m.body FROM chat_messages m WHERE m.application_id = a.id ORDER BY m.created_at DESC LIMIT 1) AS "lastBody",
         (SELECT m.created_at FROM chat_messages m WHERE m.application_id = a.id ORDER BY m.created_at DESC LIMIT 1) AS "lastMessageAt"
       FROM applications a
       INNER JOIN jobs j ON j.id = a.job_id
       LEFT JOIN salons s ON s.id = j.salon_id
       WHERE a.seeker_id = $1
       ORDER BY COALESCE(
         (SELECT MAX(created_at) FROM chat_messages m WHERE m.application_id = a.id),
         a.created_at
       ) DESC`,
      [seekerId]
    );
    return r.rows;
  }
}

export default new ChatService();
