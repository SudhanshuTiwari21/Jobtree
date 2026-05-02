import authService from '../services/authService.js';
import salonService from '../services/salonService.js';
import seekerService from '../services/seekerService.js';
import { ApiError } from './errorHandler.js';
import logger from '../utils/logger.js';

/**
 * JWT Authentication Middleware
 * Extracts and verifies JWT token from Authorization header
 */
export const authenticate = async (req, res, next) => {
  try {
    // Get token from header
    const authHeader = req.headers.authorization;
    
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      throw new ApiError(401, 'Access token required');
    }

    const token = authHeader.split(' ')[1];
    
    if (!token) {
      throw new ApiError(401, 'Access token required');
    }

    // Verify token
    const decoded = authService.verifyToken(token);
    
    if (!decoded) {
      throw new ApiError(401, 'Invalid or expired token');
    }

    if (decoded.type !== 'access') {
      throw new ApiError(401, 'Invalid token type');
    }

    // Get salon from database
    const salon = await salonService.findById(decoded.salonId);
    
    if (!salon) {
      throw new ApiError(401, 'Salon not found');
    }

    // Attach salon to request
    req.salon = salon;
    req.salonId = salon.id;

    next();
  } catch (error) {
    if (error instanceof ApiError) {
      return next(error);
    }
    
    logger.error('Authentication error:', error);
    return next(new ApiError(401, 'Authentication failed'));
  }
};

/**
 * Optional Authentication Middleware
 * Attaches salon if token is valid, but doesn't require authentication
 */
export const optionalAuth = async (req, res, next) => {
  try {
    const authHeader = req.headers.authorization;
    
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return next(); // Continue without auth
    }

    const token = authHeader.split(' ')[1];
    
    if (!token) {
      return next();
    }

    const decoded = authService.verifyToken(token);
    
    if (decoded && decoded.type === 'access') {
      const salon = await salonService.findById(decoded.salonId);
      if (salon) {
        req.salon = salon;
        req.salonId = salon.id;
      }
    }

    next();
  } catch (error) {
    // Log but don't fail - optional auth
    logger.warn('Optional auth failed:', error.message);
    next();
  }
};

/**
 * Require verified salon
 * Use after authenticate middleware
 */
export const requireVerified = (req, res, next) => {
  if (!req.salon) {
    return next(new ApiError(401, 'Authentication required'));
  }

  if (req.salon.verification_status !== 'verified') {
    return next(new ApiError(403, 'Salon verification required'));
  }

  next();
};

/**
 * JWT Authentication Middleware for Job Seekers
 * Extracts and verifies JWT token, expects role='seeker'
 */
export const authenticateSeeker = async (req, res, next) => {
  try {
    const authHeader = req.headers.authorization;

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      throw new ApiError(401, 'Access token required');
    }

    const token = authHeader.split(' ')[1];
    if (!token) throw new ApiError(401, 'Access token required');

    const decoded = authService.verifyToken(token);
    if (!decoded) throw new ApiError(401, 'Invalid or expired token');
    if (decoded.type !== 'access') throw new ApiError(401, 'Invalid token type');
    if (decoded.role !== 'seeker') throw new ApiError(401, 'This endpoint requires a seeker account');

    const seeker = await seekerService.findById(decoded.seekerId);
    if (!seeker) throw new ApiError(401, 'Seeker not found');

    req.seeker = seeker;
    req.seekerId = seeker.id;

    next();
  } catch (error) {
    if (error instanceof ApiError) return next(error);
    logger.error('Seeker authentication error:', error);
    return next(new ApiError(401, 'Authentication failed'));
  }
};

/**
 * Accept either owner (salon) or seeker JWT; set req.userId and req.userType for device/notification APIs.
 * req.userId = salon.id (owner) or seeker.id (seeker), req.userType = 'owner' | 'seeker'
 */
export const authenticateOwnerOrSeeker = async (req, res, next) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      throw new ApiError(401, 'Access token required');
    }
    const token = authHeader.split(' ')[1];
    if (!token) throw new ApiError(401, 'Access token required');

    const decoded = authService.verifyToken(token);
    if (!decoded || decoded.type !== 'access') {
      throw new ApiError(401, 'Invalid or expired token');
    }

    if (decoded.role === 'salon') {
      const salon = await salonService.findById(decoded.salonId);
      if (!salon) throw new ApiError(401, 'Salon not found');
      req.salon = salon;
      req.salonId = salon.id;
      req.userId = salon.id;
      req.userType = 'owner';
      return next();
    }
    if (decoded.role === 'seeker') {
      const seeker = await seekerService.findById(decoded.seekerId);
      if (!seeker) throw new ApiError(401, 'Seeker not found');
      req.seeker = seeker;
      req.seekerId = seeker.id;
      req.userId = seeker.id;
      req.userType = 'seeker';
      return next();
    }
    throw new ApiError(401, 'Invalid token role');
  } catch (error) {
    if (error instanceof ApiError) return next(error);
    logger.error('Owner/Seeker auth error:', error);
    return next(new ApiError(401, 'Authentication failed'));
  }
};

export default {
  authenticate,
  optionalAuth,
  requireVerified,
  authenticateSeeker,
  authenticateOwnerOrSeeker,
};














