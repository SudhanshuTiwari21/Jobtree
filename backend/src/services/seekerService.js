import db from '../database/connection.js';
import logger from '../utils/logger.js';

class SeekerService {
  /**
   * Find seeker by phone number
   */
  async findByPhone(phoneNumber) {
    const result = await db.query(
      'SELECT * FROM seeker_profiles WHERE phone_number = $1',
      [phoneNumber]
    );
    return result.rows[0] || null;
  }

  /**
   * Find seeker by ID
   */
  async findById(seekerId) {
    const result = await db.query(
      'SELECT * FROM seeker_profiles WHERE id = $1',
      [seekerId]
    );
    return result.rows[0] || null;
  }

  /**
   * Find or create a minimal seeker record (for auth flow)
   */
  async findOrCreate(phoneNumber, countryCode = '+91') {
    // Check if seeker exists
    let seeker = await this.findByPhone(phoneNumber);
    let isNew = false;

    if (!seeker) {
      // Create minimal seeker record (phone only)
      const result = await db.query(
        `INSERT INTO seeker_profiles (phone_number, country_code, profile_completion_percent)
         VALUES ($1, $2, 0)
         RETURNING *`,
        [phoneNumber, countryCode]
      );
      seeker = result.rows[0];
      isNew = true;
      logger.info(`New seeker profile created for: ${phoneNumber}`);
    }

    return { seeker, isNew };
  }

  /**
   * Check if seeker profile has basic required fields filled
   */
  hasBasicProfile(seeker) {
    return !!(seeker.full_name && seeker.city && seeker.preferred_role);
  }

  /**
   * Create / update seeker profile
   */
  async updateProfile(seekerId, data) {
    const allowedFields = [
      'full_name', 'gender', 'city', 'preferred_role',
      'experience', 'expected_salary', 'skills', 'profile_photo_url',
    ];

    const updates = [];
    const values = [];
    let paramIndex = 1;

    for (const field of allowedFields) {
      // Map camelCase from client to snake_case DB columns
      const camelKey = field.replace(/_([a-z])/g, (_, c) => c.toUpperCase());
      const value = data[camelKey] !== undefined ? data[camelKey] : data[field];
      if (value !== undefined) {
        updates.push(`${field} = $${paramIndex}`);
        values.push(field === 'skills' ? JSON.stringify(value) : value);
        paramIndex++;
      }
    }

    if (updates.length === 0) {
      return { seeker: await this.findById(seekerId) };
    }

    values.push(seekerId);
    const result = await db.query(
      `UPDATE seeker_profiles SET ${updates.join(', ')} WHERE id = $${paramIndex} RETURNING *`,
      values
    );

    const seeker = result.rows[0];

    // Recalculate completion
    const completion = this.calculateCompletion(seeker);
    await db.query(
      'UPDATE seeker_profiles SET profile_completion_percent = $1 WHERE id = $2',
      [completion, seekerId]
    );

    seeker.profile_completion_percent = completion;

    return { seeker };
  }

  /**
   * Calculate profile completion percentage
   * Weighted logic:
   *   Name = 20%, City = 20%, Role = 20%, Experience = 10%,
   *   Skills = 10%, Photo = 10%, Preferences = 10%
   */
  calculateCompletion(seeker) {
    let score = 0;
    if (seeker.full_name) score += 20;
    if (seeker.city) score += 20;
    if (seeker.preferred_role) score += 20;
    if (seeker.experience) score += 10;

    // Skills - check non-empty array
    try {
      const skills = typeof seeker.skills === 'string'
        ? JSON.parse(seeker.skills)
        : seeker.skills;
      if (Array.isArray(skills) && skills.length > 0) score += 10;
    } catch { /* no skills */ }

    if (seeker.profile_photo_url) score += 10;

    // Preferences check is async, so we do a simple heuristic here
    // (gender counts as a preference stand-in for the sync calculation)
    if (seeker.gender) score += 10;

    return Math.min(score, 100);
  }

  /**
   * Get profile completion with breakdown
   */
  async getCompletion(seekerId) {
    const seeker = await this.findById(seekerId);
    if (!seeker) return null;

    let skills = [];
    try {
      skills = typeof seeker.skills === 'string' ? JSON.parse(seeker.skills) : (seeker.skills || []);
    } catch { skills = []; }

    const breakdown = {
      fullName: { filled: !!seeker.full_name, weight: 20 },
      city: { filled: !!seeker.city, weight: 20 },
      preferredRole: { filled: !!seeker.preferred_role, weight: 20 },
      experience: { filled: !!seeker.experience, weight: 10 },
      skills: { filled: Array.isArray(skills) && skills.length > 0, weight: 10 },
      profilePhoto: { filled: !!seeker.profile_photo_url, weight: 10 },
      gender: { filled: !!seeker.gender, weight: 10 },
    };

    const percent = Object.values(breakdown).reduce(
      (sum, item) => sum + (item.filled ? item.weight : 0), 0
    );

    return { percent: Math.min(percent, 100), breakdown };
  }

  /**
   * Update seeker preferences
   */
  async updatePreferences(seekerId, data) {
    const existing = await db.query(
      'SELECT * FROM seeker_preferences WHERE seeker_id = $1',
      [seekerId]
    );

    if (existing.rows.length === 0) {
      // Insert
      await db.query(
        `INSERT INTO seeker_preferences (seeker_id, job_type, preferred_salary, preferred_cities, immediate_join)
         VALUES ($1, $2, $3, $4, $5)`,
        [
          seekerId,
          data.jobType || 'any',
          data.preferredSalary || null,
          JSON.stringify(data.preferredCities || []),
          data.immediateJoin !== undefined ? data.immediateJoin : true,
        ]
      );
    } else {
      // Update
      const updates = [];
      const values = [];
      let idx = 1;

      if (data.jobType !== undefined) {
        updates.push(`job_type = $${idx++}`);
        values.push(data.jobType);
      }
      if (data.preferredSalary !== undefined) {
        updates.push(`preferred_salary = $${idx++}`);
        values.push(data.preferredSalary);
      }
      if (data.preferredCities !== undefined) {
        updates.push(`preferred_cities = $${idx++}`);
        values.push(JSON.stringify(data.preferredCities));
      }
      if (data.immediateJoin !== undefined) {
        updates.push(`immediate_join = $${idx++}`);
        values.push(data.immediateJoin);
      }

      if (updates.length > 0) {
        values.push(seekerId);
        await db.query(
          `UPDATE seeker_preferences SET ${updates.join(', ')} WHERE seeker_id = $${idx}`,
          values
        );
      }
    }

    const result = await db.query(
      'SELECT * FROM seeker_preferences WHERE seeker_id = $1',
      [seekerId]
    );
    return result.rows[0] || null;
  }

  /**
   * Get seeker preferences
   */
  async getPreferences(seekerId) {
    const result = await db.query(
      'SELECT * FROM seeker_preferences WHERE seeker_id = $1',
      [seekerId]
    );
    return result.rows[0] || null;
  }

  /**
   * Format seeker for API response (snake_case → camelCase)
   */
  formatSeekerResponse(seeker) {
    if (!seeker) return null;

    let skills = [];
    try {
      skills = typeof seeker.skills === 'string' ? JSON.parse(seeker.skills) : (seeker.skills || []);
    } catch { skills = []; }

    return {
      id: seeker.id,
      phoneNumber: seeker.phone_number,
      countryCode: seeker.country_code,
      fullName: seeker.full_name,
      gender: seeker.gender,
      city: seeker.city,
      preferredRole: seeker.preferred_role,
      experience: seeker.experience,
      expectedSalary: seeker.expected_salary ? parseFloat(seeker.expected_salary) : null,
      skills,
      profilePhotoUrl: seeker.profile_photo_url,
      profileCompletionPercent: seeker.profile_completion_percent || 0,
      createdAt: seeker.created_at,
      updatedAt: seeker.updated_at,
    };
  }

  /**
   * Format preferences for API response
   */
  formatPreferencesResponse(prefs) {
    if (!prefs) return null;

    let preferredCities = [];
    try {
      preferredCities = typeof prefs.preferred_cities === 'string'
        ? JSON.parse(prefs.preferred_cities)
        : (prefs.preferred_cities || []);
    } catch { preferredCities = []; }

    return {
      seekerId: prefs.seeker_id,
      jobType: prefs.job_type,
      preferredSalary: prefs.preferred_salary ? parseFloat(prefs.preferred_salary) : null,
      preferredCities,
      immediateJoin: prefs.immediate_join,
      updatedAt: prefs.updated_at,
    };
  }
}

export default new SeekerService();
