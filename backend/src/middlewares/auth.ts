import { NextFunction, Request, Response } from 'express';
import AppError from '../utils/appError.js';
import { getFirebaseAuth } from '../config/firebase.js';

export const authenticate = async (req: Request, _res: Response, next: NextFunction): Promise<void> => {
  const header = req.headers.authorization;

  if (!header || !header.startsWith('Bearer ')) {
    throw new AppError('Authentication token is missing', 401);
  }

  const token = header.replace('Bearer ', '').trim();

  try {
    const decoded = await getFirebaseAuth().verifyIdToken(token);

    req.user = {
      uid: decoded.uid,
      email: decoded.email ?? null,
      name: decoded.name ?? decoded.email ?? decoded.uid,
    };

    next();
  } catch (error) {
    throw new AppError('Invalid or expired token', 401);
  }
};
