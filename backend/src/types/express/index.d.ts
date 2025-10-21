import 'express';

declare global {
  namespace Express {
    interface UserIdentity {
      uid: string;
      email?: string | null;
      name?: string | null;
    }

    interface Request {
      user?: UserIdentity;
    }
  }
}

export {};
