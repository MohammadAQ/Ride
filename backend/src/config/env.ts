import dotenv from 'dotenv';

dotenv.config();

const firebaseVars = ['FIREBASE_PROJECT_ID', 'FIREBASE_CLIENT_EMAIL', 'FIREBASE_PRIVATE_KEY'] as const;

const isMissing = (value: string | undefined) => value === undefined || value.trim().length === 0;

const missingFirebaseVars = firebaseVars.filter((variable) => isMissing(process.env[variable]));

const isProduction = process.env.NODE_ENV === 'production';
const isFirebaseConfigured = missingFirebaseVars.length === 0;

if (!isFirebaseConfigured) {
  const heading = isProduction ? '❌ Missing required environment variables:' : '⚠️ Firebase credentials not found:';
  console[isProduction ? 'error' : 'warn'](heading);
  for (const variable of missingFirebaseVars) {
    console[isProduction ? 'error' : 'warn'](` - ${variable}`);
  }

  if (isProduction) {
    console.error('\nPlease update your .env file. See .env.example for reference.');
    process.exit(1);
  }

  console.warn('\nContinuing startup with an in-memory development store and mock authentication.');
  console.warn('See .env.example for the variables required to connect to Firebase.');
} else {
  console.log('✅ Environment variables loaded successfully');
}

const toNumber = (value: string | undefined, fallback: number): number => {
  if (!value) {
    return fallback;
  }

  const parsed = Number(value);

  return Number.isNaN(parsed) ? fallback : parsed;
};

const parseCorsOrigins = (origins: string | undefined): string[] => {
  if (!origins) {
    return [];
  }

  return origins
    .split(',')
    .map((origin) => origin.trim())
    .filter((origin) => origin.length > 0);
};

export interface FirebaseConfig {
  projectId: string;
  clientEmail: string;
  privateKey: string;
}

export interface AppConfig {
  port: number;
  corsOrigins: string[];
  firebase?: FirebaseConfig;
  firebaseEnabled: boolean;
}

const firebaseConfig = isFirebaseConfigured
  ? {
      projectId: process.env.FIREBASE_PROJECT_ID as string,
      clientEmail: process.env.FIREBASE_CLIENT_EMAIL as string,
      privateKey: (process.env.FIREBASE_PRIVATE_KEY as string).replace(/\\n/g, '\n'),
    }
  : undefined;

export const config: AppConfig = {
  port: toNumber(process.env.PORT, 8080),
  corsOrigins: parseCorsOrigins(process.env.CORS_ORIGINS),
  firebase: firebaseConfig,
  firebaseEnabled: Boolean(firebaseConfig),
};
