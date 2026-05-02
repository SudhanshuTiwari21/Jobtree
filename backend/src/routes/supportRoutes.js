import express from 'express';
import supportService from '../services/supportService.js';
import { authenticate } from '../middleware/auth.js';

const router = express.Router();

/**
 * POST /api/support/ticket
 * Create a support ticket
 */
router.post('/ticket', authenticate, async (req, res) => {
  try {
    const salonId = req.salon.id;
    const { issue_type, description } = req.body;

    if (!issue_type) {
      return res.status(400).json({
        success: false,
        message: 'issue_type is required',
      });
    }

    // Validate issue type
    const validTypes = ['JOB_POSTING', 'CANDIDATE', 'APP_ISSUE', 'PAYMENT', 'OTHER'];
    if (!validTypes.includes(issue_type)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid issue_type',
      });
    }

    // Extract metadata from request (app version, device info, etc.)
    const metadata = {
      app_version: req.body.app_version || null,
      device_info: req.body.device_info || null,
      user_agent: req.headers['user-agent'] || null,
    };

    const result = await supportService.createTicket(
      salonId,
      issue_type,
      description || null,
      metadata
    );

    res.json({
      success: true,
      message: 'Support ticket created successfully',
      // Do NOT return ticket ID to user
    });
  } catch (error) {
    console.error('Create support ticket error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to create support ticket',
    });
  }
});

/**
 * GET /api/support/config
 * Get support configuration (phone, WhatsApp)
 */
router.get('/config', authenticate, async (req, res) => {
  try {
    const config = await supportService.getSupportConfig();
    res.json({
      success: true,
      data: config,
    });
  } catch (error) {
    console.error('Get support config error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get support configuration',
    });
  }
});

export default router;

