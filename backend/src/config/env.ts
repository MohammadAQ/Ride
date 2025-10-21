import { config } from 'dotenv';
import { z } from 'zod';

config();

const envSchema = z.object({
  NODE_ENV: z.string().default('development'),
  PORT: z.coerce.number().int().positive().default(8080),
  CORS_ORIGINS: z.string().optional(),
  FIREBASE_PROJECT_ID: z.string().min(1, 'FIREBASE_PROJECT_ID is required'),
  FIREBASE_CLIENT_EMAIL: z.string().email('FIREBASE_CLIENT_EMAIL must be a valid email'),
  FIREBASE_PRIVATE_KEY: z.string().min(1, 'FIREBASE_PRIVATE_KEY is required'),
});

type EnvSchema = z.infer<typeof envSchema>;

const parsedEnv = envSchema.safeParse(process.env);

if (!parsedEnv.success) {
  throw new Error(`Invalid environment configuration: ${parsedEnv.error.message}`);
}

const { CORS_ORIGINS, FIREBASE_PRIVATE_KEY, ...rest } = parsedEnv.data;

const corsOrigins = (CORS_ORIGINS ?? '')
  .split(',')
  .map((origin) => origin.trim())
  .filter((origin) => origin.length > 0);

export const env: EnvSchema & {
  corsOrigins: string[];
  firebase: {
    projectId: string;
    clientEmail: string;
    privateKey: string;
  };
} = {
  ...rest,
  CORS_ORIGINS,
  FIREBASE_PRIVATE_KEY,
  corsOrigins,
  firebase: {
    projectId: rest.FIREBASE_PROJECT_ID,
    clientEmail: rest.FIREBASE_CLIENT_EMAIL,
    privateKey: FIREBASE_PRIVATE_KEY.replace(/\\n/g, '\n'),
  },
};
