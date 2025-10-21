import admin from 'firebase-admin';
import { env } from './env.js';
import logger from '../utils/logger.js';

let initialized = false;

const initializeFirebase = (): admin.app.App => {
  if (!initialized) {
    admin.initializeApp({
      credential: admin.credential.cert({
        projectId: env.firebase.projectId,
        clientEmail: env.firebase.clientEmail,
        privateKey: env.firebase.privateKey,
      }),
    });
    initialized = true;
    logger.info('Firebase Admin initialized');
  }

  return admin.app();
};

export const getFirebaseAuth = (): admin.auth.Auth => {
  return initializeFirebase().auth();
};

export const getFirestore = (): admin.firestore.Firestore => {
  return initializeFirebase().firestore();
};
