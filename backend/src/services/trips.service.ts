import { Timestamp } from 'firebase-admin/firestore';
import { getFirestore } from '../config/firebase.js';
import AppError from '../utils/appError.js';
import type { CreateTripInput, UpdateTripInput } from '../schemas/trips.schema.js';

export interface Trip {
  id: string;
  driverId: string;
  driverName: string;
  fromCity: string;
  toCity: string;
  date: string;
  time: string;
  price: number;
  carModel: string;
  carColor: string;
  phoneNumber: string;
  notes?: string;
  createdAt: string;
  updatedAt: string;
}

interface ListTripsOptions {
  fromCity?: string;
  toCity?: string;
  driverId?: string;
  limit: number;
  cursor?: string;
}

const collection = () => getFirestore().collection('trips');

const serializeTrip = (doc: FirebaseFirestore.DocumentSnapshot): Trip => {
  const data = doc.data();

  if (!data) {
    throw new AppError('Trip data is missing', 500);
  }

  const createdAt: Timestamp | undefined = data.createdAt;
  const updatedAt: Timestamp | undefined = data.updatedAt;

  return {
    id: doc.id,
    driverId: data.driverId,
    driverName: data.driverName ?? '',
    fromCity: data.fromCity,
    toCity: data.toCity,
    date: data.date,
    time: data.time,
    price: typeof data.price === 'number' ? data.price : Number(data.price) || 0,
    carModel: data.carModel,
    carColor: data.carColor,
    phoneNumber: data.phoneNumber,
    notes: data.notes,
    createdAt: createdAt ? createdAt.toDate().toISOString() : '',
    updatedAt: updatedAt ? updatedAt.toDate().toISOString() : '',
  };
};

const applyFilters = async ({ fromCity, toCity, driverId, cursor, limit }: ListTripsOptions) => {
  let query: FirebaseFirestore.Query = collection().orderBy('createdAt', 'desc');

  if (fromCity) {
    query = query.where('fromCity', '==', fromCity);
  }

  if (toCity) {
    query = query.where('toCity', '==', toCity);
  }

  if (driverId) {
    query = query.where('driverId', '==', driverId);
  }

  if (cursor) {
    const cursorDoc = await collection().doc(cursor).get();

    if (!cursorDoc.exists) {
      throw new AppError('Invalid cursor provided', 400);
    }

    query = query.startAfter(cursorDoc);
  }

  const snapshot = await query.limit(limit).get();

  const trips = snapshot.docs.map(serializeTrip);
  const nextCursor = snapshot.docs.length === limit ? snapshot.docs[snapshot.docs.length - 1].id : undefined;

  return { trips, nextCursor };
};

export const listTrips = async (options: Omit<ListTripsOptions, 'driverId'>) =>
  applyFilters({ ...options, driverId: undefined });

export const listTripsByDriver = async (driverId: string, options: Omit<ListTripsOptions, 'driverId'>) =>
  applyFilters({ ...options, driverId });

export const createTrip = async (
  payload: CreateTripInput,
  driver: { id: string; name?: string | null },
): Promise<Trip> => {
  const now = Timestamp.now();
  const docRef = collection().doc();
  const data = {
    driverId: driver.id,
    driverName: driver.name ?? '',
    ...payload,
    createdAt: now,
    updatedAt: now,
  };

  await docRef.set(data);

  return serializeTrip(await docRef.get());
};

export const updateTrip = async (
  id: string,
  updates: UpdateTripInput,
  driverId: string,
): Promise<Trip> => {
  const docRef = collection().doc(id);
  const snapshot = await docRef.get();

  if (!snapshot.exists) {
    throw new AppError('Trip not found', 404);
  }

  const data = snapshot.data();

  if (!data) {
    throw new AppError('Trip data is missing', 500);
  }

  if (data.driverId !== driverId) {
    throw new AppError('You are not allowed to modify this trip', 403);
  }

  const payload = {
    ...updates,
    updatedAt: Timestamp.now(),
  };

  await docRef.update(payload);

  return serializeTrip(await docRef.get());
};

export const deleteTrip = async (id: string, driverId: string): Promise<void> => {
  const docRef = collection().doc(id);
  const snapshot = await docRef.get();

  if (!snapshot.exists) {
    throw new AppError('Trip not found', 404);
  }

  const data = snapshot.data();

  if (!data) {
    throw new AppError('Trip data is missing', 500);
  }

  if (data.driverId !== driverId) {
    throw new AppError('You are not allowed to delete this trip', 403);
  }

  await docRef.delete();
};
