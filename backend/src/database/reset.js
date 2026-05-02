import db from './connection.js';
import logger from '../utils/logger.js';

/**
 * Database Reset Script
 * Drops all tables and recreates them (USE WITH CAUTION!)
 */

const dropTables = `
  DROP TABLE IF EXISTS refresh_tokens CASCADE;
  DROP TABLE IF EXISTS salon_verification_docs CASCADE;
  DROP TABLE IF EXISTS salon_policies CASCADE;
  DROP TABLE IF EXISTS salon_media CASCADE;
  DROP TABLE IF EXISTS otp_requests CASCADE;
  DROP TABLE IF EXISTS salons CASCADE;
  
  DROP FUNCTION IF EXISTS update_updated_at_column CASCADE;
`;

async function resetDatabase() {
  // Safety check
  if (process.env.NODE_ENV === 'production') {
    logger.error('Cannot reset database in production!');
    process.exit(1);
  }

  logger.warn('⚠️  Resetting database - this will delete ALL data!');
  
  try {
    // Check database connection
    const connected = await db.checkConnection();
    if (!connected) {
      throw new Error('Cannot connect to database');
    }

    // Drop all tables
    logger.info('Dropping existing tables...');
    await db.query(dropTables);
    logger.info('✓ All tables dropped');

    logger.info('Database reset complete. Run "npm run db:migrate" to recreate tables.');
  } catch (error) {
    logger.error('Reset failed:', error.message);
    throw error;
  } finally {
    await db.closePool();
  }
}

// Run reset if executed directly
resetDatabase().catch((error) => {
  console.error('Reset error:', error);
  process.exit(1);
});

export { resetDatabase };














