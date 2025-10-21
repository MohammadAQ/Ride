import { Router } from 'express';
import {
  createTripHandler,
  deleteTripHandler,
  getMyTripsHandler,
  getTripsHandler,
  updateTripHandler,
} from '../controllers/trips.controller';
import { authenticate } from '../middlewares/auth';

const router = Router();

router.get('/', getTripsHandler);
router.get('/mine', authenticate, getMyTripsHandler);
router.post('/', authenticate, createTripHandler);
router.patch('/:id', authenticate, updateTripHandler);
router.delete('/:id', authenticate, deleteTripHandler);

export default router;
