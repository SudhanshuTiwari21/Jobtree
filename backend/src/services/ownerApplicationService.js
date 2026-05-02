import db from '../database/connection.js';
import logger from '../utils/logger.js';
import pushService from './pushService.js';

/**
 * Owner Application Service
 * Handles candidate management for salon owners.
 * Owners can view and manage applications for their own jobs only.
 */
class OwnerApplicationService {
  /**
   * Valid status values
   */
  static VALID_STATUSES = ['applied', 'shortlisted', 'interview', 'rejected', 'hired'];

  /**
   * Allowed status transitions.
   * Key = current status, Value = array of statuses it can move to.
   */
  static STATUS_TRANSITIONS = {
    applied: ['shortlisted', 'rejected'],
    shortlisted: ['interview', 'rejected'],
    interview: ['hired', 'rejected'],
    rejected: [],   // terminal state
    hired: [],      // terminal state
  };

  /**
   * Verify that a job belongs to the given salon
   * @param {string} jobId
   * @param {string} salonId
   * @returns {object|null} job row or null
   */
  async verifyJobOwnership(jobId, salonId) {
    const result = await db.query(
      'SELECT id, job_role, custom_role_name, location, salon_id, vacancy_count, number_of_staff FROM jobs WHERE id = $1',
      [jobId]
    );

    if (result.rows.length === 0) {
      return null;
    }

    const job = result.rows[0];
    if (job.salon_id !== salonId) {
      return null; // ownership mismatch
    }

    return job;
  }

  /**
   * Get the current hired count for a job
   * @param {string} jobId
   * @returns {number}
   */
  async getHiredCount(jobId) {
    const result = await db.query(
      "SELECT COUNT(*) FROM applications WHERE job_id = $1 AND status = 'hired'",
      [jobId]
    );
    return parseInt(result.rows[0].count);
  }

  /**
   * Log a status change in the audit trail
   * @param {string} applicationId
   * @param {string} oldStatus
   * @param {string} newStatus
   * @param {string} changedBy - salon_id of the owner making the change
   */
  async logStatusChange(applicationId, oldStatus, newStatus, changedBy) {
    try {
      await db.query(
        `INSERT INTO application_status_logs (application_id, old_status, new_status, changed_by)
         VALUES ($1, $2, $3, $4)`,
        [applicationId, oldStatus, newStatus, changedBy]
      );
    } catch (error) {
      // Non-critical: don't fail the status update if audit log fails
      logger.error(`Failed to log status change for application ${applicationId}:`, error.message);
    }
  }

  /**
   * Get all candidates (applications) for a specific job.
   * Includes seeker profile details. Sorted by latest first.
   *
   * @param {string} jobId
   * @param {string} salonId - from JWT, for ownership check
   * @param {object} options - { status, limit, offset }
   */
  async getCandidatesForJob(jobId, salonId, { status, limit = 20, offset = 0 } = {}) {
    // Verify ownership
    const job = await this.verifyJobOwnership(jobId, salonId);
    if (!job) {
      throw Object.assign(new Error('Job not found or access denied'), { statusCode: 404 });
    }

    // Build query with optional status filter (includes interview fields)
    let query = `
      SELECT 
        a.id AS application_id,
        a.status,
        a.created_at,
        a.updated_at,
        a.interview_status,
        a.interview_scheduled_at,
        a.interview_mode,
        a.interview_notes,
        sp.id AS seeker_id,
        sp.full_name,
        sp.city,
        sp.experience,
        sp.expected_salary,
        sp.profile_completion_percent,
        sp.profile_photo_url,
        sp.gender,
        sp.preferred_role,
        sp.phone_number
      FROM applications a
      JOIN seeker_profiles sp ON a.seeker_id = sp.id
      WHERE a.job_id = $1
    `;
    const params = [jobId];
    let paramIndex = 2;

    if (status && OwnerApplicationService.VALID_STATUSES.includes(status)) {
      query += ` AND a.status = $${paramIndex}`;
      params.push(status);
      paramIndex++;
    }

    query += ` ORDER BY a.created_at DESC LIMIT $${paramIndex} OFFSET $${paramIndex + 1}`;
    params.push(limit, offset);

    const result = await db.query(query, params);

    // Get total count (respecting filter)
    let countQuery = 'SELECT COUNT(*) FROM applications WHERE job_id = $1';
    const countParams = [jobId];
    if (status && OwnerApplicationService.VALID_STATUSES.includes(status)) {
      countQuery += ' AND status = $2';
      countParams.push(status);
    }
    const countResult = await db.query(countQuery, countParams);

    // Get status-wise breakdown
    const breakdownResult = await db.query(
      `SELECT status, COUNT(*) as count 
       FROM applications 
       WHERE job_id = $1 
       GROUP BY status`,
      [jobId]
    );
    const statusBreakdown = {};
    breakdownResult.rows.forEach((row) => {
      statusBreakdown[row.status] = parseInt(row.count);
    });

    // Vacancy info
    const vacancyCount = job.vacancy_count || job.number_of_staff || 1;
    const hiredCount = statusBreakdown['hired'] || 0;
    const vacancyFull = hiredCount >= vacancyCount;

    const applications = result.rows.map((row) => ({
      applicationId: row.application_id,
      status: row.status,
      appliedAt: row.created_at,
      updatedAt: row.updated_at,
      interviewStatus: row.interview_status || 'not_scheduled',
      interviewScheduledAt: row.interview_scheduled_at,
      interviewMode: row.interview_mode,
      interviewNotes: row.interview_notes,
      seeker: {
        id: row.seeker_id,
        fullName: row.full_name || 'Unknown',
        city: row.city || '',
        experience: row.experience || '',
        expectedSalary: row.expected_salary ? parseFloat(row.expected_salary) : null,
        profileCompletion: row.profile_completion_percent || 0,
        profilePhoto: row.profile_photo_url || '',
        gender: row.gender || '',
        preferredRole: row.preferred_role || '',
        phoneNumber: row.phone_number || '',
      },
    }));

    return {
      job: {
        id: job.id,
        jobRole: job.job_role,
        customRoleName: job.custom_role_name,
        location: job.location,
        vacancyCount,
        hiredCount,
        vacancyFull,
      },
      applications,
      total: parseInt(countResult.rows[0].count),
      statusBreakdown,
    };
  }

  /**
   * Update the status of an application.
   * Validates ownership, allowed transitions, and vacancy limits.
   * Logs the change to the audit trail.
   *
   * @param {string} applicationId
   * @param {string} newStatus
   * @param {string} salonId - from JWT
   */
  async updateApplicationStatus(applicationId, newStatus, salonId) {
    // Validate status value
    if (!OwnerApplicationService.VALID_STATUSES.includes(newStatus)) {
      throw Object.assign(
        new Error(`Invalid status: ${newStatus}. Must be one of: ${OwnerApplicationService.VALID_STATUSES.join(', ')}`),
        { statusCode: 400 }
      );
    }

    // Fetch current application with job ownership check + interview fields
    const appResult = await db.query(
      `SELECT a.id, a.status, a.interview_status, a.job_id, a.seeker_id, 
              j.salon_id, j.vacancy_count, j.number_of_staff
       FROM applications a
       JOIN jobs j ON a.job_id = j.id
       WHERE a.id = $1`,
      [applicationId]
    );

    if (appResult.rows.length === 0) {
      throw Object.assign(new Error('Application not found'), { statusCode: 404 });
    }

    const application = appResult.rows[0];

    // Check ownership
    if (application.salon_id !== salonId) {
      throw Object.assign(new Error('Access denied'), { statusCode: 403 });
    }

    const currentStatus = application.status;

    // Check transition rules
    const allowedTransitions = OwnerApplicationService.STATUS_TRANSITIONS[currentStatus] || [];
    if (!allowedTransitions.includes(newStatus)) {
      throw Object.assign(
        new Error(`Cannot transition from '${currentStatus}' to '${newStatus}'. Allowed: ${allowedTransitions.join(', ') || 'none (terminal state)'}`),
        { statusCode: 400 }
      );
    }

    // ── Interview completion enforcement ──
    // Cannot hire if interview was scheduled but not completed
    if (newStatus === 'hired' && application.interview_status === 'scheduled') {
      throw Object.assign(
        new Error('Cannot hire: interview is scheduled but not yet completed. Mark interview as completed first.'),
        { statusCode: 400, code: 'INTERVIEW_NOT_COMPLETED' }
      );
    }

    // ── Over-hiring prevention ──
    if (newStatus === 'hired') {
      const vacancyCount = application.vacancy_count || application.number_of_staff || 1;
      const hiredCount = await this.getHiredCount(application.job_id);

      if (hiredCount >= vacancyCount) {
        throw Object.assign(
          new Error(`Vacancy limit reached. This job has ${vacancyCount} position(s) and all are filled.`),
          { statusCode: 400, code: 'VACANCY_FULL' }
        );
      }
    }

    // ── Audit trail: log BEFORE the update ──
    await this.logStatusChange(applicationId, currentStatus, newStatus, salonId);

    // Perform update
    const updateResult = await db.query(
      `UPDATE applications 
       SET status = $1, updated_at = CURRENT_TIMESTAMP 
       WHERE id = $2 
       RETURNING *`,
      [newStatus, applicationId]
    );

    const updated = updateResult.rows[0];

    logger.info(`Application ${applicationId} status changed: ${currentStatus} → ${newStatus} by salon ${salonId}`);

    // ── Status-based notification triggers (scaffolded) ──
    this._triggerStatusNotification(applicationId, newStatus, application.seeker_id, application.job_id, salonId);

    // Return vacancy info alongside the updated application
    const vacancyCount = application.vacancy_count || application.number_of_staff || 1;
    const newHiredCount = newStatus === 'hired'
      ? (await this.getHiredCount(application.job_id))
      : null;

    return {
      applicationId: updated.id,
      jobId: updated.job_id,
      seekerId: updated.seeker_id,
      status: updated.status,
      previousStatus: currentStatus,
      updatedAt: updated.updated_at,
      createdAt: updated.created_at,
      vacancyCount,
      hiredCount: newHiredCount,
      vacancyFull: newHiredCount !== null ? newHiredCount >= vacancyCount : undefined,
    };
  }

  /**
   * Status-based push notification triggers (non-blocking).
   * Fetches job/salon details for message text, then sends via pushService.
   */
  async _triggerStatusNotification(applicationId, newStatus, seekerId, jobId, salonId) {
    try {
      const jobResult = await db.query(
        `SELECT j.job_role, j.custom_role_name, s.salon_name
         FROM jobs j
         LEFT JOIN salons s ON j.salon_id = s.id
         WHERE j.id = $1`,
        [jobId]
      );
      const jobRole = jobResult.rows[0]
        ? (jobResult.rows[0].custom_role_name || jobResult.rows[0].job_role || 'Job')
        : 'Job';
      const salonName = jobResult.rows[0]?.salon_name || 'Salon';

      const deepLink = `app://seeker/applications`;
      const data = { deepLink, jobId, applicationId: String(applicationId) };

      switch (newStatus) {
        case 'shortlisted':
          pushService.sendNotification(seekerId, 'seeker', {
            type: 'shortlisted',
            title: "You've been shortlisted!",
            body: `You've been shortlisted for ${jobRole} at ${salonName}.`,
            data,
          });
          break;
        case 'interview':
          pushService.sendNotification(seekerId, 'seeker', {
            type: 'interview',
            title: 'Interview stage',
            body: `You've been moved to interview for ${jobRole} at ${salonName}.`,
            data,
          });
          break;
        case 'hired':
          pushService.sendNotification(seekerId, 'seeker', {
            type: 'hired',
            title: "Congratulations! You're hired",
            body: `You've been hired for ${jobRole} at ${salonName}.`,
            data,
          });
          break;
        case 'rejected':
          pushService.sendNotification(seekerId, 'seeker', {
            type: 'rejected',
            title: 'Update on your application',
            body: `Update on your application for ${jobRole} at ${salonName}.`,
            data,
          });
          break;
        default:
          break;
      }
    } catch (error) {
      logger.error(`Notification trigger error for application ${applicationId}:`, error.message);
    }
  }
}

export default new OwnerApplicationService();
