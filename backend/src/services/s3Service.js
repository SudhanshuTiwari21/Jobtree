import { S3Client, PutObjectCommand, DeleteObjectCommand, GetObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { v4 as uuidv4 } from 'uuid';
import config from '../config/index.js';
import db from '../database/connection.js';
import logger from '../utils/logger.js';

class S3Service {
  constructor() {
    this.client = null;
    this.bucket = config.aws.s3Bucket;

    // Initialize S3 client if credentials are available
    if (config.aws.accessKeyId && config.aws.secretAccessKey) {
      this.client = new S3Client({
        region: config.aws.region,
        credentials: {
          accessKeyId: config.aws.accessKeyId,
          secretAccessKey: config.aws.secretAccessKey,
        },
        // Default WHEN_SUPPORTED adds checksum headers to PutObject; presigned URLs
        // then require the uploader to send those headers — plain HTTP PUT from mobile does not.
        requestChecksumCalculation: 'WHEN_REQUIRED',
      });
      logger.info('S3 client initialized');
    } else {
      logger.warn('AWS credentials not configured. S3 service will return mock URLs in development.');
    }
  }

  /**
   * Generate presigned URL for file upload
   * @param {string} salonId - Salon UUID
   * @param {string} mediaType - 'photo' or 'video'
   * @param {string} contentType - MIME type (e.g., 'image/jpeg')
   * @param {string} originalFilename - Original file name
   * @returns {Promise<object>} Presigned URL and file key
   */
  async generateUploadUrl(salonId, mediaType, contentType, originalFilename = '') {
    // Validate media type
    if (!['photo', 'video'].includes(mediaType)) {
      throw new Error('Invalid media type. Must be "photo" or "video".');
    }

    // Get file extension
    const extension = this.getExtension(contentType, originalFilename);
    
    // Generate unique file key
    const fileKey = `salons/${salonId}/${mediaType}s/${uuidv4()}${extension}`;

    // For development without AWS credentials
    if (!this.client) {
      const mockUrl = `https://${this.bucket}.s3.${config.aws.region}.amazonaws.com/${fileKey}`;
      logger.warn(`[DEV MODE] Mock presigned URL generated: ${mockUrl}`);
      
      return {
        uploadUrl: mockUrl,
        fileUrl: mockUrl,
        fileKey,
        expiresIn: config.aws.presignedUrlExpiry,
        method: 'PUT',
        contentType,
      };
    }

    // Presigned PUT must not require headers the mobile client does not send.
    // (Metadata becomes x-amz-meta-* and is part of the signature — missing → 403.)
    // Salon id is already in the object key: salons/{salonId}/...
    const command = new PutObjectCommand({
      Bucket: this.bucket,
      Key: fileKey,
      ContentType: contentType,
    });

    // Generate presigned URL
    const uploadUrl = await getSignedUrl(this.client, command, {
      expiresIn: config.aws.presignedUrlExpiry,
    });

    const fileUrl = `https://${this.bucket}.s3.${config.aws.region}.amazonaws.com/${fileKey}`;

    logger.info(`Presigned upload URL generated for salon ${salonId}: ${fileKey}`);

    return {
      uploadUrl,
      fileUrl,
      fileKey,
      expiresIn: config.aws.presignedUrlExpiry,
      method: 'PUT',
      contentType,
    };
  }

  /**
   * Presigned upload for seeker profile photo (stored on seeker_profiles.profile_photo_url).
   */
  async generateSeekerUploadUrl(seekerId, mediaType, contentType, originalFilename = '') {
    if (!['photo', 'video'].includes(mediaType)) {
      throw new Error('Invalid media type. Must be "photo" or "video".');
    }

    const extension = this.getExtension(contentType, originalFilename);
    const fileKey = `seekers/${seekerId}/${mediaType}s/${uuidv4()}${extension}`;

    if (!this.client) {
      const mockUrl = `https://${this.bucket}.s3.${config.aws.region}.amazonaws.com/${fileKey}`;
      logger.warn(`[DEV MODE] Mock presigned URL generated (seeker): ${mockUrl}`);
      return {
        uploadUrl: mockUrl,
        fileUrl: mockUrl,
        fileKey,
        expiresIn: config.aws.presignedUrlExpiry,
        method: 'PUT',
        contentType,
      };
    }

    const command = new PutObjectCommand({
      Bucket: this.bucket,
      Key: fileKey,
      ContentType: contentType,
    });

    const uploadUrl = await getSignedUrl(this.client, command, {
      expiresIn: config.aws.presignedUrlExpiry,
    });

    const fileUrl = `https://${this.bucket}.s3.${config.aws.region}.amazonaws.com/${fileKey}`;
    logger.info(`Presigned upload URL generated for seeker ${seekerId}: ${fileKey}`);

    return {
      uploadUrl,
      fileUrl,
      fileKey,
      expiresIn: config.aws.presignedUrlExpiry,
      method: 'PUT',
      contentType,
    };
  }

  /**
   * Upload salon media from API process (avoids mobile presigned PUT / S3 policy mismatches).
   * @param {string} salonId
   * @param {string} mediaType - 'photo' | 'video'
   * @param {string} contentType
   * @param {Buffer} buffer
   * @param {{ filename?: string }} opts
   * @returns {Promise<string>} Public file URL
   */
  async uploadSalonBuffer(salonId, mediaType, contentType, buffer, opts = {}) {
    if (!['photo', 'video'].includes(mediaType)) {
      throw new Error('Invalid media type. Must be "photo" or "video".');
    }
    const { filename = '' } = opts;
    const extension = this.getExtension(contentType, filename);
    const fileKey = `salons/${salonId}/${mediaType}s/${uuidv4()}${extension}`;
    const fileUrl = `https://${this.bucket}.s3.${config.aws.region}.amazonaws.com/${fileKey}`;

    if (!this.client) {
      logger.warn(`[DEV MODE] Mock salon buffer upload (no S3): ${fileKey}`);
      return fileUrl;
    }

    const command = new PutObjectCommand({
      Bucket: this.bucket,
      Key: fileKey,
      Body: buffer,
      ContentType: contentType,
    });
    await this.client.send(command);
    logger.info(`Salon buffer uploaded to S3: ${fileKey}`);
    return fileUrl;
  }

  /**
   * Upload seeker media from API process (same credentials as presign path).
   * @returns {Promise<string>} Public file URL
   */
  async uploadSeekerBuffer(seekerId, mediaType, contentType, buffer, opts = {}) {
    if (!['photo', 'video'].includes(mediaType)) {
      throw new Error('Invalid media type. Must be "photo" or "video".');
    }
    const { filename = '' } = opts;
    const extension = this.getExtension(contentType, filename);
    const fileKey = `seekers/${seekerId}/${mediaType}s/${uuidv4()}${extension}`;
    const fileUrl = `https://${this.bucket}.s3.${config.aws.region}.amazonaws.com/${fileKey}`;

    if (!this.client) {
      logger.warn(`[DEV MODE] Mock seeker buffer upload (no S3): ${fileKey}`);
      return fileUrl;
    }

    const command = new PutObjectCommand({
      Bucket: this.bucket,
      Key: fileKey,
      Body: buffer,
      ContentType: contentType,
    });
    await this.client.send(command);
    logger.info(`Seeker buffer uploaded to S3: ${fileKey}`);
    return fileUrl;
  }

  /**
   * KYC / business proof upload (private objects; served via presigned GET).
   * @returns {Promise<string>} Canonical S3 HTTPS URL stored in DB
   */
  async uploadSalonVerificationBuffer(salonId, contentType, buffer, opts = {}) {
    const { filename = '' } = opts;
    const extension = this.getExtension(contentType, filename);
    const fileKey = `salons/${salonId}/verification/${uuidv4()}${extension}`;
    const fileUrl = `https://${this.bucket}.s3.${config.aws.region}.amazonaws.com/${fileKey}`;

    if (!this.client) {
      logger.warn(`[DEV MODE] Mock verification buffer upload (no S3): ${fileKey}`);
      return fileUrl;
    }

    const command = new PutObjectCommand({
      Bucket: this.bucket,
      Key: fileKey,
      Body: buffer,
      ContentType: contentType,
    });
    await this.client.send(command);
    logger.info(`Salon verification doc uploaded to S3: ${fileKey}`);
    return fileUrl;
  }

  /**
   * Generate presigned URL for file download
   * @param {string} fileKey - S3 file key
   * @returns {Promise<string>} Presigned download URL
   */
  async generateDownloadUrl(fileKey) {
    if (!this.client) {
      return `https://${this.bucket}.s3.${config.aws.region}.amazonaws.com/${fileKey}`;
    }

    const command = new GetObjectCommand({
      Bucket: this.bucket,
      Key: fileKey,
    });

    return getSignedUrl(this.client, command, {
      expiresIn: config.aws.presignedUrlExpiry,
    });
  }

  /**
   * Presigned GET for URLs stored in DB (Image.network cannot use IAM on private buckets).
   * @param {string|null|undefined} url
   * @returns {Promise<string>}
   */
  async presignGetUrl(url) {
    if (!url || typeof url !== 'string' || url.length === 0) return '';
    if (!this.client) return url;
    try {
      const key = this.extractFileKey(url);
      if (!key || key === url) return url;
      return await this.generateDownloadUrl(key);
    } catch (e) {
      logger.warn(`presignGetUrl failed: ${e.message}`);
      return url;
    }
  }

  /** @param {string[]} urls */
  async presignGetUrls(urls) {
    if (!Array.isArray(urls)) return [];
    return Promise.all(urls.map((u) => this.presignGetUrl(u)));
  }

  /**
   * Save media record to database
   * @param {string} salonId - Salon UUID
   * @param {string} mediaType - 'photo' or 'video'
   * @param {string} mediaUrl - S3 file URL
   * @param {boolean} isPrimary - Is this the primary media
   * @returns {Promise<object>} Media record
   */
  async saveMediaRecord(salonId, mediaType, mediaUrl, isPrimary = false) {
    // If setting as primary, unset existing primary
    if (isPrimary) {
      await db.query(
        `UPDATE salon_media 
         SET is_primary = false 
         WHERE salon_id = $1 AND media_type = $2`,
        [salonId, mediaType]
      );
    }

    // Get next display order
    const orderResult = await db.query(
      `SELECT COALESCE(MAX(display_order), 0) + 1 as next_order 
       FROM salon_media WHERE salon_id = $1`,
      [salonId]
    );
    const displayOrder = orderResult.rows[0].next_order;

    // Insert media record
    const result = await db.query(
      `INSERT INTO salon_media (salon_id, media_type, media_url, is_primary, display_order)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING *`,
      [salonId, mediaType, mediaUrl, isPrimary, displayOrder]
    );

    logger.info(`Media record saved for salon ${salonId}: ${mediaType}`);

    return result.rows[0];
  }

  /**
   * Delete media from S3 and database
   * @param {string} mediaId - Media record UUID
   * @param {string} salonId - Salon UUID (for authorization)
   * @returns {Promise<boolean>} Deletion success
   */
  async deleteMedia(mediaId, salonId) {
    // Get media record
    const result = await db.query(
      'SELECT * FROM salon_media WHERE id = $1 AND salon_id = $2',
      [mediaId, salonId]
    );

    if (result.rows.length === 0) {
      throw new Error('Media not found');
    }

    const media = result.rows[0];

    // Delete from S3
    if (this.client && media.media_url) {
      try {
        const fileKey = this.extractFileKey(media.media_url);
        const command = new DeleteObjectCommand({
          Bucket: this.bucket,
          Key: fileKey,
        });
        await this.client.send(command);
        logger.info(`Deleted from S3: ${fileKey}`);
      } catch (error) {
        logger.warn(`Failed to delete from S3: ${error.message}`);
        // Continue with database deletion
      }
    }

    // Delete from database
    await db.query('DELETE FROM salon_media WHERE id = $1', [mediaId]);

    logger.info(`Media record deleted: ${mediaId}`);

    return true;
  }

  /**
   * Get file extension from content type or filename
   * @param {string} contentType - MIME type
   * @param {string} filename - Original filename
   * @returns {string} File extension with dot
   */
  getExtension(contentType, filename = '') {
    // Try to get from filename first
    if (filename) {
      const match = filename.match(/\.[^.]+$/);
      if (match) return match[0].toLowerCase();
    }

    // Fall back to content type
    const mimeToExt = {
      'image/jpeg': '.jpg',
      'image/jpg': '.jpg',
      'image/png': '.png',
      'image/gif': '.gif',
      'image/webp': '.webp',
      'image/heic': '.heic',
      'image/heif': '.heif',
      'application/pdf': '.pdf',
      'video/mp4': '.mp4',
      'video/quicktime': '.mov',
      'video/webm': '.webm',
    };

    return mimeToExt[contentType] || '.bin';
  }

  /**
   * Extract file key from S3 URL
   * @param {string} url - S3 URL
   * @returns {string} File key
   */
  extractFileKey(url) {
    const regex = new RegExp(`https://${this.bucket}.s3.[^/]+.amazonaws.com/(.+)`);
    const match = url.match(regex);
    return match ? match[1] : url;
  }
}

export default new S3Service();














