/**
 * Notification Triggers
 * 
 * Helper functions to create notifications when specific events occur.
 * These should be called from relevant services (jobService, etc.)
 * 
 * IMPORTANT: Only for job owners (salon owners), not job seekers
 */

import notificationService from '../services/notificationService.js';
import logger from './logger.js';

/**
 * Trigger notification when a candidate applies to a job
 * @param {string} salonId - Salon UUID
 * @param {string} jobId - Job UUID
 * @param {string} city - Job city
 */
export async function notifyCandidateApplied(salonId, jobId, city) {
  try {
    await notificationService.createNotification(
      salonId,
      'CANDIDATE_APPLIED',
      'New candidate applied',
      `A candidate has applied for your job in ${city}`,
      `/candidates/${jobId}`
    );
  } catch (error) {
    logger.error('Error creating candidate applied notification:', error);
  }
}

/**
 * Trigger notification when a candidate replies to a message
 * @param {string} salonId - Salon UUID
 * @param {string} candidateId - Candidate UUID or phone
 * @param {string} candidateName - Candidate name
 */
export async function notifyCandidateReplied(salonId, candidateId, candidateName) {
  try {
    await notificationService.createNotification(
      salonId,
      'CANDIDATE_REPLIED',
      'Candidate replied',
      `You received a new message from ${candidateName}`,
      `/chat/${candidateId}`
    );
  } catch (error) {
    logger.error('Error creating candidate replied notification:', error);
  }
}

/**
 * Trigger interview reminder notification
 * @param {string} salonId - Salon UUID
 * @param {string} interviewId - Interview UUID
 * @param {string} time - Interview time (formatted)
 */
export async function notifyInterviewReminder(salonId, interviewId, time) {
  try {
    await notificationService.createNotification(
      salonId,
      'INTERVIEW_REMINDER',
      'Interview reminder',
      `Interview scheduled at ${time}`,
      `/interviews/${interviewId}`
    );
  } catch (error) {
    logger.error('Error creating interview reminder notification:', error);
  }
}

/**
 * Trigger job performance tip notification
 * @param {string} salonId - Salon UUID
 * @param {string} tip - Tip message
 */
export async function notifyJobPerformanceTip(salonId, tip) {
  try {
    await notificationService.createNotification(
      salonId,
      'JOB_PERFORMANCE_TIP',
      'Improve job responses',
      tip, // e.g., "Jobs with salary details get more calls"
      null
    );
  } catch (error) {
    logger.error('Error creating job performance tip notification:', error);
  }
}

/**
 * Trigger profile incomplete notification
 * @param {string} salonId - Salon UUID
 * @param {string} suggestion - Suggestion message
 */
export async function notifyProfileIncomplete(salonId, suggestion) {
  try {
    await notificationService.createNotification(
      salonId,
      'PROFILE_INCOMPLETE',
      'Complete your profile',
      suggestion, // e.g., "Add salon photos to attract better candidates"
      '/profile'
    );
  } catch (error) {
    logger.error('Error creating profile incomplete notification:', error);
  }
}

/**
 * Trigger account alert notification
 * @param {string} salonId - Salon UUID
 * @param {string} message - Alert message
 */
export async function notifyAccountAlert(salonId, message) {
  try {
    await notificationService.createNotification(
      salonId,
      'ACCOUNT_ALERT',
      'Account activity',
      message, // e.g., "New login detected on your account"
      '/settings'
    );
  } catch (error) {
    logger.error('Error creating account alert notification:', error);
  }
}

/**
 * Trigger promotion notification (only if user has opted in)
 * @param {string} salonId - Salon UUID
 * @param {string} title - Promotion title
 * @param {string} message - Promotion message
 * @param {string} deepLink - Optional deep link
 */
export async function notifyPromotion(salonId, title, message, deepLink = null) {
  try {
    await notificationService.createNotification(
      salonId,
      'PROMOTION',
      title, // e.g., "Special offer"
      message, // e.g., "Boost your job visibility with featured listing"
      deepLink
    );
  } catch (error) {
    logger.error('Error creating promotion notification:', error);
  }
}





