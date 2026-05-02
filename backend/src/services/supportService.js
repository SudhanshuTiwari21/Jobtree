import db from '../database/connection.js';
import logger from '../utils/logger.js';

/**
 * Support Service
 * Handles support ticket creation and management for job owners (salon owners)
 * 
 * IMPORTANT: This service is ONLY for job owners, not job seekers
 */
class SupportService {
  /**
   * Create a support ticket
   * @param {string} salonId - Salon UUID
   * @param {string} issueType - Issue type (from support_issue_type enum)
   * @param {string} description - Optional description
   * @param {object} metadata - Optional metadata (app version, device info, etc.)
   * @returns {Promise<object>} Created ticket
   */
  async createTicket(salonId, issueType, description = null, metadata = {}) {
    try {
      const result = await db.query(
        `INSERT INTO support_tickets (salon_id, issue_type, description, metadata)
         VALUES ($1, $2, $3, $4)
         RETURNING *`,
        [salonId, issueType, description, JSON.stringify(metadata)]
      );

      const ticket = result.rows[0];
      logger.info(`Support ticket created: ${ticket.id} for salon: ${salonId}, type: ${issueType}`);
      
      return { success: true, ticket };
    } catch (error) {
      logger.error('Create support ticket error:', error.message);
      throw error;
    }
  }

  /**
   * Get support tickets for a salon
   * @param {string} salonId - Salon UUID
   * @param {object} options - Query options
   * @returns {Promise<object>} Tickets with pagination
   */
  async getTickets(salonId, options = {}) {
    const { limit = 50, offset = 0, status = null } = options;

    try {
      let query = `
        SELECT * FROM support_tickets 
        WHERE salon_id = $1
      `;
      const params = [salonId];
      let paramIndex = 2;

      if (status) {
        query += ` AND status = $${paramIndex}`;
        params.push(status);
        paramIndex++;
      }

      query += ` ORDER BY created_at DESC LIMIT $${paramIndex} OFFSET $${paramIndex + 1}`;
      params.push(limit, offset);

      const result = await db.query(query, params);

      // Get total count
      let countQuery = 'SELECT COUNT(*) FROM support_tickets WHERE salon_id = $1';
      const countParams = [salonId];
      if (status) {
        countQuery += ' AND status = $2';
        countParams.push(status);
      }
      const countResult = await db.query(countQuery, countParams);

      return {
        success: true,
        tickets: result.rows,
        total: parseInt(countResult.rows[0].count),
        limit,
        offset,
      };
    } catch (error) {
      logger.error('Get support tickets error:', error.message);
      throw error;
    }
  }

  /**
   * Get support configuration (phone number, WhatsApp number)
   * @returns {Promise<object>} Support config
   */
  async getSupportConfig() {
    // In production, this could come from database or env vars
    return {
      supportPhone: process.env.SUPPORT_PHONE || '+91-1800-XXX-XXXX',
      whatsappNumber: process.env.WHATSAPP_SUPPORT || '+91-9876543210',
      whatsappMessage: 'Hi, I need help with JobTree',
    };
  }
}

export default new SupportService();





