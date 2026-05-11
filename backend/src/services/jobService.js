import db from '../database/connection.js';
import logger from '../utils/logger.js';
import s3Service from './s3Service.js';

/**
 * Job Service
 * Handles all job-related business logic
 */
class JobService {
  /**
   * Create a new job posting
   */
  async createJob(salonId, jobData) {
    const {
      jobRole,
      otherCategory,
      customRoleName,
      skills = [],
      location,
      numberOfStaff = 1,
      salaryMin,
      salaryMax,
      workType,
      experience,
      accommodation,
      preferredGender,
    } = jobData;

    try {
      const result = await db.query(
        `INSERT INTO jobs (
          salon_id, job_role, other_category, custom_role_name, skills,
          location, number_of_staff, salary_min, salary_max,
          work_type, experience, accommodation, preferred_gender,
          status, completion_percent
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, 'active', 40)
        RETURNING *`,
        [
          salonId,
          jobRole,
          otherCategory || null,
          customRoleName || null,
          JSON.stringify(skills),
          location,
          numberOfStaff,
          salaryMin,
          salaryMax,
          workType,
          experience,
          accommodation || null,
          preferredGender || 'any',
        ]
      );

      // Auto-calculate completion percentage based on filled fields
      const jobData = result.rows[0];
      const completion = this.calculateJobCompletion(jobData);

      // Update with calculated completion if different from default
      if (completion !== 40) {
        await db.query(
          'UPDATE jobs SET completion_percent = $1 WHERE id = $2',
          [completion, jobData.id]
        );
        jobData.completion_percent = completion;
      }

      const job = this._formatJob(jobData);
      logger.info(`Job created: ${job.id} by salon: ${salonId} - Completion: ${completion}%`);
      
      return { success: true, job };
    } catch (error) {
      logger.error('Create job error:', error.message);
      throw error;
    }
  }

  /**
   * Get job by ID
   */
  async getJobById(jobId, salonId = null) {
    try {
      let query = 'SELECT * FROM jobs WHERE id = $1';
      const params = [jobId];

      // If salonId provided, ensure the job belongs to this salon
      if (salonId) {
        query += ' AND salon_id = $2';
        params.push(salonId);
      }

      const result = await db.query(query, params);

      if (result.rows.length === 0) {
        return { success: false, message: 'Job not found' };
      }

      return { success: true, job: this._formatJob(result.rows[0]) };
    } catch (error) {
      logger.error('Get job error:', error.message);
      throw error;
    }
  }

  /**
   * Get all jobs for a salon (with per-job candidate counts)
   */
  async getJobsBySalon(salonId, options = {}) {
    const { status, limit = 20, offset = 0 } = options;

    try {
      // Main query with LEFT JOIN for per-status application counts
      let query = `
        SELECT j.*,
          COALESCE(ac.total_applications, 0) AS total_applications_real,
          COALESCE(ac.shortlisted_count, 0) AS shortlisted_count,
          COALESCE(ac.interview_count, 0) AS interview_count,
          COALESCE(ac.hired_count, 0) AS hired_count
        FROM jobs j
        LEFT JOIN (
          SELECT 
            job_id,
            COUNT(*) AS total_applications,
            COUNT(*) FILTER (WHERE status = 'shortlisted') AS shortlisted_count,
            COUNT(*) FILTER (WHERE status = 'interview') AS interview_count,
            COUNT(*) FILTER (WHERE status = 'hired') AS hired_count
          FROM applications
          GROUP BY job_id
        ) ac ON ac.job_id = j.id
        WHERE j.salon_id = $1
      `;
      const params = [salonId];
      let paramIndex = 2;

      if (status) {
        query += ` AND j.status = $${paramIndex}`;
        params.push(status);
        paramIndex++;
      }

      query += ` ORDER BY j.created_at DESC LIMIT $${paramIndex} OFFSET $${paramIndex + 1}`;
      params.push(limit, offset);

      const result = await db.query(query, params);

      // Get total count
      let countQuery = 'SELECT COUNT(*) FROM jobs WHERE salon_id = $1';
      const countParams = [salonId];
      if (status) {
        countQuery += ' AND status = $2';
        countParams.push(status);
      }
      const countResult = await db.query(countQuery, countParams);

      return {
        success: true,
        jobs: result.rows.map((row) => ({
          ...this._formatJob(row),
          totalApplications: parseInt(row.total_applications_real) || 0,
          shortlistedCount: parseInt(row.shortlisted_count) || 0,
          interviewCount: parseInt(row.interview_count) || 0,
          hiredCount: parseInt(row.hired_count) || 0,
        })),
        total: parseInt(countResult.rows[0].count),
        limit,
        offset,
      };
    } catch (error) {
      logger.error('Get jobs by salon error:', error.message);
      throw error;
    }
  }

  /**
   * Search/browse active jobs (for job seekers)
   */
  async searchJobs(filters = {}) {
    const {
      location,
      jobRole,
      workType,
      experience,
      salaryMin,
      salaryMax,
      limit = 20,
      offset = 0,
    } = filters;

    try {
      let query = `
        SELECT j.*, s.salon_name, s.owner_name, s.city as salon_city, s.verification_status as salon_verification_status
        FROM jobs j
        LEFT JOIN salons s ON j.salon_id = s.id
        WHERE j.status = 'active'
        AND j.expires_at > NOW()
      `;
      const params = [];
      let paramIndex = 1;

      if (location) {
        query += ` AND LOWER(j.location) LIKE LOWER($${paramIndex})`;
        params.push(`%${location}%`);
        paramIndex++;
      }

      if (jobRole) {
        query += ` AND j.job_role = $${paramIndex}`;
        params.push(jobRole);
        paramIndex++;
      }

      if (workType) {
        query += ` AND j.work_type = $${paramIndex}`;
        params.push(workType);
        paramIndex++;
      }

      if (experience) {
        query += ` AND j.experience = $${paramIndex}`;
        params.push(experience);
        paramIndex++;
      }

      if (salaryMin) {
        query += ` AND j.salary_max >= $${paramIndex}`;
        params.push(salaryMin);
        paramIndex++;
      }

      if (salaryMax) {
        query += ` AND j.salary_min <= $${paramIndex}`;
        params.push(salaryMax);
        paramIndex++;
      }

      query += ` ORDER BY j.is_featured DESC, j.created_at DESC`;
      query += ` LIMIT $${paramIndex} OFFSET $${paramIndex + 1}`;
      params.push(limit, offset);

      const result = await db.query(query, params);

      const salonIds = [...new Set(result.rows.map((r) => r.salon_id).filter(Boolean))];
      /** @type {Map<string, string[]>} */
      const photosBySalon = new Map();
      const maxPhotosPerSalon = 12;

      if (salonIds.length > 0) {
        const mediaRes = await db.query(
          `SELECT salon_id, media_url, is_primary, display_order
           FROM salon_media
           WHERE salon_id = ANY($1::uuid[])
             AND media_type IN ('photo', 'logo')
           ORDER BY salon_id, is_primary DESC, display_order ASC NULLS LAST`,
          [salonIds]
        );

        for (const m of mediaRes.rows) {
          const sid = m.salon_id;
          if (!photosBySalon.has(sid)) photosBySalon.set(sid, []);
          const arr = photosBySalon.get(sid);
          if (arr.length < maxPhotosPerSalon && m.media_url) {
            arr.push(m.media_url);
          }
        }

        for (const [sid, urls] of photosBySalon.entries()) {
          photosBySalon.set(sid, await s3Service.presignGetUrls(urls));
        }
      }

      return {
        success: true,
        jobs: result.rows.map((row) => ({
          ...this._formatJob(row),
          salonName: row.salon_name,
          ownerName: row.owner_name,
          salonVerificationStatus: row.salon_verification_status || 'unverified',
          salonPhotoUrls: photosBySalon.get(row.salon_id) || [],
        })),
        limit,
        offset,
      };
    } catch (error) {
      logger.error('Search jobs error:', error.message);
      throw error;
    }
  }

  /**
   * Update job (partial update)
   */
  async updateJob(jobId, salonId, updates) {
    // Normalize shift type from UI to allowed DB values
    if (updates.shiftType) {
      const shiftMap = {
        full_day: 'flexible',
        shift_based: 'flexible',
        morning: 'morning',
        evening: 'evening',
        night: 'night',
        flexible: 'flexible',
      };
      updates.shiftType = shiftMap[updates.shiftType] || 'flexible';
    }

    const allowedFields = [
      'job_role', 'other_category', 'custom_role_name', 'skills',
      'location', 'number_of_staff', 'salary_min', 'salary_max',
      'work_type', 'experience', 'accommodation', 'preferred_gender',
      'status', 'description', 'shift_type', 'weekly_off', 'facilities',
      'completion_percent',
    ];

    // Convert camelCase to snake_case and filter allowed fields
    const fieldMapping = {
      jobRole: 'job_role',
      otherCategory: 'other_category',
      customRoleName: 'custom_role_name',
      numberOfStaff: 'number_of_staff',
      salaryMin: 'salary_min',
      salaryMax: 'salary_max',
      workType: 'work_type',
      preferredGender: 'preferred_gender',
      shiftType: 'shift_type',
      weeklyOff: 'weekly_off',
      completionPercent: 'completion_percent',
    };

    const updateFields = [];
    const values = [];
    let paramIndex = 1;

    for (const [key, value] of Object.entries(updates)) {
      const dbField = fieldMapping[key] || key;
      if (allowedFields.includes(dbField) && value !== undefined) {
        updateFields.push(`${dbField} = $${paramIndex}`);
        // Handle JSON fields
        if (['skills', 'weekly_off', 'facilities'].includes(dbField)) {
          values.push(JSON.stringify(value));
        } else {
          values.push(value);
        }
        paramIndex++;
      }
    }

    if (updateFields.length === 0) {
      return { success: false, message: 'No valid fields to update' };
    }

    try {
      values.push(jobId, salonId);
      const result = await db.query(
        `UPDATE jobs SET ${updateFields.join(', ')}, updated_at = NOW()
         WHERE id = $${paramIndex} AND salon_id = $${paramIndex + 1}
         RETURNING *`,
        values
      );

      if (result.rows.length === 0) {
        return { success: false, message: 'Job not found or access denied' };
      }

      // Auto-calculate and update completion percentage
      const updatedJob = result.rows[0];
      const completion = this.calculateJobCompletion(updatedJob);

      // Update completion if it changed
      if (updatedJob.completion_percent !== completion) {
        await db.query(
          'UPDATE jobs SET completion_percent = $1 WHERE id = $2',
          [completion, jobId]
        );
        updatedJob.completion_percent = completion;
      }

      logger.info(`Job updated: ${jobId} - Completion: ${completion}%`);
      return { success: true, job: this._formatJob(updatedJob) };
    } catch (error) {
      logger.error('Update job error:', error.message);
      throw error;
    }
  }

  /**
   * Delete/close a job
   */
  async deleteJob(jobId, salonId) {
    try {
      // Soft delete by changing status to 'closed'
      const result = await db.query(
        `UPDATE jobs SET status = 'closed', updated_at = NOW()
         WHERE id = $1 AND salon_id = $2
         RETURNING id`,
        [jobId, salonId]
      );

      if (result.rows.length === 0) {
        return { success: false, message: 'Job not found or access denied' };
      }

      logger.info(`Job closed: ${jobId}`);
      return { success: true, message: 'Job closed successfully' };
    } catch (error) {
      logger.error('Delete job error:', error.message);
      throw error;
    }
  }

  /**
   * Increment view count
   */
  async incrementViews(jobId) {
    try {
      await db.query(
        'UPDATE jobs SET views_count = views_count + 1 WHERE id = $1',
        [jobId]
      );
      return { success: true };
    } catch (error) {
      logger.error('Increment views error:', error.message);
      return { success: false };
    }
  }

  /**
   * Get job completion percentage
   */
  async getJobCompletion(jobId, salonId) {
    try {
      const result = await db.query(
        'SELECT completion_percent FROM jobs WHERE id = $1 AND salon_id = $2',
        [jobId, salonId]
      );

      if (result.rows.length === 0) {
        return { success: false, message: 'Job not found' };
      }

      return {
        success: true,
        completionPercent: result.rows[0].completion_percent,
      };
    } catch (error) {
      logger.error('Get job completion error:', error.message);
      throw error;
    }
  }

  /**
   * Calculate and update job completion percentage
   */
  /**
   * Calculate job completion percentage based on filled fields
   * @param {object} job - Job data object
   * @returns {number} Completion percentage (0-100)
   */
  calculateJobCompletion(job) {
    let completion = 0;
    const maxCompletion = 100;

    // Step 1 - Basic Job Details (40% total)
    // Job role is always required (10%)
    completion += 10;

    // Location is required (10%)
    if (job.location && job.location.trim().length > 0) {
      completion += 10;
    }

    // Salary range (5%)
    if (job.salary_min && job.salary_max && job.salary_max > job.salary_min) {
      completion += 5;
    }

    // Number of staff (2%)
    if (job.number_of_staff && job.number_of_staff > 0) {
      completion += 2;
    }

    // Skills (5%)
    if (job.skills) {
      try {
        const skills = typeof job.skills === 'string' ? JSON.parse(job.skills) : job.skills;
        if (Array.isArray(skills) && skills.length > 0) {
          completion += 5;
        }
      } catch (e) {
        // Invalid JSON, skip
      }
    }

    // Custom role name (if "other" selected) (3%)
    if (job.job_role === 'other' && job.custom_role_name && job.custom_role_name.trim().length > 0) {
      completion += 3;
    }

    // Accommodation (Step 2 optional) (2%)
    if (job.accommodation) {
      completion += 2;
    }

    // Preferred gender (Step 2 optional) (3%)
    if (job.preferred_gender && job.preferred_gender !== 'any') {
      completion += 3;
    }

    // Step 2 - Work Details (10% total)
    // Work type is required (5%)
    if (job.work_type) {
      completion += 5;
    }

    // Experience is required (5%)
    if (job.experience) {
      completion += 5;
    }

    // Step 3 - Profile Enrichment (50% total)
    // Description (15%)
    if (job.description && job.description.trim().length > 20) {
      completion += 15;
    }

    // Shift type (10%)
    if (job.shift_type) {
      completion += 10;
    }

    // Weekly off (10%)
    if (job.weekly_off) {
      try {
        const weeklyOff = typeof job.weekly_off === 'string' ? JSON.parse(job.weekly_off) : job.weekly_off;
        if (Array.isArray(weeklyOff) && weeklyOff.length > 0) {
          completion += 10;
        }
      } catch (e) {
        // Invalid JSON, skip
      }
    }

    // Facilities (15%)
    if (job.facilities) {
      try {
        const facilities = typeof job.facilities === 'string' ? JSON.parse(job.facilities) : job.facilities;
        if (Array.isArray(facilities) && facilities.length > 0) {
          completion += 15;
        }
      } catch (e) {
        // Invalid JSON, skip
      }
    }

    // Cap at 100%
    return Math.min(Math.round(completion), maxCompletion);
  }

  /**
   * Update job completion percentage based on filled fields
   * @param {string} jobId - Job UUID
   * @param {string} salonId - Salon UUID
   * @returns {Promise<object>} Update result
   */
  async updateJobCompletion(jobId, salonId) {
    try {
      const jobResult = await db.query(
        'SELECT * FROM jobs WHERE id = $1 AND salon_id = $2',
        [jobId, salonId]
      );

      if (jobResult.rows.length === 0) {
        return { success: false, message: 'Job not found' };
      }

      const job = jobResult.rows[0];
      const completion = this.calculateJobCompletion(job);

      await db.query(
        'UPDATE jobs SET completion_percent = $1 WHERE id = $2',
        [completion, jobId]
      );

      logger.info(`Job completion updated: ${jobId} - ${completion}%`);

      return { success: true, completionPercent: completion };
    } catch (error) {
      logger.error('Update job completion error:', error.message);
      throw error;
    }
  }

  /**
   * Format job from database row to API response
   */
  _formatJob(row) {
    if (!row) return null;

    return {
      id: row.id,
      salonId: row.salon_id,
      jobRole: row.job_role,
      otherCategory: row.other_category,
      customRoleName: row.custom_role_name,
      skills: typeof row.skills === 'string' ? JSON.parse(row.skills) : row.skills || [],
      location: row.location,
      numberOfStaff: row.number_of_staff,
      salaryMin: parseFloat(row.salary_min),
      salaryMax: parseFloat(row.salary_max),
      workType: row.work_type,
      experience: row.experience,
      accommodation: row.accommodation,
      preferredGender: row.preferred_gender,
      status: row.status,
      isFeatured: row.is_featured,
      viewsCount: row.views_count,
      applicationsCount: row.applications_count,
      description: row.description,
      shiftType: row.shift_type,
      weeklyOff: typeof row.weekly_off === 'string' ? JSON.parse(row.weekly_off) : row.weekly_off || [],
      facilities: typeof row.facilities === 'string' ? JSON.parse(row.facilities) : row.facilities || [],
      completionPercent: row.completion_percent,
      vacancyCount: row.vacancy_count || row.number_of_staff || 1,
      expiresAt: row.expires_at,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    };
  }
}

export default new JobService();







