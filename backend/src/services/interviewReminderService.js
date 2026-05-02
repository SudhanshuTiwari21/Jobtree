import db from '../database/connection.js';
import pushService from './pushService.js';
import logger from '../utils/logger.js';

/**
 * Interview Reminder Service
 * Finds applications where interview time has passed but not marked completed,
 * sends push reminder to owner, then marks reminder as sent.
 * Called by cron every 10 minutes.
 */
async function run() {
  try {
    const result = await db.query(
      `SELECT a.id AS application_id, a.job_id, j.salon_id,
              sp.full_name AS candidate_name
       FROM applications a
       JOIN jobs j ON a.job_id = j.id
       JOIN seeker_profiles sp ON a.seeker_id = sp.id
       WHERE a.interview_status = 'scheduled'
         AND a.interview_scheduled_at < NOW()
         AND (a.interview_reminder_sent = false OR a.interview_reminder_sent IS NULL)`
    );

    const rows = result.rows || [];
    if (rows.length === 0) return;

    for (const row of rows) {
      try {
        const candidateName = row.candidate_name || 'the candidate';
        pushService.sendNotification(row.salon_id, 'owner', {
          type: 'interview_reminder',
          title: 'Interview Reminder',
          body: `Did you complete the interview with ${candidateName}? Update the status.`,
          data: {
            deepLink: `app://owner/job/${row.job_id}`,
            jobId: row.job_id,
            applicationId: String(row.application_id),
          },
        });

        await db.query(
          `UPDATE applications SET interview_reminder_sent = true, updated_at = CURRENT_TIMESTAMP WHERE id = $1`,
          [row.application_id]
        );

        logger.info(`Interview reminder sent → ${row.application_id}`);
      } catch (err) {
        logger.error(`Interview reminder failed for application ${row.application_id}:`, err.message);
        // Continue with next application; do not rethrow
      }
    }
  } catch (error) {
    logger.error('Interview reminder service run error:', error.message);
    // Do not throw — cron must not crash the process
  }
}

export default { run };
