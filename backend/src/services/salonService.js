import db from '../database/connection.js';
import logger from '../utils/logger.js';
import s3Service from './s3Service.js';

class SalonService {
  /**
   * Calculate profile completion percentage based on filled fields
   * @param {object} salon - Salon data
   * @returns {number} Completion percentage
   */
  /**
   * Calculate salon profile completion percentage based on weighted sections
   * 
   * A. Basic Identity — 30% (FOUNDATION)
   *    - Phone number (verified): 10%
   *    - Salon name: 10%
   *    - City / Location: 10%
   * 
   * B. Trust & Visuals — 30% (CONVERSION DRIVER)
   *    - Profile photo OR salon logo: 10%
   *    - At least 2 salon photos: 10%
   *    - Owner / Manager name: 10%
   * 
   * C. Business Credibility — 20% (OPTIONAL, HIGH QUALITY)
   *    - Salon policies / working hours: 10%
   *    - KYC document uploaded: 10%
   * 
   * D. Job Readiness Signals — 20% (QUALITY BOOST)
   *    - At least 1 active job posted: 10%
   *    - Job details ≥ 60% complete: 10%
   * 
   * @param {object} salon - Salon data object
   * @param {object} jobStats - Job statistics { hasActiveJob: boolean, hasJobWith60Percent: boolean }
   * @param {number} photoCount - Number of salon photos
   * @returns {number} Completion percentage (0-100), rounded DOWN
   */
  calculateCompletionPercent(salon, jobStats = { hasActiveJob: false, hasJobWith60Percent: false }, photoCount = 0) {
    let completion = 0;

    // A. Basic Identity — 30%
    // Phone number (verified) — 10%
    if (salon.phone_number) {
      completion += 10;
    }

    // Salon name — 10%
    if (salon.salon_name && salon.salon_name.trim().length > 0) {
      completion += 10;
    }

    // City / Location — 10%
    if (salon.city && salon.city.trim().length > 0) {
      completion += 10;
    }

    // B. Trust & Visuals — 30%
    // Profile photo OR salon logo — 10%
    // Check if has primary media (logo/profile photo)
    if (salon.has_media && photoCount > 0) {
      completion += 10;
    }

    // At least 2 salon photos — 10%
    if (photoCount >= 2) {
      completion += 10;
    }

    // Owner / Manager name — 10%
    if (salon.owner_name && salon.owner_name.trim().length > 0) {
      completion += 10;
    }

    // C. Business Credibility — 20% (OPTIONAL)
    // Salon policies / working hours — 10%
    if (salon.has_policies) {
      completion += 10;
    }

    // KYC document uploaded — 10%
    if (salon.has_verification_docs) {
      completion += 10;
    }

    // D. Job Readiness Signals — 20%
    // At least 1 active job posted — 10%
    if (jobStats.hasActiveJob) {
      completion += 10;
    }

    // Job details ≥ 60% complete — 10%
    if (jobStats.hasJobWith60Percent) {
      completion += 10;
    }

    // Round DOWN and cap at 100%
    return Math.min(Math.floor(completion), 100);
  }

  /**
   * Get missing fields for profile completion
   * @param {object} salon - Salon data object
   * @param {number} photoCount - Number of salon photos
   * @param {object} jobStats - Job statistics
   * @returns {Array<string>} List of missing field keys
   */
  getMissingFields(salon, photoCount = 0, jobStats = { hasActiveJob: false, hasJobWith60Percent: false }) {
    const missing = [];

    // A. Basic Identity
    if (!salon.phone_number) missing.push('phone');
    if (!salon.salon_name || salon.salon_name.trim().length === 0) missing.push('salonName');
    if (!salon.city || salon.city.trim().length === 0) missing.push('city');

    // B. Trust & Visuals
    if (!salon.has_media || photoCount === 0) missing.push('photos');
    if (photoCount < 2) missing.push('morePhotos');
    if (!salon.owner_name || salon.owner_name.trim().length === 0) missing.push('ownerName');

    // C. Business Credibility (optional, but track for upsell)
    if (!salon.has_policies) missing.push('policies');
    if (!salon.has_verification_docs) missing.push('verification');

    // D. Job Readiness
    if (!jobStats.hasActiveJob) missing.push('activeJob');
    if (!jobStats.hasJobWith60Percent) missing.push('jobDetails');

    return missing;
  }

  /**
   * Calculate upsell stage based on completion percentage
   * @param {number} completionPercent - Completion percentage (0-100)
   * @returns {string} Upsell stage: 'early' | 'activation' | 'trust' | 'ready'
   */
  getUpsellStage(completionPercent) {
    if (completionPercent <= 40) {
      return 'early';
    } else if (completionPercent <= 70) {
      return 'activation';
    } else if (completionPercent <= 85) {
      return 'trust';
    } else {
      return 'ready';
    }
  }

  /**
   * Find or create salon by phone number
   * @param {string} phoneNumber - Phone number
   * @param {string} countryCode - Country code
   * @returns {Promise<object>} Salon record
   */
  async findOrCreate(phoneNumber, countryCode = '+91') {
    // Check if salon exists
    const existing = await db.query(
      'SELECT * FROM salons WHERE phone_number = $1',
      [phoneNumber]
    );

    if (existing.rows.length > 0) {
      return {
        salon: existing.rows[0],
        isNew: false,
      };
    }

    // Create new salon with phone number only
    const result = await db.query(
      `INSERT INTO salons (phone_number, country_code, profile_completion_percent)
       VALUES ($1, $2, 10)
       RETURNING *`,
      [phoneNumber, countryCode]
    );

    // Calculate initial completion (just phone number = 10%)
    const salon = result.rows[0];
    // New salon has no jobs or photos yet
    const completionPercent = this.calculateCompletionPercent(
      {
        ...salon,
        has_media: false,
        has_policies: false,
        has_verification_docs: false,
      },
      { hasActiveJob: false, hasJobWith60Percent: false },
      0
    );

    // Update completion if different
    if (completionPercent !== salon.profile_completion_percent) {
      await db.query(
        'UPDATE salons SET profile_completion_percent = $1 WHERE id = $2',
        [completionPercent, salon.id]
      );
      salon.profile_completion_percent = completionPercent;
    }

    logger.info(`New salon created for phone: ${phoneNumber} - Completion: ${completionPercent}%`);

    return {
      salon: salon,
      isNew: true,
    };
  }

  /**
   * Get job statistics for a salon (for completion calculation)
   * @param {string} salonId - Salon UUID
   * @returns {Promise<object>} Job statistics
   */
  async getJobStats(salonId) {
    try {
      // Check for active jobs
      const activeJobsResult = await db.query(
        `SELECT COUNT(*) as count FROM jobs 
         WHERE salon_id = $1 AND status = 'active'`,
        [salonId]
      );
      const hasActiveJob = parseInt(activeJobsResult.rows[0].count) > 0;

      // Check for jobs with ≥60% completion
      const jobCompletionResult = await db.query(
        `SELECT COUNT(*) as count FROM jobs 
         WHERE salon_id = $1 AND status = 'active' AND completion_percent >= 60`,
        [salonId]
      );
      const hasJobWith60Percent = parseInt(jobCompletionResult.rows[0].count) > 0;

      return {
        hasActiveJob,
        hasJobWith60Percent,
      };
    } catch (error) {
      logger.error('Get job stats error:', error.message);
      return { hasActiveJob: false, hasJobWith60Percent: false };
    }
  }

  /**
   * Get photo count for a salon
   * @param {string} salonId - Salon UUID
   * @returns {Promise<number>} Number of photos
   */
  async getPhotoCount(salonId) {
    try {
      const result = await db.query(
        `SELECT COUNT(*) as count FROM salon_media 
         WHERE salon_id = $1 AND media_type IN ('photo', 'logo')`,
        [salonId]
      );
      return parseInt(result.rows[0].count) || 0;
    } catch (error) {
      logger.error('Get photo count error:', error.message);
      return 0;
    }
  }

  /**
   * Find salon by ID
   * @param {string} salonId - Salon UUID
   * @returns {Promise<object|null>} Salon record
   */
  async findById(salonId) {
    const result = await db.query(
      `SELECT s.*,
        EXISTS(SELECT 1 FROM salon_media WHERE salon_id = s.id) as has_media,
        EXISTS(SELECT 1 FROM salon_policies WHERE salon_id = s.id) as has_policies,
        EXISTS(SELECT 1 FROM salon_verification_docs WHERE salon_id = s.id) as has_verification_docs
       FROM salons s
       WHERE s.id = $1`,
      [salonId]
    );

    return result.rows[0] || null;
  }

  /**
   * Find salon by phone number
   * @param {string} phoneNumber - Phone number
   * @returns {Promise<object|null>} Salon record
   */
  async findByPhoneNumber(phoneNumber) {
    const result = await db.query(
      `SELECT s.*,
        EXISTS(SELECT 1 FROM salon_media WHERE salon_id = s.id) as has_media,
        EXISTS(SELECT 1 FROM salon_policies WHERE salon_id = s.id) as has_policies,
        EXISTS(SELECT 1 FROM salon_verification_docs WHERE salon_id = s.id) as has_verification_docs
       FROM salons s
       WHERE s.phone_number = $1`,
      [phoneNumber]
    );

    return result.rows[0] || null;
  }

  /**
   * Update salon profile (partial update)
   * @param {string} salonId - Salon UUID
   * @param {object} updates - Fields to update
   * @returns {Promise<object>} Updated salon record
   */
  async updateProfile(salonId, updates) {
    // Allowed fields for update
    const allowedFields = [
      'salon_name',
      'owner_name',
      'city',
      'area',
      'full_address',
      'latitude',
      'longitude',
    ];

    // Filter and sanitize updates
    const validUpdates = {};
    for (const [key, value] of Object.entries(updates)) {
      const snakeKey = this.camelToSnake(key);
      if (allowedFields.includes(snakeKey) && value !== undefined) {
        validUpdates[snakeKey] = value;
      }
    }

    if (Object.keys(validUpdates).length === 0) {
      // No valid updates, return current salon
      return this.findById(salonId);
    }

    // Build dynamic UPDATE query
    const setClause = Object.keys(validUpdates)
      .map((key, index) => `${key} = $${index + 2}`)
      .join(', ');
    
    const values = [salonId, ...Object.values(validUpdates)];

    const result = await db.query(
      `UPDATE salons 
       SET ${setClause}, updated_at = NOW()
       WHERE id = $1
       RETURNING *`,
      values
    );

    if (result.rows.length === 0) {
      throw new Error('Salon not found');
    }

    // Fetch full salon with computed fields
    const salon = await this.findById(salonId);

    // Get job stats and photo count for accurate completion calculation
    const jobStats = await this.getJobStats(salonId);
    const photoCount = await this.getPhotoCount(salonId);

    // Recalculate and update completion percentage with weighted system
    const completionPercent = this.calculateCompletionPercent(salon, jobStats, photoCount);
    const isComplete = completionPercent >= 86; // 86%+ is considered complete

    await db.query(
      `UPDATE salons 
       SET profile_completion_percent = $1, is_profile_complete = $2
       WHERE id = $3`,
      [completionPercent, isComplete, salonId]
    );

    logger.info(`Salon profile updated: ${salonId} - Completion: ${completionPercent}%`);

    return this.findById(salonId);
  }

  /**
   * Update completion percent only (helper method)
   * @param {string} salonId - Salon UUID
   * @param {number} completionPercent - Completion percentage
   * @returns {Promise<void>}
   */
  async updateCompletionPercent(salonId, completionPercent) {
    const isComplete = completionPercent >= 86;
    await db.query(
      `UPDATE salons 
       SET profile_completion_percent = $1, is_profile_complete = $2
       WHERE id = $3`,
      [completionPercent, isComplete, salonId]
    );
  }

  /**
   * Get salon profile with all related data
   * @param {string} salonId - Salon UUID
   * @returns {Promise<object>} Full salon profile
   */
  async getFullProfile(salonId) {
    const salon = await this.findById(salonId);
    if (!salon) return null;

    // Get media
    const media = await db.query(
      `SELECT id, media_type, media_url, thumbnail_url, is_primary, display_order
       FROM salon_media
       WHERE salon_id = $1
       ORDER BY is_primary DESC, display_order ASC`,
      [salonId]
    );

    // Get policies
    const policies = await db.query(
      `SELECT id, policy_text, working_hours, benefits, requirements, last_updated
       FROM salon_policies
       WHERE salon_id = $1`,
      [salonId]
    );

    // Get verification docs (owner sees presigned file URLs from getFullProfile)
    const verificationDocs = await db.query(
      `SELECT id, doc_type, doc_last_4, doc_file_url, verification_status, rejection_reason, created_at, reviewed_at
       FROM salon_verification_docs
       WHERE salon_id = $1
       ORDER BY created_at DESC`,
      [salonId]
    );

    // Recalculate completion
    // Get job stats and photo count
    const jobStats = await this.getJobStats(salonId);
    const photoCount = await this.getPhotoCount(salonId);
    
    const completionPercent = this.calculateCompletionPercent(
      {
        ...salon,
        has_media: media.rows.length > 0,
        has_policies: policies.rows.length > 0,
        has_verification_docs: verificationDocs.rows.length > 0,
      },
      jobStats,
      photoCount
    );

    const mediaRows = await Promise.all(
      media.rows.map(async (row) => ({
        ...row,
        media_url: await s3Service.presignGetUrl(row.media_url),
        thumbnail_url: row.thumbnail_url
          ? await s3Service.presignGetUrl(row.thumbnail_url)
          : null,
      }))
    );

    const verificationDocsOut = await Promise.all(
      verificationDocs.rows.map(async (doc) => ({
        id: doc.id,
        docType: doc.doc_type,
        docLast4: doc.doc_last_4,
        status: doc.verification_status,
        rejectionReason: doc.rejection_reason,
        createdAt: doc.created_at,
        reviewedAt: doc.reviewed_at,
        docFileUrl: await s3Service.presignGetUrl(doc.doc_file_url),
      }))
    );

    return {
      ...this.formatSalonResponse(salon),
      profileCompletionPercent: completionPercent,
      media: mediaRows,
      policies: policies.rows[0] || null,
      verificationDocs: verificationDocsOut,
    };
  }

  /**
   * Format salon response (snake_case to camelCase)
   * @param {object} salon - Raw salon data
   * @returns {object} Formatted salon data
   */
  formatSalonResponse(salon) {
    if (!salon) return null;

    return {
      id: salon.id,
      phoneNumber: salon.phone_number,
      countryCode: salon.country_code,
      salonName: salon.salon_name,
      ownerName: salon.owner_name,
      city: salon.city,
      area: salon.area,
      fullAddress: salon.full_address,
      latitude: salon.latitude,
      longitude: salon.longitude,
      verificationStatus: salon.verification_status,
      profileCompletionPercent: salon.profile_completion_percent,
      isProfileComplete: salon.is_profile_complete,
      createdAt: salon.created_at,
      updatedAt: salon.updated_at,
    };
  }

  /**
   * Convert camelCase to snake_case
   * @param {string} str - camelCase string
   * @returns {string} snake_case string
   */
  camelToSnake(str) {
    return str.replace(/[A-Z]/g, letter => `_${letter.toLowerCase()}`);
  }

  /**
   * Record a KYC / business document and mark salon pending when applicable.
   */
  async submitVerificationDocument(salonId, docType, docLast4, docFileUrl) {
    const allowed = ['aadhaar', 'gst', 'shop_license', 'pan', 'other'];
    if (!allowed.includes(docType)) {
      const err = new Error('Invalid document type');
      err.statusCode = 400;
      throw err;
    }
    const last4 = docLast4 && String(docLast4).trim().length > 0 ? String(docLast4).trim().slice(-4) : null;

    const result = await db.query(
      `INSERT INTO salon_verification_docs (salon_id, doc_type, doc_last_4, doc_file_url, verification_status)
       VALUES ($1, $2, $3, $4, 'pending')
       RETURNING id, doc_type, doc_last_4, doc_file_url, verification_status, created_at`,
      [salonId, docType, last4, docFileUrl]
    );

    await db.query(
      `UPDATE salons SET verification_status = 'pending', updated_at = CURRENT_TIMESTAMP
       WHERE id = $1 AND verification_status IN ('unverified', 'rejected')`,
      [salonId]
    );

    return result.rows[0];
  }

  /**
   * Admin: set salon verification outcome and sync pending document rows.
   */
  async applyAdminSalonVerificationDecision(salonId, status, rejectionReason = null) {
    if (!['verified', 'rejected'].includes(status)) {
      const err = new Error('status must be "verified" or "rejected"');
      err.statusCode = 400;
      throw err;
    }

    await db.transaction(async (client) => {
      await client.query(
        `UPDATE salons SET verification_status = $2, updated_at = CURRENT_TIMESTAMP WHERE id = $1`,
        [salonId, status]
      );
      if (status === 'verified') {
        await client.query(
          `UPDATE salon_verification_docs
           SET verification_status = 'approved', reviewed_at = CURRENT_TIMESTAMP, rejection_reason = NULL
           WHERE salon_id = $1 AND verification_status = 'pending'`,
          [salonId]
        );
      } else {
        await client.query(
          `UPDATE salon_verification_docs
           SET verification_status = 'rejected', reviewed_at = CURRENT_TIMESTAMP,
               rejection_reason = COALESCE($2, 'Rejected')
           WHERE salon_id = $1 AND verification_status = 'pending'`,
          [salonId, rejectionReason]
        );
      }
    });
  }
}

export default new SalonService();








