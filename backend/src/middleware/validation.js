import { body, param, query, validationResult } from 'express-validator';
import { ApiError } from './errorHandler.js';

/**
 * Validation result middleware
 */
export const validate = (req, res, next) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    const errorMessages = errors.array().map((error) => ({
      field: error.path || error.param,
      message: error.msg,
    }));

    throw new ApiError(400, 'Validation failed', true, JSON.stringify(errorMessages));
  }
  next();
};

/**
 * Phone number validation rules
 */
export const validatePhoneNumber = [
  body('phoneNumber')
    .trim()
    .notEmpty()
    .withMessage('Phone number is required')
    .matches(/^\d{10}$/)
    .withMessage('Phone number must be exactly 10 digits'),
  body('countryCode')
    .optional()
    .trim()
    .matches(/^\+\d{1,4}$/)
    .withMessage('Invalid country code format (e.g., +91)'),
  /** Android SMS Retriever: 11-char app hash from client (sms_autofill). Optional. */
  body('smsAppHash')
    .optional({ values: 'falsy' })
    .trim()
    .isLength({ min: 11, max: 11 })
    .withMessage('smsAppHash must be exactly 11 characters')
    .matches(/^[A-Za-z0-9+/=-]{11}$/)
    .withMessage('Invalid smsAppHash format'),
  validate,
];

/**
 * OTP verification validation rules
 */
export const validateOTP = [
  body('phoneNumber')
    .trim()
    .notEmpty()
    .withMessage('Phone number is required')
    .matches(/^\d{10}$/)
    .withMessage('Phone number must be exactly 10 digits'),
  body('otp')
    .trim()
    .notEmpty()
    .withMessage('OTP is required')
    .isLength({ min: 6, max: 6 })
    .withMessage('OTP must be exactly 6 digits')
    .isNumeric()
    .withMessage('OTP must contain only numbers'),
  body('countryCode')
    .optional()
    .trim()
    .matches(/^\+\d{1,4}$/)
    .withMessage('Invalid country code format'),
  validate,
];

/**
 * Salon profile update validation rules
 */
export const validateSalonProfileUpdate = [
  body('salonName')
    .optional()
    .trim()
    .isLength({ min: 1, max: 100 })
    .withMessage('Salon name must be between 1 and 100 characters'),
  body('ownerName')
    .optional()
    .trim()
    .isLength({ min: 1, max: 100 })
    .withMessage('Owner name must be between 1 and 100 characters'),
  body('city')
    .optional()
    .trim()
    .isLength({ min: 1, max: 100 })
    .withMessage('City must be between 1 and 100 characters'),
  body('area')
    .optional()
    .trim()
    .isLength({ min: 1, max: 200 })
    .withMessage('Area must be between 1 and 200 characters'),
  body('fullAddress')
    .optional()
    .trim()
    .isLength({ min: 1, max: 500 })
    .withMessage('Address must be between 1 and 500 characters'),
  body('latitude')
    .optional()
    .isFloat({ min: -90, max: 90 })
    .withMessage('Invalid latitude'),
  body('longitude')
    .optional()
    .isFloat({ min: -180, max: 180 })
    .withMessage('Invalid longitude'),
  validate,
];

/**
 * Media upload presign validation rules
 */
export const validateMediaPresign = [
  body('mediaType')
    .trim()
    .notEmpty()
    .withMessage('Media type is required')
    .isIn(['photo', 'video'])
    .withMessage('Media type must be "photo" or "video"'),
  body('contentType')
    .trim()
    .notEmpty()
    .withMessage('Content type is required')
    .matches(/^(image|video)\/[a-z0-9]+$/i)
    .withMessage('Invalid content type format'),
  body('filename')
    .optional()
    .trim()
    .isLength({ max: 255 })
    .withMessage('Filename too long'),
  validate,
];

/**
 * Media save validation rules
 */
export const validateMediaSave = [
  body('mediaType')
    .trim()
    .notEmpty()
    .withMessage('Media type is required')
    .isIn(['photo', 'video'])
    .withMessage('Media type must be "photo" or "video"'),
  body('mediaUrl')
    .trim()
    .notEmpty()
    .withMessage('Media URL is required')
    .isURL()
    .withMessage('Invalid media URL'),
  body('isPrimary')
    .optional()
    .isBoolean()
    .withMessage('isPrimary must be a boolean'),
  validate,
];

/**
 * UUID parameter validation
 */
export const validateUUID = (paramName = 'id') => [
  param(paramName)
    .isUUID()
    .withMessage(`Invalid ${paramName} format`),
  validate,
];

/**
 * Refresh token validation
 */
export const validateRefreshToken = [
  body('refreshToken')
    .trim()
    .notEmpty()
    .withMessage('Refresh token is required'),
  validate,
];
