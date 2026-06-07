import db from '../database/connection.js';
import logger from '../utils/logger.js';
import s3Service from './s3Service.js';

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

  _parsePreferredCities(prefs) {
    if (!prefs) return [];
    try {
      const raw = prefs.preferred_cities;
      if (typeof raw === 'string') return JSON.parse(raw);
      return Array.isArray(raw) ? raw : [];
    } catch {
      return [];
    }
  }

  /**
   * Recompute profile_completion_percent from current row (+ prefs) and persist if it drifted
   */
  async syncStoredCompletion(seekerId) {
    const seeker = await this.findById(seekerId);
    if (!seeker) return null;
    const prefs = await this.getPreferences(seekerId);
    const computed = this.calculateCompletion(seeker, prefs);
    const stored = seeker.profile_completion_percent ?? 0;
    if (computed !== stored) {
      await db.query(
        'UPDATE seeker_profiles SET profile_completion_percent = $1 WHERE id = $2',
        [computed, seekerId]
      );
      seeker.profile_completion_percent = computed;
    }
    return seeker;
  }

  /**
   * Persist completion after profile or preferences change.
   */
  async refreshCompletionFromDb(seekerId) {
    const seeker = await this.findById(seekerId);
    if (!seeker) return;
    const prefs = await this.getPreferences(seekerId);
    const completion = this.calculateCompletion(seeker, prefs);
    await db.query(
      'UPDATE seeker_profiles SET profile_completion_percent = $1 WHERE id = $2',
      [completion, seekerId]
    );
  }

  /**
   * Find or create a minimal seeker record (for auth flow)
   */
  async findOrCreate(phoneNumber, countryCode = '+91') {
    let seeker = await this.findByPhone(phoneNumber);
    let isNew = false;

    if (!seeker) {
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

  /** Strip presigned query params; keep stable S3 object URL for DB storage. */
  _canonicalMediaUrl(url) {
    if (!url || typeof url !== 'string') return url;
    return url.split('?')[0].trim();
  }

  _canonicalPortfolioForStorage(items) {
    if (!Array.isArray(items)) return items;
    return items.map((item) => {
      if (typeof item === 'string') {
        return { url: this._canonicalMediaUrl(item), kind: 'image' };
      }
      if (item && typeof item === 'object') {
        return {
          ...item,
          url: this._canonicalMediaUrl(String(item.url || '')),
        };
      }
      return item;
    });
  }

  /**
   * Create / update seeker profile
   */
  async updateProfile(seekerId, data) {
    const allowedFields = [
      'full_name', 'gender', 'city', 'preferred_role',
      'experience', 'expected_salary', 'expected_salary_max', 'current_salary',
      'experience_years', 'marital_status', 'email',
      'has_professional_course', 'professional_course_certificate_url',
      'work_portfolio_urls',
      'skills', 'profile_photo_url',
    ];

    const jsonFields = new Set(['skills', 'work_portfolio_urls']);

    const updates = [];
    const values = [];
    let paramIndex = 1;

    for (const field of allowedFields) {
      const camelKey = field.replace(/_([a-z])/g, (_, c) => c.toUpperCase());
      const value = data[camelKey] !== undefined ? data[camelKey] : data[field];
      if (value === undefined) continue;

      let stored = value;
      if (field === 'profile_photo_url' || field === 'professional_course_certificate_url') {
        stored = this._canonicalMediaUrl(value);
      } else if (field === 'work_portfolio_urls') {
        stored = this._canonicalPortfolioForStorage(value);
      }

      updates.push(`${field} = $${paramIndex}`);
      if (jsonFields.has(field)) {
        values.push(typeof stored === 'string' ? stored : JSON.stringify(stored));
      } else {
        values.push(stored);
      }
      paramIndex++;
    }

    if (updates.length === 0) {
      return { seeker: await this.findById(seekerId) };
    }

    values.push(seekerId);
    await db.query(
      `UPDATE seeker_profiles SET ${updates.join(', ')} WHERE id = $${paramIndex} RETURNING *`,
      values
    );

    await this.refreshCompletionFromDb(seekerId);
    const seeker = await this.findById(seekerId);

    return { seeker };
  }

  /**
   * Weighted completion (max 100). Uses seeker row + optional preferences row.
   */
  calculateCompletion(seeker, prefs = null) {
    let score = 0;
    if (seeker.full_name) score += 17;
    if (seeker.city) score += 17;
    if (seeker.preferred_role) score += 17;

    const hasExp = !!(
      seeker.experience
      || (seeker.experience_years != null && seeker.experience_years >= 0)
    );
    if (hasExp) score += 10;

    try {
      const skills = typeof seeker.skills === 'string'
        ? JSON.parse(seeker.skills)
        : seeker.skills;
      if (Array.isArray(skills) && skills.length > 0) score += 9;
    } catch { /* no skills */ }

    if (seeker.profile_photo_url) score += 9;
    if (seeker.gender) score += 7;

    if (seeker.expected_salary != null || seeker.expected_salary_max != null) score += 5;

    if (prefs?.job_type) score += 3;
    const pc = this._parsePreferredCities(prefs);
    if (Array.isArray(pc) && pc.length >= 2) score += 6;
    else if (pc.length === 1) score += 4;
    else if (seeker.city) score += 2;

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

    const prefs = await this.getPreferences(seekerId);
    const pc = this._parsePreferredCities(prefs);

    const breakdown = {
      fullName: { filled: !!seeker.full_name, weight: 17 },
      city: { filled: !!seeker.city, weight: 17 },
      preferredRole: { filled: !!seeker.preferred_role, weight: 17 },
      experience: {
        filled: !!(seeker.experience || (seeker.experience_years != null && seeker.experience_years >= 0)),
        weight: 10,
      },
      skills: { filled: Array.isArray(skills) && skills.length > 0, weight: 9 },
      profilePhoto: { filled: !!seeker.profile_photo_url, weight: 9 },
      gender: { filled: !!seeker.gender, weight: 7 },
      salaryExpectation: {
        filled: seeker.expected_salary != null || seeker.expected_salary_max != null,
        weight: 5,
      },
      jobTypePreference: { filled: !!(prefs?.job_type), weight: 3 },
      preferredCities: { filled: pc.length > 0, weight: 6 },
    };

    const percent = Object.values(breakdown).reduce(
      (sum, item) => sum + (item.filled ? item.weight : 0),
      0
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

    await this.refreshCompletionFromDb(seekerId);

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

  _parseWorkPortfolio(seeker) {
    try {
      const raw = seeker.work_portfolio_urls;
      if (raw == null) return [];
      const arr = typeof raw === 'string' ? JSON.parse(raw) : raw;
      if (!Array.isArray(arr)) return [];
      return arr.map((item) => {
        if (typeof item === 'string') return { url: item, kind: 'image' };
        if (item && typeof item === 'object') {
          return {
            url: String(item.url || ''),
            kind: (item.kind === 'video' ? 'video' : 'image'),
          };
        }
        return { url: '', kind: 'image' };
      }).filter((x) => x.url.length > 0);
    } catch {
      return [];
    }
  }

  /**
   * Format seeker for API response (snake_case → camelCase).
   * Presigns S3 media URLs so mobile Image.network can load private bucket objects.
   * @param {object} seeker - seeker_profiles row
   * @param {object|null} prefs - seeker_preferences row (optional; loaded if omitted in callers that merge)
   */
  async formatSeekerResponse(seeker, prefs = null) {
    if (!seeker) return null;

    let skills = [];
    try {
      skills = typeof seeker.skills === 'string' ? JSON.parse(seeker.skills) : (seeker.skills || []);
    } catch { skills = []; }

    const preferredCities = this._parsePreferredCities(prefs);
    const workPortfolioUrls = this._parseWorkPortfolio(seeker);

    const presignedPortfolio = await Promise.all(
      workPortfolioUrls.map(async (item) => ({
        ...item,
        url: await s3Service.presignGetUrl(item.url),
      }))
    );

    const out = {
      id: seeker.id,
      phoneNumber: seeker.phone_number,
      countryCode: seeker.country_code,
      fullName: seeker.full_name,
      gender: seeker.gender,
      city: seeker.city,
      preferredRole: seeker.preferred_role,
      experience: seeker.experience,
      experienceYears: seeker.experience_years != null ? seeker.experience_years : null,
      expectedSalary: seeker.expected_salary ? parseFloat(seeker.expected_salary) : null,
      expectedSalaryMax: seeker.expected_salary_max ? parseFloat(seeker.expected_salary_max) : null,
      currentSalary: seeker.current_salary ? parseFloat(seeker.current_salary) : null,
      maritalStatus: seeker.marital_status,
      email: seeker.email,
      hasProfessionalCourse: seeker.has_professional_course,
      professionalCourseCertificateUrl: await s3Service.presignGetUrl(
        seeker.professional_course_certificate_url
      ),
      workPortfolioUrls: presignedPortfolio,
      skills,
      profilePhotoUrl: await s3Service.presignGetUrl(seeker.profile_photo_url),
      profileCompletionPercent: seeker.profile_completion_percent || 0,
      createdAt: seeker.created_at,
      updatedAt: seeker.updated_at,
    };

    if (prefs) {
      out.jobType = prefs.job_type;
      out.preferredCities = preferredCities;
      out.immediateJoin = prefs.immediate_join;
      out.preferredSalary = prefs.preferred_salary ? parseFloat(prefs.preferred_salary) : null;
    } else {
      out.jobType = null;
      out.preferredCities = [];
      out.immediateJoin = true;
      out.preferredSalary = null;
    }

    return out;
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

  /**
   * Public seeker card for salon owners (no phone number).
   */
  async formatSeekerPublicResponse(seeker, prefs = null) {
    const full = await this.formatSeekerResponse(seeker, prefs);
    if (!full) return null;
    const { phoneNumber, countryCode, email, ...rest } = full;
    return rest;
  }

  /**
   * Browse job seeker profiles for salon owners (filter by role / city).
   */
  async browseForOwner({ jobRole, location, limit = 50, offset = 0 }) {
    const params = [];
    const conditions = [
      'sp.full_name IS NOT NULL',
      "TRIM(sp.full_name) <> ''",
      'sp.city IS NOT NULL',
      "TRIM(sp.city) <> ''",
      'sp.preferred_role IS NOT NULL',
      "TRIM(sp.preferred_role) <> ''",
    ];

    if (jobRole) {
      params.push(jobRole);
      conditions.push(`sp.preferred_role = $${params.length}`);
    }
    if (location) {
      params.push(`%${location.trim()}%`);
      conditions.push(`sp.city ILIKE $${params.length}`);
    }

    const where = conditions.join(' AND ');
    const countResult = await db.query(
      `SELECT COUNT(*)::int AS total FROM seeker_profiles sp WHERE ${where}`,
      params
    );
    const total = countResult.rows[0]?.total ?? 0;

    params.push(limit, offset);
    const limitIdx = params.length - 1;
    const offsetIdx = params.length;

    const listResult = await db.query(
      `SELECT sp.*, pref.job_type, pref.preferred_cities, pref.immediate_join, pref.preferred_salary
       FROM seeker_profiles sp
       LEFT JOIN seeker_preferences pref ON pref.seeker_id = sp.id
       WHERE ${where}
       ORDER BY sp.profile_completion_percent DESC, sp.updated_at DESC
       LIMIT $${limitIdx} OFFSET $${offsetIdx}`,
      params
    );

    const seekers = await Promise.all(
      listResult.rows.map(async (row) => {
        const prefs = row.job_type != null
          ? {
              job_type: row.job_type,
              preferred_cities: row.preferred_cities,
              immediate_join: row.immediate_join,
              preferred_salary: row.preferred_salary,
            }
          : null;
        return this.formatSeekerPublicResponse(row, prefs);
      })
    );

    const citiesResult = await db.query(
      `SELECT DISTINCT city FROM seeker_profiles
       WHERE city IS NOT NULL AND TRIM(city) <> ''
       ORDER BY city ASC`
    );
    const cities = citiesResult.rows.map((r) => r.city).filter(Boolean);

    return { seekers, total, cities };
  }
}

export default new SeekerService();
