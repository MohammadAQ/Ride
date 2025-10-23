import { NextFunction, Request, Response } from 'express';
import AppError from '../utils/appError.js';
import { firebaseAuth, db } from '../config/firebase.js';
import { sanitizeDisplayName, selectDisplayName } from '../utils/sanitize.js';

export const authenticate = async (req: Request, _res: Response, next: NextFunction): Promise<void> => {
  const header = req.headers.authorization;

  if (!header || !header.startsWith('Bearer ')) {
    throw new AppError('Authentication token is missing', 401);
  }

  const token = header.replace('Bearer ', '').trim();

  try {
    const decoded = await firebaseAuth.verifyIdToken(token);

    let displayName = sanitizeDisplayName(decoded.name ?? decoded.uid);

    if (db) {
      try {
        const profileSnapshot = await db.collection('users').doc(decoded.uid).get();
        if (profileSnapshot.exists) {
          const profileData = profileSnapshot.data() ?? {};
          displayName = selectDisplayName(profileData, displayName);
        }
      } catch (error) {
        // Ignore profile lookup issues and fall back to the decoded token name.
      }
    }

    req.user = {
      uid: decoded.uid,
      email: decoded.email ?? null,
      name: displayName,
    };

    next();
  } catch (error) {
    throw new AppError('Invalid or expired token', 401);
  }
};
