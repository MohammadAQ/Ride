import { Router } from 'express';
import {
  createTripHandler,
  deleteTripHandler,
  getMyTripsHandler,
  getTripsHandler,
  updateTripHandler,
} from '../controllers/trips.controller.js';
import { authenticate } from '../middlewares/auth.js';
import logger from '../utils/logger.js';

const router = Router();

router.use((req, res, next) => {
  const start = Date.now();

  res.on('finish', () => {
    logger.info(
      {
        method: req.method,
        url: req.originalUrl,
        statusCode: res.statusCode,
        durationMs: Date.now() - start,
      },
      'Handled trips request',
    );
  });

  next();
});

router.get('/', getTripsHandler);
router.get('/mine', authenticate, getMyTripsHandler);
router.post('/', authenticate, createTripHandler);
router.patch('/:id', authenticate, updateTripHandler);
router.delete('/:id', authenticate, deleteTripHandler);

export default router;
