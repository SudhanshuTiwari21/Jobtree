import express from 'express';
import authRoutes from './authRoutes.js';
import salonRoutes from './salonRoutes.js';
import jobRoutes from './jobRoutes.js';
import ownerApplicationRoutes from './ownerApplicationRoutes.js';
import callRoutes from './callRoutes.js';
import notificationRoutes from './notificationRoutes.js';
import supportRoutes from './supportRoutes.js';
import seekerRoutes from './seekerRoutes.js';
import deviceRoutes from './deviceRoutes.js';
import chatRoutes from './chatRoutes.js';
import adminRoutes from './adminRoutes.js';
import db from '../database/connection.js';

const router = express.Router();

// Health check endpoint (basic)
router.get('/health', (req, res) => {
  res.status(200).json({
    success: true,
    message: 'Jobtree API is running',
    timestamp: new Date().toISOString(),
    environment: process.env.NODE_ENV || 'development',
    version: '1.0.0',
  });
});

// Detailed health check with database status
router.get('/health/detailed', async (req, res) => {
  const dbHealth = await db.healthCheck();
  const isHealthy = dbHealth.status === 'healthy';

  res.status(isHealthy ? 200 : 503).json({
    success: isHealthy,
    timestamp: new Date().toISOString(),
    environment: process.env.NODE_ENV || 'development',
    version: '1.0.0',
    services: {
      api: {
        status: 'healthy',
      },
      database: {
        status: dbHealth.status,
        latency: `${dbHealth.latency}ms`,
        pool: dbHealth.pool,
        ...(dbHealth.error && { error: dbHealth.error }),
      },
    },
  });
});

// API routes
router.use('/auth', authRoutes);
router.use('/salon', salonRoutes);
router.use('/jobs', jobRoutes);
router.use('/owner', ownerApplicationRoutes);
router.use('/calls', callRoutes);
router.use('/notifications', notificationRoutes);
router.use('/support', supportRoutes);
router.use('/seeker', seekerRoutes);
router.use('/device', deviceRoutes);
router.use('/chat', chatRoutes);
router.use('/admin', adminRoutes);

export default router;
