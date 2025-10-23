import admin from 'firebase-admin';
import { config } from './env.js';

const looksLikeEmail = (value: string): boolean => /[^\s@]+@[^\s@]+\.[^\s@]+/.test(value);

const sanitizeName = (value: unknown): string | undefined => {
  if (typeof value !== 'string') {
    return undefined;
  }

  const trimmed = value.trim();

  if (!trimmed || looksLikeEmail(trimmed)) {
    return undefined;
  }

  return trimmed;
};

const createMockDecodedToken = (token: string): admin.auth.DecodedIdToken => {
  if (!token) {
    throw new Error('Token cannot be empty');
  }

  if (token.startsWith('mock:')) {
    const [, uid = '', email, name] = token.split(':');

    const sanitizedName = sanitizeName(name);

    if (!uid) {
      throw new Error('Mock tokens must follow the format "mock:<uid>[:<email>[:<name>]]".');
    }

    const issuedAt = Math.floor(Date.now() / 1000);

    return {
      uid,
      email: email ?? null,
      name: sanitizedName,
      aud: 'mock',
      auth_time: issuedAt,
      exp: issuedAt + 60 * 60,
      iat: issuedAt,
      iss: 'https://mock.firebase.local',
      sub: uid,
    } as admin.auth.DecodedIdToken;
  }

  try {
    const json = Buffer.from(token, 'base64url').toString('utf8');
    const parsed = JSON.parse(json) as { uid?: string; email?: string | null; name?: string | null };

    if (!parsed.uid) {
      throw new Error('Decoded token is missing the "uid" property.');
    }

    const issuedAt = Math.floor(Date.now() / 1000);

    const sanitizedName = sanitizeName(parsed.name);

    return {
      uid: parsed.uid,
      email: parsed.email ?? null,
      name: sanitizedName,
      aud: 'mock',
      auth_time: issuedAt,
      exp: issuedAt + 60 * 60,
      iat: issuedAt,
      iss: 'https://mock.firebase.local',
      sub: parsed.uid,
    } as admin.auth.DecodedIdToken;
  } catch (error) {
    throw new Error('Unable to decode mock token. Provide a base64url encoded JSON token or use the "mock:" format.');
  }
};

let firebaseAuth: admin.auth.Auth;
let db: FirebaseFirestore.Firestore | null = null;

if (config.firebaseEnabled && config.firebase) {
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

  firebaseAuth = admin.auth();
  db = admin.firestore();
} else {
  console.warn('⚠️ Firebase Admin not initialised. Falling back to mock authentication.');

  const mockAuth: Pick<admin.auth.Auth, 'verifyIdToken'> = {
    async verifyIdToken(token: string): Promise<admin.auth.DecodedIdToken> {
      return createMockDecodedToken(token);
    },
  };

  firebaseAuth = mockAuth as admin.auth.Auth;
}

export { firebaseAuth, db };
export const isUsingMockFirebase = !config.firebaseEnabled;
