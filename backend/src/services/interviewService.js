import db from '../database/connection.js';
import logger from '../utils/logger.js';
import pushService from './pushService.js';

/**
 * Interview Service
 * Handles interview scheduling, rescheduling, and completion for salon owners.
 */
class InterviewService {
  static VALID_MODES = ['in_person', 'phone_call', 'video_call'];

  /**
   * Schedule an interview for a shortlisted candidate.
   * - Only allowed if application status = 'shortlisted'
   * - Transitions status to 'interview', interview_status to 'scheduled'
   * - Logs event in interview_events
   *
   * @param {string} applicationId
   * @param {string} salonId - from JWT
   * @param {object} data - { interviewAt, mode, notes }
   */
  async scheduleInterview(applicationId, salonId, { interviewAt, mode, notes }) {
    // Fetch application with ownership check
    const appResult = await db.query(
      `SELECT a.id, a.status, a.interview_status, a.job_id, a.seeker_id, j.salon_id
       FROM applications a
       JOIN jobs j ON a.job_id = j.id
       WHERE a.id = $1`,
      [applicationId]
    );

    if (appResult.rows.length === 0) {
      throw Object.assign(new Error('Application not found'), { statusCode: 404 });
    }

    const app = appResult.rows[0];

    if (app.salon_id !== salonId) {
      throw Object.assign(new Error('Access denied'), { statusCode: 403 });
    }

    if (app.status !== 'shortlisted') {
      throw Object.assign(
        new Error(`Cannot schedule interview: application status is '${app.status}'. Must be 'shortlisted'.`),
        { statusCode: 400 }
      );
    }

    // Prevent scheduling in the past
    const scheduledDate = new Date(interviewAt);
    if (scheduledDate <= new Date()) {
      throw Object.assign(
        new Error('Interview must be scheduled in the future'),
        { statusCode: 400 }
      );
    }

    // Update application: status → interview, interview fields
    const updateResult = await db.query(
      `UPDATE applications
       SET status = 'interview',
           interview_status = 'scheduled',
           interview_scheduled_at = $1,
           interview_mode = $2,
           interview_notes = $3,
           updated_at = CURRENT_TIMESTAMP
       WHERE id = $4
       RETURNING *`,
      [interviewAt, mode || null, notes || null, applicationId]
    );

    // Log in interview_events
    await db.query(
      `INSERT INTO interview_events (application_id, scheduled_by, scheduled_at, mode, notes, event_type)
       VALUES ($1, $2, $3, $4, $5, 'scheduled')`,
      [applicationId, salonId, interviewAt, mode || null, notes || null]
    );

    // Log in status audit trail
    await db.query(
      `INSERT INTO application_status_logs (application_id, old_status, new_status, changed_by)
       VALUES ($1, $2, $3, $4)`,
      [applicationId, 'shortlisted', 'interview', salonId]
    );

    logger.info(`Interview scheduled: app=${applicationId}, at=${interviewAt}, by salon=${salonId}`);

    pushService.sendNotification(app.seeker_id, 'seeker', {
      type: 'interview_scheduled',
      title: 'Interview scheduled',
      body: `Your interview has been scheduled. Check your applications for details.`,
      data: {
        deepLink: `app://seeker/applications/${applicationId}`,
        jobId: app.job_id,
        applicationId,
      },
    });

    const updated = updateResult.rows[0];
    return this._formatInterview(updated);
  }

  /**
   * Reschedule an existing interview.
   * - Only allowed if interview_status = 'scheduled'
   *
   * @param {string} applicationId
   * @param {string} salonId
   * @param {object} data - { interviewAt, mode, notes }
   */
  async rescheduleInterview(applicationId, salonId, { interviewAt, mode, notes }) {
    const appResult = await db.query(
      `SELECT a.id, a.status, a.interview_status, a.job_id, a.seeker_id, j.salon_id
       FROM applications a
       JOIN jobs j ON a.job_id = j.id
       WHERE a.id = $1`,
      [applicationId]
    );

    if (appResult.rows.length === 0) {
      throw Object.assign(new Error('Application not found'), { statusCode: 404 });
    }

    const app = appResult.rows[0];

    if (app.salon_id !== salonId) {
      throw Object.assign(new Error('Access denied'), { statusCode: 403 });
    }

    if (app.interview_status !== 'scheduled') {
      throw Object.assign(
        new Error(`Cannot reschedule: interview_status is '${app.interview_status}'. Must be 'scheduled'.`),
        { statusCode: 400 }
      );
    }

    const scheduledDate = new Date(interviewAt);
    if (scheduledDate <= new Date()) {
      throw Object.assign(
        new Error('Interview must be scheduled in the future'),
        { statusCode: 400 }
      );
    }

    const updateResult = await db.query(
      `UPDATE applications
       SET interview_scheduled_at = $1,
           interview_mode = COALESCE($2, interview_mode),
           interview_notes = COALESCE($3, interview_notes),
           updated_at = CURRENT_TIMESTAMP
       WHERE id = $4
       RETURNING *`,
      [interviewAt, mode || null, notes || null, applicationId]
    );

    await db.query(
      `INSERT INTO interview_events (application_id, scheduled_by, scheduled_at, mode, notes, event_type)
       VALUES ($1, $2, $3, $4, $5, 'rescheduled')`,
      [applicationId, salonId, interviewAt, mode || null, notes || null]
    );

    logger.info(`Interview rescheduled: app=${applicationId}, new_time=${interviewAt}`);

    pushService.sendNotification(app.seeker_id, 'seeker', {
      type: 'interview_rescheduled',
      title: 'Interview rescheduled',
      body: `Your interview has been rescheduled. Check your applications for the new time.`,
      data: {
        deepLink: `app://seeker/applications/${applicationId}`,
        jobId: app.job_id,
        applicationId,
      },
    });

    return this._formatInterview(updateResult.rows[0]);
  }

  /**
   * Mark interview as completed.
   * - Only if interview_status = 'scheduled'
   * - Keeps main status = 'interview'; owner must then hire or reject
   *
   * @param {string} applicationId
   * @param {string} salonId
   */
  async completeInterview(applicationId, salonId) {
    const appResult = await db.query(
      `SELECT a.id, a.status, a.interview_status, a.job_id, a.seeker_id, j.salon_id
       FROM applications a
       JOIN jobs j ON a.job_id = j.id
       WHERE a.id = $1`,
      [applicationId]
    );

    if (appResult.rows.length === 0) {
      throw Object.assign(new Error('Application not found'), { statusCode: 404 });
    }

    const app = appResult.rows[0];

    if (app.salon_id !== salonId) {
      throw Object.assign(new Error('Access denied'), { statusCode: 403 });
    }

    if (app.interview_status !== 'scheduled') {
      throw Object.assign(
        new Error(`Cannot complete: interview_status is '${app.interview_status}'.`),
        { statusCode: 400 }
      );
    }

    const updateResult = await db.query(
      `UPDATE applications
       SET interview_status = 'completed',
           updated_at = CURRENT_TIMESTAMP
       WHERE id = $1
       RETURNING *`,
      [applicationId]
    );

    await db.query(
      `INSERT INTO interview_events (application_id, scheduled_by, scheduled_at, mode, notes, event_type)
       VALUES ($1, $2, COALESCE($3, CURRENT_TIMESTAMP), NULL, NULL, 'completed')`,
      [applicationId, salonId, app.interview_scheduled_at || null]
    );

    logger.info(`Interview completed: app=${applicationId}`);

    // TODO: triggerNotification(app.seeker_id, 'interview_reminder') — prompt owner to hire/reject

    return this._formatInterview(updateResult.rows[0]);
  }

  /**
   * Get interview details for a specific application.
   * Used by both owner and seeker.
   *
   * @param {string} applicationId
   */
  async getInterviewDetails(applicationId) {
    const result = await db.query(
      `SELECT a.id, a.status, a.interview_status, a.interview_scheduled_at,
              a.interview_mode, a.interview_notes, a.job_id, a.seeker_id,
              j.job_role, j.custom_role_name, j.location,
              s.salon_name
       FROM applications a
       JOIN jobs j ON a.job_id = j.id
       LEFT JOIN salons s ON j.salon_id = s.id
       WHERE a.id = $1`,
      [applicationId]
    );

    if (result.rows.length === 0) {
      throw Object.assign(new Error('Application not found'), { statusCode: 404 });
    }

    const row = result.rows[0];
    return {
      applicationId: row.id,
      status: row.status,
      interviewStatus: row.interview_status,
      interviewScheduledAt: row.interview_scheduled_at,
      interviewMode: row.interview_mode,
      interviewNotes: row.interview_notes,
      job: {
        id: row.job_id,
        jobRole: row.job_role,
        customRoleName: row.custom_role_name,
        location: row.location,
        salonName: row.salon_name,
      },
    };
  }

  /**
   * Format interview data from DB row
   */
  _formatInterview(row) {
    return {
      applicationId: row.id,
      status: row.status,
      interviewStatus: row.interview_status,
      interviewScheduledAt: row.interview_scheduled_at,
      interviewMode: row.interview_mode,
      interviewNotes: row.interview_notes,
      updatedAt: row.updated_at,
    };
  }
}

// TODO: Scaffold for cron job / background checker
// If interview_scheduled_at < NOW() AND interview_status = 'scheduled'
// → Send reminder to owner: "Interview completed? Update status."
// This should be a separate scheduler service, not part of the request cycle.

export default new InterviewService();
