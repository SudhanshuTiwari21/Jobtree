import express from 'express';
import salonService from '../services/salonService.js';
import s3Service from '../services/s3Service.js';
import { authenticate } from '../middleware/auth.js';
import { 
  validateSalonProfileUpdate, 
  validateMediaPresign, 
  validateMediaSave,
  validateUUID 
} from '../middleware/validation.js';
import { asyncHandler } from '../middleware/errorHandler.js';
import logger from '../utils/logger.js';

const router = express.Router();

// All salon routes require authentication
router.use(authenticate);

/**
 * @route   GET /api/salon/me
 * @desc    Get current salon profile
 * @access  Protected
 */
router.get(
  '/me',
  asyncHandler(async (req, res) => {
    const profile = await salonService.getFullProfile(req.salonId);

    res.status(200).json({
      success: true,
      data: profile,
    });
  })
);

/**
 * @route   PATCH /api/salon/profile
 * @desc    Update salon profile (partial update)
 * @access  Protected
 */
router.patch(
  '/profile',
  validateSalonProfileUpdate,
  asyncHandler(async (req, res) => {
    const {
      salonName,
      ownerName,
      city,
      area,
      fullAddress,
      latitude,
      longitude,
    } = req.body;

    // Build updates object with only provided fields
    const updates = {};
    if (salonName !== undefined) updates.salonName = salonName;
    if (ownerName !== undefined) updates.ownerName = ownerName;
    if (city !== undefined) updates.city = city;
    if (area !== undefined) updates.area = area;
    if (fullAddress !== undefined) updates.fullAddress = fullAddress;
    if (latitude !== undefined) updates.latitude = latitude;
    if (longitude !== undefined) updates.longitude = longitude;

    const updatedSalon = await salonService.updateProfile(req.salonId, updates);

    logger.info(`Salon profile updated: ${req.salonId}`);

    res.status(200).json({
      success: true,
      message: 'Profile updated successfully',
      data: salonService.formatSalonResponse(updatedSalon),
    });
  })
);

/**
 * @route   POST /api/salon/media/presign
 * @desc    Generate presigned URL for media upload
 * @access  Protected
 */
router.post(
  '/media/presign',
  validateMediaPresign,
  asyncHandler(async (req, res) => {
    const { mediaType, contentType, filename } = req.body;

    const presignedData = await s3Service.generateUploadUrl(
      req.salonId,
      mediaType,
      contentType,
      filename
    );

    res.status(200).json({
      success: true,
      message: 'Presigned URL generated',
      data: presignedData,
    });
  })
);

const salonDirectUploadAllowedTypes = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/gif',
  'image/heic',
  'image/heif',
  'video/mp4',
  'video/quicktime',
  'video/webm',
]);

/**
 * @route   POST /api/salon/media/upload
 * @desc    Upload image/video bytes through API; saves salon_media row (no S3 presigned PUT from client)
 * @access  Protected
 */
router.post(
  '/media/upload',
  express.raw({ limit: '20mb', type: '*/*' }),
  asyncHandler(async (req, res) => {
    const rawCt = (req.get('Content-Type') || '').split(';')[0].trim().toLowerCase();
    if (!Buffer.isBuffer(req.body) || req.body.length === 0) {
      return res.status(400).json({ success: false, message: 'Empty body' });
    }
    if (!salonDirectUploadAllowedTypes.has(rawCt)) {
      return res.status(400).json({ success: false, message: 'Unsupported content type' });
    }

    const mediaType = String(req.get('X-Media-Type') || 'photo').toLowerCase();
    if (!['photo', 'video'].includes(mediaType)) {
      return res.status(400).json({ success: false, message: 'Invalid X-Media-Type' });
    }

    const isPrimary = String(req.get('X-Is-Primary') || '').toLowerCase() === 'true';
    const filename = req.get('X-Filename')?.trim() || '';

    const mediaUrl = await s3Service.uploadSalonBuffer(req.salonId, mediaType, rawCt, req.body, {
      filename,
    });
    const media = await s3Service.saveMediaRecord(req.salonId, mediaType, mediaUrl, isPrimary);

    res.status(201).json({
      success: true,
      message: 'Media uploaded successfully',
      data: {
        id: media.id,
        mediaType: media.media_type,
        mediaUrl: media.media_url,
        isPrimary: media.is_primary,
        displayOrder: media.display_order,
      },
    });
  })
);

const verificationDocAllowedTypes = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/gif',
  'image/heic',
  'image/heif',
  'application/pdf',
]);

/**
 * @route   POST /api/salon/verification/upload
 * @desc    Upload KYC / business proof; marks salon pending when applicable
 * @access  Protected
 */
router.post(
  '/verification/upload',
  express.raw({ limit: '15mb', type: '*/*' }),
  asyncHandler(async (req, res) => {
    const rawCt = (req.get('Content-Type') || '').split(';')[0].trim().toLowerCase();
    if (!Buffer.isBuffer(req.body) || req.body.length === 0) {
      return res.status(400).json({ success: false, message: 'Empty body' });
    }
    if (!verificationDocAllowedTypes.has(rawCt)) {
      return res.status(400).json({ success: false, message: 'Unsupported content type' });
    }

    const docType = String(req.get('X-Doc-Type') || '').toLowerCase().trim();
    const allowedDoc = ['aadhaar', 'gst', 'shop_license', 'pan', 'other'];
    if (!allowedDoc.includes(docType)) {
      return res.status(400).json({ success: false, message: 'Invalid or missing X-Doc-Type header' });
    }

    const rawLast4 = req.get('X-Doc-Last-4')?.trim() || '';
    const docLast4 = rawLast4.length > 0 ? rawLast4 : null;
    const filename = req.get('X-Filename')?.trim() || '';

    const fileUrl = await s3Service.uploadSalonVerificationBuffer(req.salonId, rawCt, req.body, {
      filename,
    });
    const row = await salonService.submitVerificationDocument(req.salonId, docType, docLast4, fileUrl);

    res.status(201).json({
      success: true,
      message: 'Document submitted for review',
      data: {
        id: row.id,
        docType: row.doc_type,
        docLast4: row.doc_last_4,
        status: row.verification_status,
        createdAt: row.created_at,
      },
    });
  })
);

/**
 * @route   POST /api/salon/media
 * @desc    Save media record after upload
 * @access  Protected
 */
router.post(
  '/media',
  validateMediaSave,
  asyncHandler(async (req, res) => {
    const { mediaType, mediaUrl, isPrimary = false } = req.body;

    const media = await s3Service.saveMediaRecord(
      req.salonId,
      mediaType,
      mediaUrl,
      isPrimary
    );

    res.status(201).json({
      success: true,
      message: 'Media saved successfully',
      data: {
        id: media.id,
        mediaType: media.media_type,
        mediaUrl: media.media_url,
        isPrimary: media.is_primary,
        displayOrder: media.display_order,
      },
    });
  })
);

/**
 * @route   DELETE /api/salon/media/:id
 * @desc    Delete media
 * @access  Protected
 */
router.delete(
  '/media/:id',
  validateUUID('id'),
  asyncHandler(async (req, res) => {
    await s3Service.deleteMedia(req.params.id, req.salonId);

    res.status(200).json({
      success: true,
      message: 'Media deleted successfully',
    });
  })
);

/**
 * @route   GET /api/salon/completion
 * @desc    Get profile completion status with upsell stage
 * @access  Protected
 */
router.get(
  '/completion',
  asyncHandler(async (req, res) => {
    const salon = await salonService.findById(req.salonId);
    
    // Get job statistics and photo count for accurate completion calculation
    const jobStats = await salonService.getJobStats(req.salonId);
    const photoCount = await salonService.getPhotoCount(req.salonId);
    
    // Recalculate completion with current data (authoritative)
    const completion = salonService.calculateCompletionPercent(salon, jobStats, photoCount);
    
    // Update stored completion if different (keep DB in sync)
    if (completion !== salon.profile_completion_percent) {
      await salonService.updateCompletionPercent(req.salonId, completion);
    }
    
    // Get missing fields
    const missing = salonService.getMissingFields(salon, photoCount, jobStats);
    
    // Calculate upsell stage
    const upsellStage = salonService.getUpsellStage(completion);

    res.status(200).json({
      success: true,
      data: {
        completionPercent: completion,
        isComplete: completion >= 86, // Complete at 86%+
        missing,
        upsellStage, // 'early' | 'activation' | 'trust' | 'ready'
      },
    });
  })
);

export default router;









