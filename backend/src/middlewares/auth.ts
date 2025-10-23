import { NextFunction, Request, Response } from 'express';
import AppError from '../utils/appError.js';
import { firebaseAuth } from '../config/firebase.js';

const looksLikeEmail = (value: string): boolean => /[^\s@]+@[^\s@]+\.[^\s@]+/.test(value);

const normalizeString = (value: unknown): string | null => {
  if (typeof value !== 'string') {
    return null;
  }

  const trimmed = value.trim();

  if (!trimmed) {
    return null;
  }

  return trimmed;
};

const resolveDisplayName = (decoded: Record<string, unknown>): string | null => {
  const candidates: Array<unknown> = [
    decoded.displayName,
    decoded.fullName,
    decoded.name,
    decoded.username,
  ];

  for (const candidate of candidates) {
    const normalized = normalizeString(candidate);

    if (!normalized || looksLikeEmail(normalized)) {
      continue;
    }

    return normalized;
  }

  return null;
};

export const authenticate = async (req: Request, _res: Response, next: NextFunction): Promise<void> => {
  const header = req.headers.authorization;

  if (!header || !header.startsWith('Bearer ')) {
    throw new AppError('Authentication token is missing', 401);
  }

  const token = header.replace('Bearer ', '').trim();

  try {
    const decoded = await firebaseAuth.verifyIdToken(token);
    const decodedRecord = decoded as Record<string, unknown>;

    req.user = {
      uid: decoded.uid,
      email: decoded.email ?? null,
      name: resolveDisplayName(decodedRecord),
    };

    next();
  } catch (error) {
    throw new AppError('Invalid or expired token', 401);
  }
};
