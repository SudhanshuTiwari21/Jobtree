import db from '../database/connection.js';
import config from '../config/index.js';
import logger from '../utils/logger.js';

/**
 * Call Masking Service
 * 
 * Routes owner-seeker calls through a proxy number (Twilio)
 * so neither party sees the other's real phone number.
 * 
 * This is a monetization lever:
 * - Free tier: 3 calls/candidate/day
 * - Premium: unlimited calls
 * 
 * Future upgrades (TODO):
 * - Record call duration for analytics
 * - Charge per call for monetization
 * - Unlock unlimited calls for premium subscriptions
 */
class CallMaskingService {
  constructor() {
    this.twilioClient = null;
    this._initTwilio();
  }

  /**
   * Initialize Twilio client if credentials are available
   */
  _initTwilio() {
    const { accountSid, authToken } = config.twilio;
    if (accountSid && authToken) {
      try {
        // Dynamic import to avoid hard dependency if Twilio is not needed
        import('twilio').then((twilioModule) => {
          const Twilio = twilioModule.default;
          this.twilioClient = new Twilio(accountSid, authToken);
          logger.info('Twilio client initialized for call masking');
        }).catch((err) => {
          logger.warn('Twilio package not installed. Call masking will run in dry-run mode. Install with: npm install twilio');
        });
      } catch (err) {
        logger.warn('Twilio initialization failed:', err.message);
      }
    } else {
      logger.warn('Twilio credentials not configured. Call masking runs in dry-run mode.');
    }
  }

  /**
   * Allowed application statuses for calling
   */
  static CALLABLE_STATUSES = ['shortlisted', 'interview'];

  /**
   * Validate that a call can be made for this application
   * 
   * @param {string} applicationId
   * @param {string} salonId - from JWT
   * @returns {object} { application, ownerPhone, seekerPhone }
   */
  async validateCallRequest(applicationId, salonId) {
    // Fetch application with job ownership, owner phone, and seeker phone
    const result = await db.query(
      `SELECT 
        a.id AS application_id,
        a.status,
        a.job_id,
        a.seeker_id,
        j.salon_id,
        j.job_role,
        j.custom_role_name,
        s.phone_number AS owner_phone,
        s.country_code AS owner_country_code,
        sp.phone_number AS seeker_phone,
        sp.country_code AS seeker_country_code,
        sp.full_name AS seeker_name
      FROM applications a
      JOIN jobs j ON a.job_id = j.id
      JOIN salons s ON j.salon_id = s.id
      JOIN seeker_profiles sp ON a.seeker_id = sp.id
      WHERE a.id = $1`,
      [applicationId]
    );

    if (result.rows.length === 0) {
      throw Object.assign(new Error('Application not found'), { statusCode: 404 });
    }

    const data = result.rows[0];

    // Verify ownership
    if (data.salon_id !== salonId) {
      throw Object.assign(new Error('Access denied'), { statusCode: 403 });
    }

    // Verify status allows calling
    if (!CallMaskingService.CALLABLE_STATUSES.includes(data.status)) {
      throw Object.assign(
        new Error(`Cannot call candidates with status '${data.status}'. Only shortlisted or interview candidates can be called.`),
        { statusCode: 400, code: 'INVALID_CALL_STATUS' }
      );
    }

    return {
      applicationId: data.application_id,
      jobId: data.job_id,
      seekerId: data.seeker_id,
      ownerId: data.salon_id,
      status: data.status,
      jobRole: data.custom_role_name || data.job_role,
      ownerPhone: this._formatPhone(data.owner_phone, data.owner_country_code),
      seekerPhone: this._formatPhone(data.seeker_phone, data.seeker_country_code),
      seekerName: data.seeker_name,
    };
  }

  /**
   * Check rate limit: max N calls per candidate per day
   * 
   * @param {string} ownerId
   * @param {string} seekerId
   * @returns {object} { allowed, remaining, limit }
   */
  async checkRateLimit(ownerId, seekerId) {
    const maxCalls = config.twilio.maxCallsPerCandidatePerDay;

    const result = await db.query(
      `SELECT COUNT(*) FROM call_sessions 
       WHERE owner_id = $1 AND seeker_id = $2 
       AND created_at >= CURRENT_DATE
       AND call_status NOT IN ('failed')`,
      [ownerId, seekerId]
    );

    const callsToday = parseInt(result.rows[0].count);
    const remaining = Math.max(0, maxCalls - callsToday);

    return {
      allowed: callsToday < maxCalls,
      remaining,
      limit: maxCalls,
      callsToday,
    };
  }

  /**
   * Initiate a masked call between owner and seeker
   * 
   * Flow:
   * 1. Validate application & ownership
   * 2. Check rate limit
   * 3. Create call_sessions row (status: initiated)
   * 4. Call Twilio API to connect owner → proxy → seeker
   * 5. Return session info
   * 
   * @param {string} applicationId
   * @param {string} salonId
   */
  async initiateCall(applicationId, salonId) {
    // Step 1: Validate
    const callData = await this.validateCallRequest(applicationId, salonId);

    // Step 2: Rate limit
    const rateLimit = await this.checkRateLimit(callData.ownerId, callData.seekerId);
    if (!rateLimit.allowed) {
      throw Object.assign(
        new Error(`Daily call limit reached (${rateLimit.limit} calls/candidate/day). Try again tomorrow.`),
        { statusCode: 429, code: 'CALL_RATE_LIMIT' }
      );
    }

    // Step 3: Create session
    const sessionResult = await db.query(
      `INSERT INTO call_sessions (job_id, application_id, owner_id, seeker_id, call_status, provider)
       VALUES ($1, $2, $3, $4, 'initiated', 'twilio')
       RETURNING *`,
      [callData.jobId, applicationId, callData.ownerId, callData.seekerId]
    );
    const session = sessionResult.rows[0];

    // Step 4: Call telephony provider
    let providerCallSid = null;
    try {
      if (this.twilioClient && config.twilio.phoneNumber) {
        const webhookUrl = `${config.twilio.webhookBaseUrl}/api/calls/webhook/connect/${session.id}`;

        const call = await this.twilioClient.calls.create({
          to: callData.ownerPhone,
          from: config.twilio.phoneNumber,
          url: webhookUrl,
          method: 'POST',
          statusCallback: `${config.twilio.webhookBaseUrl}/api/calls/webhook/status/${session.id}`,
          statusCallbackMethod: 'POST',
          statusCallbackEvent: ['initiated', 'ringing', 'answered', 'completed'],
        });

        providerCallSid = call.sid;

        // Update session with provider SID
        await db.query(
          `UPDATE call_sessions SET provider_call_sid = $1, call_status = 'ringing' WHERE id = $2`,
          [providerCallSid, session.id]
        );

        logger.info(`Call initiated: session=${session.id}, twilio_sid=${providerCallSid}, owner→seeker`);
      } else {
        // Dry-run mode: no Twilio configured
        logger.info(`[DRY-RUN] Call session created: ${session.id} | Owner: ${callData.ownerPhone} → Seeker: ${callData.seekerPhone}`);

        await db.query(
          `UPDATE call_sessions SET call_status = 'initiated', failure_reason = 'dry_run_mode' WHERE id = $1`,
          [session.id]
        );
      }
    } catch (error) {
      // Log the failure but don't crash
      logger.error(`Call initiation failed for session ${session.id}:`, error.message);

      await db.query(
        `UPDATE call_sessions SET call_status = 'failed', failure_reason = $1 WHERE id = $2`,
        [error.message, session.id]
      );

      throw Object.assign(
        new Error('Failed to initiate call. Please try again.'),
        { statusCode: 502, code: 'CALL_INITIATION_FAILED' }
      );
    }

    // TODO: Track analytics event — call_initiated (for calls_per_job metric)

    return {
      sessionId: session.id,
      callStatus: providerCallSid ? 'ringing' : 'initiated',
      providerCallSid,
      remainingCallsToday: rateLimit.remaining - 1,
      seekerName: callData.seekerName,
      isDryRun: !this.twilioClient || !config.twilio.phoneNumber,
    };
  }

  /**
   * Handle Twilio connect webhook — bridges the call to the seeker.
   * Called when the owner picks up.
   * 
   * Returns TwiML to dial the seeker via the proxy number.
   * 
   * @param {string} sessionId
   * @returns {string} TwiML XML
   */
  async handleConnectWebhook(sessionId) {
    const result = await db.query(
      `SELECT cs.*, sp.phone_number AS seeker_phone, sp.country_code AS seeker_country_code
       FROM call_sessions cs
       JOIN seeker_profiles sp ON cs.seeker_id = sp.id
       WHERE cs.id = $1`,
      [sessionId]
    );

    if (result.rows.length === 0) {
      logger.error(`Connect webhook: session not found: ${sessionId}`);
      return this._twimlHangup('Call session not found');
    }

    const session = result.rows[0];
    const seekerPhone = this._formatPhone(session.seeker_phone, session.seeker_country_code);

    // Update status to in_progress
    await db.query(
      `UPDATE call_sessions SET call_status = 'in_progress' WHERE id = $1`,
      [sessionId]
    );

    logger.info(`Connect webhook: bridging session=${sessionId} to seeker=${seekerPhone}`);

    // TwiML: Dial the seeker, masking with proxy number
    return `<?xml version="1.0" encoding="UTF-8"?>
<Response>
  <Dial callerId="${config.twilio.phoneNumber || '+0000000000'}">
    <Number>${seekerPhone}</Number>
  </Dial>
</Response>`;
  }

  /**
   * Handle Twilio status callback webhook.
   * Updates call_sessions with final status and duration.
   * 
   * @param {string} sessionId
   * @param {object} statusData - from Twilio POST body
   */
  async handleStatusWebhook(sessionId, statusData) {
    const { CallStatus, CallDuration } = statusData;

    const statusMap = {
      'initiated': 'initiated',
      'ringing': 'ringing',
      'in-progress': 'in_progress',
      'completed': 'completed',
      'failed': 'failed',
      'no-answer': 'no_answer',
      'busy': 'busy',
      'canceled': 'failed',
    };

    const mappedStatus = statusMap[CallStatus] || 'failed';
    const duration = parseInt(CallDuration) || 0;

    await db.query(
      `UPDATE call_sessions 
       SET call_status = $1, 
           duration_seconds = $2, 
           ended_at = CASE WHEN $1 IN ('completed', 'failed', 'no_answer', 'busy') THEN CURRENT_TIMESTAMP ELSE ended_at END
       WHERE id = $3`,
      [mappedStatus, duration, sessionId]
    );

    logger.info(`Status webhook: session=${sessionId}, status=${mappedStatus}, duration=${duration}s`);

    // TODO: Track analytics — call_completed, call_duration, call_to_hire_ratio
    // TODO: If completed and duration > 30s, update conversion tracking
  }

  /**
   * Get call history for an application (for display on candidate card)
   * 
   * @param {string} applicationId
   * @param {string} salonId
   * @returns {object} { calls, totalCalls }
   */
  async getCallHistory(applicationId, salonId) {
    const result = await db.query(
      `SELECT cs.id, cs.call_status, cs.duration_seconds, cs.created_at, cs.ended_at
       FROM call_sessions cs
       WHERE cs.application_id = $1 AND cs.owner_id = $2
       ORDER BY cs.created_at DESC
       LIMIT 10`,
      [applicationId, salonId]
    );

    return {
      calls: result.rows.map((row) => ({
        id: row.id,
        status: row.call_status,
        duration: row.duration_seconds,
        createdAt: row.created_at,
        endedAt: row.ended_at,
      })),
      totalCalls: result.rows.length,
    };
  }

  /**
   * Format phone number to E.164 format
   */
  _formatPhone(phone, countryCode) {
    if (!phone) return '';
    // Strip existing + and leading zeros
    const cleaned = phone.replace(/[^\d]/g, '');
    const code = (countryCode || '+91').replace(/[^\d]/g, '');
    
    // If phone already starts with country code, use as-is
    if (cleaned.startsWith(code)) {
      return `+${cleaned}`;
    }
    return `+${code}${cleaned}`;
  }

  /**
   * Generate a TwiML hangup response
   */
  _twimlHangup(reason) {
    return `<?xml version="1.0" encoding="UTF-8"?>
<Response>
  <Say>${reason}</Say>
  <Hangup/>
</Response>`;
  }
}

export default new CallMaskingService();
