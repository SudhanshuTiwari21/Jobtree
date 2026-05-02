import cron from 'node-cron';
import interviewReminderService from '../services/interviewReminderService.js';
import logger from '../utils/logger.js';

/** Cron schedule: every 10 minutes */
const SCHEDULE = '*/10 * * * *';

let task = null;

/**
 * Start the interview reminder cron job.
 * Runs every 10 minutes; does not block the main thread.
 */
function start() {
  if (task) {
    logger.warn('Interview reminder cron already started');
    return;
  }
  task = cron.schedule(SCHEDULE, async () => {
    await interviewReminderService.run();
  });
  logger.info('Interview reminder cron started (every 10 minutes)');
}

/**
 * Stop the interview reminder cron job.
 */
function stop() {
  if (task) {
    task.stop();
    task = null;
    logger.info('Interview reminder cron stopped');
  }
}

export default { start, stop };
