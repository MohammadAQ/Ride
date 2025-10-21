import dotenv from 'dotenv';

dotenv.config();

const requiredVars = [
  'PORT',
  'FIREBASE_PROJECT_ID',
  'FIREBASE_CLIENT_EMAIL',
  'FIREBASE_PRIVATE_KEY',
] as const;

const isMissing = (value: string | undefined) => value === undefined || value.trim().length === 0;

const missingVars = requiredVars.filter((variable) => isMissing(process.env[variable]));

if (missingVars.length > 0) {
  console.error('❌ Missing required environment variables:');
  for (const variable of missingVars) {
    console.error(` - ${variable}`);
  }
  console.error('\nPlease update your .env file. See .env.example for reference.');
  process.exit(1);
}

console.log('✅ Environment variables loaded successfully');

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
  firebase: FirebaseConfig;
}

export const config: AppConfig = {
  port: toNumber(process.env.PORT, 8080),
  corsOrigins: parseCorsOrigins(process.env.CORS_ORIGINS),
  firebase: {
    projectId: process.env.FIREBASE_PROJECT_ID as string,
    clientEmail: process.env.FIREBASE_CLIENT_EMAIL as string,
    privateKey: (process.env.FIREBASE_PRIVATE_KEY as string).replace(/\\n/g, '\n'),
  },
};
