import admin from 'firebase-admin';
import { config } from './env.js';

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert({
      projectId: config.firebase.projectId,
      clientEmail: config.firebase.clientEmail,
      privateKey: config.firebase.privateKey,
    }),
  });
  console.log('🔥 Firebase Admin initialized');
}

export const firebaseApp = admin.app();
export const firebaseAuth = admin.auth();
export const db = admin.firestore();
