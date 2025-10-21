import cors from 'cors';
import { Express } from 'express';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import { env } from '../config/env.js';
import AppError from '../utils/appError.js';

export const applySecurityMiddlewares = (app: Express): void => {
  app.use(helmet());

  const allowedOrigins = new Set(env.corsOrigins);

  app.use(
    cors({
      origin: (origin, callback) => {
        if (allowedOrigins.size === 0 || !origin || allowedOrigins.has(origin)) {
          callback(null, true);
          return;
        }

        callback(new AppError('Not allowed by CORS', 403));
      },
      credentials: true,
    }),
  );

  app.use(
    rateLimit({
      windowMs: 15 * 60 * 1000,
      max: 100,
      standardHeaders: true,
      legacyHeaders: false,
    }),
  );
};
