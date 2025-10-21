import { NextFunction, Request, Response } from 'express';
import { ZodError } from 'zod';
import AppError from '../utils/appError';
import logger from '../utils/logger';

// eslint-disable-next-line @typescript-eslint/no-unused-vars
export const errorHandler = (err: unknown, req: Request, res: Response, _next: NextFunction): void => {
  if (err instanceof ZodError) {
    const issues = err.issues.map((issue) => ({
      path: issue.path.join('.'),
      message: issue.message,
    }));

    res.status(400).json({
      message: 'Validation failed',
      errors: issues,
    });
    return;
  }

  if (err instanceof AppError) {
    if (err.statusCode >= 500) {
      logger.error({ err }, err.message);
    }

    res.status(err.statusCode).json({
      message: err.message,
    });
    return;
  }

  logger.error({ err }, 'Unexpected error occurred');
  res.status(500).json({ message: 'Internal server error' });
};
