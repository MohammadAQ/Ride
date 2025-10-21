import { Request, Response } from 'express';
import AppError from '../utils/appError';
import {
  createTrip,
  deleteTrip,
  listTrips,
  listTripsByDriver,
  updateTrip,
} from '../services/trips.service';
import { CreateTripSchema, UpdateTripSchema } from '../schemas/trips.schema';

const parseLimit = (value: unknown): number => {
  const defaultLimit = 20;
  if (!value) {
    return defaultLimit;
  }

  const parsed = Number(value);

  if (Number.isNaN(parsed) || parsed <= 0) {
    throw new AppError('limit must be a positive number', 400);
  }

  return Math.min(parsed, 100);
};

export const getTripsHandler = async (req: Request, res: Response): Promise<void> => {
  const { fromCity, toCity, cursor } = req.query;
  const limit = parseLimit(req.query.limit);

  const { trips, nextCursor } = await listTrips({
    fromCity: typeof fromCity === 'string' ? fromCity.trim() : undefined,
    toCity: typeof toCity === 'string' ? toCity.trim() : undefined,
    limit,
    cursor: typeof cursor === 'string' ? cursor : undefined,
  });

  res.json({ trips, nextCursor: nextCursor ?? null });
};

export const getMyTripsHandler = async (req: Request, res: Response): Promise<void> => {
  if (!req.user) {
    throw new AppError('Authentication required', 401);
  }

  const { cursor } = req.query;
  const limit = parseLimit(req.query.limit);

  const { trips, nextCursor } = await listTripsByDriver(req.user.uid, {
    limit,
    cursor: typeof cursor === 'string' ? cursor : undefined,
  });

  res.json({ trips, nextCursor: nextCursor ?? null });
};

export const createTripHandler = async (req: Request, res: Response): Promise<void> => {
  if (!req.user) {
    throw new AppError('Authentication required', 401);
  }

  const payload = CreateTripSchema.parse(req.body);
  const trip = await createTrip(payload, { id: req.user.uid, name: req.user.name });

  res.status(201).json({ message: 'Trip created successfully', trip });
};

export const updateTripHandler = async (req: Request, res: Response): Promise<void> => {
  if (!req.user) {
    throw new AppError('Authentication required', 401);
  }

  const { id } = req.params;

  if (!id) {
    throw new AppError('Trip id is required', 400);
  }

  const payload = UpdateTripSchema.parse(req.body);
  const trip = await updateTrip(id, payload, req.user.uid);

  res.json(trip);
};

export const deleteTripHandler = async (req: Request, res: Response): Promise<void> => {
  if (!req.user) {
    throw new AppError('Authentication required', 401);
  }

  const { id } = req.params;

  if (!id) {
    throw new AppError('Trip id is required', 400);
  }

  await deleteTrip(id, req.user.uid);

  res.status(204).send();
};
