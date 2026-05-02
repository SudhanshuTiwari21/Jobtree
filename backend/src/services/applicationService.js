import db from '../database/connection.js';
import logger from '../utils/logger.js';
import pushService from './pushService.js';

class ApplicationService {
  /**
   * Apply to a job
   * - Prevents duplicate applications
   * - Increments applications_count on the job
   */
  async apply(seekerId, jobId) {
    // Check if job exists and is active
    const jobResult = await db.query(
      "SELECT * FROM jobs WHERE id = $1 AND status = 'active'",
      [jobId]
    );
    if (jobResult.rows.length === 0) {
      throw Object.assign(new Error('Job not found or no longer active'), { statusCode: 404 });
    }

    // Check seeker profile minimum completeness (must have name + city at least)
    const seekerResult = await db.query(
      'SELECT full_name, city, profile_completion_percent FROM seeker_profiles WHERE id = $1',
      [seekerId]
    );
    if (seekerResult.rows.length === 0) {
      throw Object.assign(new Error('Seeker profile not found'), { statusCode: 404 });
    }
    const seeker = seekerResult.rows[0];
    if (!seeker.full_name || !seeker.city) {
      throw Object.assign(
        new Error('Please complete your profile (name and city required) before applying'),
        { statusCode: 400, code: 'PROFILE_INCOMPLETE' }
      );
    }

    // Check for duplicate
    const existingResult = await db.query(
      'SELECT id FROM applications WHERE job_id = $1 AND seeker_id = $2',
      [jobId, seekerId]
    );
    if (existingResult.rows.length > 0) {
      throw Object.assign(new Error('You have already applied to this job'), { statusCode: 409 });
    }

    // Insert application
    const result = await db.query(
      `INSERT INTO applications (job_id, seeker_id, status)
       VALUES ($1, $2, 'applied')
       RETURNING *`,
      [jobId, seekerId]
    );

    // Increment applications_count on the job
    await db.query(
      'UPDATE jobs SET applications_count = applications_count + 1 WHERE id = $1',
      [jobId]
    );

    logger.info(`Seeker ${seekerId} applied to job ${jobId}`);

    const job = jobResult.rows[0];
    const applicationId = result.rows[0].id;
    pushService.sendNotification(job.salon_id, 'owner', {
      type: 'new_application',
      title: 'New application',
      body: 'A candidate applied to your job.',
      data: {
        deepLink: `app://owner/job/${jobId}`,
        jobId,
        applicationId: String(applicationId),
      },
    });

    return this._formatApplication(result.rows[0]);
  }

  /**
   * Get applications by seeker (with job details)
   */
  async getBySeeker(seekerId, { limit = 20, offset = 0 } = {}) {
    const result = await db.query(
      `SELECT a.*, j.job_role, j.custom_role_name, j.location, j.salary_min, j.salary_max,
              j.work_type, j.experience, j.status as job_status,
              s.salon_name
       FROM applications a
       JOIN jobs j ON a.job_id = j.id
       LEFT JOIN salons s ON j.salon_id = s.id
       WHERE a.seeker_id = $1
       ORDER BY a.created_at DESC
       LIMIT $2 OFFSET $3`,
      [seekerId, limit, offset]
    );

    const countResult = await db.query(
      'SELECT COUNT(*) FROM applications WHERE seeker_id = $1',
      [seekerId]
    );

    return {
      applications: result.rows.map((row) => ({
        id: row.id,
        jobId: row.job_id,
        seekerId: row.seeker_id,
        status: row.status,
        createdAt: row.created_at,
        interviewStatus: row.interview_status || 'not_scheduled',
        interviewScheduledAt: row.interview_scheduled_at,
        interviewMode: row.interview_mode,
        interviewNotes: row.interview_notes,
        job: {
          jobRole: row.job_role,
          customRoleName: row.custom_role_name,
          location: row.location,
          salaryMin: parseFloat(row.salary_min),
          salaryMax: parseFloat(row.salary_max),
          workType: row.work_type,
          experience: row.experience,
          jobStatus: row.job_status,
          salonName: row.salon_name,
        },
      })),
      total: parseInt(countResult.rows[0].count),
    };
  }

  /**
   * Get applications by job (for salon owner)
   */
  async getByJob(jobId, { limit = 50, offset = 0 } = {}) {
    const result = await db.query(
      `SELECT a.*, sp.full_name, sp.phone_number, sp.gender, sp.city,
              sp.preferred_role, sp.experience, sp.profile_photo_url
       FROM applications a
       JOIN seeker_profiles sp ON a.seeker_id = sp.id
       WHERE a.job_id = $1
       ORDER BY a.created_at DESC
       LIMIT $2 OFFSET $3`,
      [jobId, limit, offset]
    );

    return {
      applications: result.rows.map((row) => ({
        id: row.id,
        jobId: row.job_id,
        seekerId: row.seeker_id,
        status: row.status,
        createdAt: row.created_at,
        seeker: {
          fullName: row.full_name,
          phoneNumber: row.phone_number,
          gender: row.gender,
          city: row.city,
          preferredRole: row.preferred_role,
          experience: row.experience,
          profilePhotoUrl: row.profile_photo_url,
        },
      })),
    };
  }

  /**
   * Check if seeker has applied to a specific job
   */
  async hasApplied(seekerId, jobId) {
    const result = await db.query(
      'SELECT id FROM applications WHERE job_id = $1 AND seeker_id = $2',
      [jobId, seekerId]
    );
    return result.rows.length > 0;
  }

  /**
   * Get applied job IDs for a seeker (for badge display in feed)
   */
  async getAppliedJobIds(seekerId) {
    const result = await db.query(
      'SELECT job_id FROM applications WHERE seeker_id = $1',
      [seekerId]
    );
    return result.rows.map((r) => r.job_id);
  }

  /**
   * Format a single application row
   */
  _formatApplication(row) {
    return {
      id: row.id,
      jobId: row.job_id,
      seekerId: row.seeker_id,
      status: row.status,
      createdAt: row.created_at,
    };
  }
}

export default new ApplicationService();
