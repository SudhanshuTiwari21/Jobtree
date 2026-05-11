import express from 'express';
import { body, param } from 'express-validator';
import config from '../config/index.js';
import db from '../database/connection.js';
import salonService from '../services/salonService.js';
import pushService from '../services/pushService.js';
import { asyncHandler } from '../middleware/errorHandler.js';
import { validate } from '../middleware/validation.js';

const router = express.Router();

function requireAdminSecret(req, res, next) {
  const header = req.headers['x-admin-secret'];
  const bodySecret = req.body?.secret;
  const secret = typeof header === 'string' && header.length > 0 ? header : bodySecret;
  const expected = config.admin?.webhookSecret;
  if (!expected || secret !== expected) {
    return res.status(401).json({ success: false, message: 'Unauthorized' });
  }
  next();
}

/**
 * @route   PATCH /api/admin/salons/:salonId/verification
 * @desc    Set salon KYC outcome (until a full admin UI exists). Sends owner push.
 * @access  Header X-Admin-Secret or body.secret must match ADMIN_WEBHOOK_SECRET
 */
router.patch(
  '/salons/:salonId/verification',
  requireAdminSecret,
  [
    param('salonId').isUUID().withMessage('Invalid salon id'),
    body('status').isIn(['verified', 'rejected']).withMessage('status must be verified or rejected'),
    body('rejectionReason').optional().isString().isLength({ max: 2000 }),
    validate,
  ],
  asyncHandler(async (req, res) => {
    const { salonId } = req.params;
    const { status, rejectionReason } = req.body;

    const exists = await db.query('SELECT id, salon_name FROM salons WHERE id = $1', [salonId]);
    if (exists.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Salon not found' });
    }

    await salonService.applyAdminSalonVerificationDecision(salonId, status, rejectionReason || null);

    const title = status === 'verified' ? 'Salon verified' : 'Verification update';
    const bodyText =
      status === 'verified'
        ? 'Your salon is now verified. A verified badge appears next to your salon name.'
        : `Your verification was not approved.${rejectionReason ? ` ${rejectionReason}` : ' You can submit documents again from your profile.'}`;

    pushService.sendNotification(salonId, 'owner', {
      type: status === 'verified' ? 'salon_verification_approved' : 'salon_verification_rejected',
      title,
      body: bodyText,
      data: { deepLink: 'salon/profile', salonId },
    });

    res.json({
      success: true,
      message: `Salon verification set to ${status}`,
    });
  })
);

export default router;
