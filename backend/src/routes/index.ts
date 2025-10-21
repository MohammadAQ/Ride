import { Router } from 'express';
import tripsRouter from './trips.routes';

const router = Router();

router.get('/health', (_req, res) => {
  res.json({ status: 'ok' });
});

router.use('/trips', tripsRouter);

export default router;
