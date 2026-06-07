import http from 'http';
import express from 'express';
import compression from 'compression';
import morgan from 'morgan';
import config from './config/index.js';
import logger from './utils/logger.js';
import { securityMiddleware, rateLimiter } from './middleware/security.js';
import { errorHandler, notFoundHandler } from './middleware/errorHandler.js';
import routes from './routes/index.js';
import db from './database/connection.js';
import interviewReminderCron from './jobs/interviewReminderCron.js';
import { attachChatSocketServer } from './websocket/chatSocket.js';

const app = express();
let httpServerRef = null;
app.set('trust proxy', 1);

// Middleware
app.use(compression()); // Compress responses
app.use(express.json({ limit: '10mb' })); // Parse JSON bodies
app.use(express.urlencoded({ extended: true, limit: '10mb' })); // Parse URL-encoded bodies

// Security middleware
app.use(securityMiddleware);

// Logging middleware
if (config.env === 'development') {
  app.use(morgan('dev'));
} else {
  app.use(
    morgan('combined', {
      stream: {
        write: (message) => logger.info(message.trim()),
      },
    })
  );
}

// Rate limiting
app.use('/api/', rateLimiter);

// API routes
app.use('/api', routes);

// Root endpoint
app.get('/', (req, res) => {
  res.json({
    success: true,
    message: 'Welcome to Jobtree API',
    version: '1.0.0',
    documentation: '/api/health',
    endpoints: {
      auth: {
        sendOtp: 'POST /api/auth/send-otp',
        resendOtp: 'POST /api/auth/resend-otp',
        verifyOtp: 'POST /api/auth/verify-otp',
        refresh: 'POST /api/auth/refresh',
        logout: 'POST /api/auth/logout',
      },
      salon: {
        getProfile: 'GET /api/salon/me',
        updateProfile: 'PATCH /api/salon/profile',
        mediaPresign: 'POST /api/salon/media/presign',
        mediaUpload: 'POST /api/salon/media/upload',
        saveMedia: 'POST /api/salon/media',
        deleteMedia: 'DELETE /api/salon/media/:id',
        completion: 'GET /api/salon/completion',
      },
      jobs: {
        create: 'POST /api/jobs',
        getMyJobs: 'GET /api/jobs/my-jobs',
        getById: 'GET /api/jobs/:id',
        update: 'PATCH /api/jobs/:id',
        delete: 'DELETE /api/jobs/:id',
        completion: 'GET /api/jobs/:id/completion',
        search: 'GET /api/jobs/search (public)',
        publicView: 'GET /api/jobs/public/:id (public)',
      },
    },
  });
});

// 404 handler
app.use(notFoundHandler);

// Error handler (must be last)
app.use(errorHandler);

// Start server
const startServer = async () => {
  try {
    // Check database connection
    const dbConnected = await db.checkConnection();
    if (!dbConnected) {
      logger.error('Failed to connect to database. Server will start but database operations will fail.');
    } else {
      logger.info('✓ Database connection established');
    }

    const PORT = config.port;

    const httpServer = http.createServer(app);
    httpServerRef = httpServer;
    attachChatSocketServer(httpServer);

    httpServer.listen(PORT, () => {
      logger.info(`🚀 Server running on port ${PORT} in ${config.env} mode`);
      logger.info(`📡 API available at http://localhost:${PORT}/api`);
      logger.info(`💬 WebSocket chat at ws://localhost:${PORT}/ws/chat`);
      logger.info(`❤️  Health check: http://localhost:${PORT}/api/health`);
      interviewReminderCron.start();
      console.log(`
╔══════════════════════════════════════════════════════════════╗
║                    JOBTREE API SERVER                        ║
╠══════════════════════════════════════════════════════════════╣
║  Status: Running                                             ║
║  Port: ${PORT}                                                   ║
║  Environment: ${config.env.padEnd(45)}║
║  Database: ${dbConnected ? 'Connected ✓' : 'Not connected ✗'.padEnd(48)}║
╠══════════════════════════════════════════════════════════════╣
║  Auth Endpoints:                                             ║
║  • POST /api/auth/send-otp      - Send OTP                   ║
║  • POST /api/auth/verify-otp    - Verify OTP & Login         ║
║                                                              ║
║  Salon Endpoints:                                            ║
║  • GET  /api/salon/me           - Get Profile                ║
║  • PATCH /api/salon/profile     - Update Profile             ║
║                                                              ║
║  Job Endpoints:                                              ║
║  • POST /api/jobs               - Create Job                 ║
║  • GET  /api/jobs/my-jobs       - My Jobs                    ║
║  • PATCH /api/jobs/:id          - Update Job                 ║
║  • GET  /api/jobs/search        - Browse Jobs (Public)       ║
╚══════════════════════════════════════════════════════════════╝
      `);
    });
  } catch (error) {
    logger.error('Failed to start server:', error);
    process.exit(1);
  }
};

startServer();

// Graceful shutdown
const gracefulShutdown = async (signal) => {
  logger.info(`${signal} signal received: closing HTTP server`);
  try {
    interviewReminderCron.stop();
    if (httpServerRef) {
      await new Promise((resolve, reject) => {
        httpServerRef.close((err) => (err ? reject(err) : resolve()));
      });
    }
    await db.closePool();
    logger.info('Database connections closed');
  } catch (error) {
    logger.error('Error closing database:', error);
  }
  process.exit(0);
};

process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));

export default app;
