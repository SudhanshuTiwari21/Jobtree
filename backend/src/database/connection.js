import pg from 'pg';
import config from '../config/index.js';
import logger from '../utils/logger.js';

const { Pool } = pg;

const createPool = () => {
  const poolConfig = config.database.url
    ? {
        // Neon pooled connection string
        connectionString: config.database.url,
        ssl: {
          rejectUnauthorized: config.env === 'production',
        },
      }
    : {
        // Individual connection params
        host: config.database.host,
        port: config.database.port,
        database: config.database.name,
        user: config.database.user,
        password: config.database.password,
        ssl: config.database.ssl
          ? { rejectUnauthorized: config.env === 'production' }
          : false,
      };

  // Connection pool settings optimized for Neon
  return new Pool({
    ...poolConfig,
    min: config.database.poolMin,
    max: config.database.poolMax,
    connectionTimeoutMillis: 15000,
    idleTimeoutMillis: 30000,
    keepAlive: true,
    keepAliveInitialDelayMillis: 10000,
    statement_timeout: 30000,
    application_name: 'jobtree-backend',
  });
};

const pool = createPool();

// Pool event handlers
pool.on('error', (err, client) => {
  logger.error('Unexpected error on idle database client', err);
});

pool.on('connect', (client) => {
  logger.debug('New database connection established');
  
  // Set session parameters for Neon
  client.query('SET timezone = \'Asia/Kolkata\'').catch(() => {});
});

pool.on('remove', () => {
  logger.debug('Database connection removed from pool');
});

export const query = async (text, params) => {
  const start = Date.now();
  try {
    const result = await pool.query(text, params);
    const duration = Date.now() - start;
    
    // Log slow queries (> 1000ms)
    if (duration > 1000) {
      logger.warn(`Slow query (${duration}ms): ${text.substring(0, 100)}...`);
    } else {
      logger.debug(`Query: ${text.substring(0, 50)}... Duration: ${duration}ms Rows: ${result.rowCount}`);
    }
    
    return result;
  } catch (error) {
    const duration = Date.now() - start;
    logger.error(`Query error (${duration}ms): ${error.message}`, {
      query: text.substring(0, 200),
      code: error.code,
    });
    throw error;
  }
};

/**
 * Get a client from the pool for transaction support
 * @returns {Promise<object>} Pool client
 */
export const getClient = async () => {
  const client = await pool.connect();
  const originalQuery = client.query.bind(client);
  const originalRelease = client.release.bind(client);

  // Track query timeout
  const timeout = setTimeout(() => {
    logger.error('A client has been checked out for more than 30 seconds!');
  }, 30000);

  // Override release to clear timeout
  client.release = () => {
    clearTimeout(timeout);
    return originalRelease();
  };

  return client;
};

/**
 * Execute a transaction
 * @param {Function} callback - Transaction callback
 * @returns {Promise<any>} Transaction result
 */
export const transaction = async (callback) => {
  const client = await getClient();
  try {
    await client.query('BEGIN');
    const result = await callback(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
};

/**
 * Check database connection and get info
 * @returns {Promise<object>} Connection status and info
 */
export const checkConnection = async () => {
  try {
    const result = await query(`
      SELECT 
        NOW() as server_time,
        current_database() as database,
        version() as version
    `);
    
    const info = result.rows[0];
    logger.info(`Database connected: ${info.database}`);
    logger.info(`PostgreSQL version: ${info.version.split(' ')[0]} ${info.version.split(' ')[1]}`);
    
    return {
      connected: true,
      database: info.database,
      serverTime: info.server_time,
      version: info.version,
    };
  } catch (error) {
    logger.error('Database connection failed:', error.message);
    return {
      connected: false,
      error: error.message,
    };
  }
};

/**
 * Get pool statistics
 * @returns {object} Pool stats
 */
export const getPoolStats = () => ({
  totalConnections: pool.totalCount,
  idleConnections: pool.idleCount,
  waitingClients: pool.waitingCount,
});

/**
 * Close all pool connections
 */
export const closePool = async () => {
  await pool.end();
  logger.info('Database pool closed');
};

/**
 * Health check for database
 * @returns {Promise<object>} Health status
 */
export const healthCheck = async () => {
  const start = Date.now();
  try {
    await query('SELECT 1');
    return {
      status: 'healthy',
      latency: Date.now() - start,
      pool: getPoolStats(),
    };
  } catch (error) {
    return {
      status: 'unhealthy',
      error: error.message,
      latency: Date.now() - start,
    };
  }
};

export default {
  query,
  getClient,
  transaction,
  checkConnection,
  closePool,
  getPoolStats,
  healthCheck,
  pool,
};
