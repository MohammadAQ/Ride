import { randomUUID } from 'crypto';
import { Timestamp } from 'firebase-admin/firestore';
import { db, isUsingMockFirebase } from '../config/firebase.js';
import { sanitizeDisplayName, selectDisplayName } from '../utils/sanitize.js';
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

const collection = () => {
  if (!db) {
    throw new AppError('The trips store is not configured.', 500);
  }

  return db.collection('trips');
};

const resolveDriverName = (data: FirebaseFirestore.DocumentData): string => {
  const driverField = data.driver;
  let driverProfile: unknown;

  if (driverField && typeof driverField === 'object' && !Array.isArray(driverField)) {
    const record = driverField as Record<string, unknown>;
    driverProfile = record.profile;
  }

  return selectDisplayName(
    data.driverDisplayName,
    data.driverFullName,
    data.driverName,
    driverField,
    driverProfile,
    data.fullName,
    data.displayName,
    data.name,
  );
};

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
    driverName: resolveDriverName(data),
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

const listTripsInMemory = ({ fromCity, toCity, driverId, limit, cursor }: ListTripsOptions) => {
  const sorted = inMemoryTrips
    .filter((trip) => (fromCity ? trip.fromCity === fromCity : true))
    .filter((trip) => (toCity ? trip.toCity === toCity : true))
    .filter((trip) => (driverId ? trip.driverId === driverId : true))
    .sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());

  if (cursor) {
    const cursorIndex = sorted.findIndex((trip) => trip.id === cursor);

    if (cursorIndex === -1) {
      throw new AppError('Invalid cursor provided', 400);
    }

    return paginate(sorted.slice(cursorIndex + 1), limit);
  }

  return paginate(sorted, limit);
};

const paginate = (items: Trip[], limit: number) => {
  const page = items.slice(0, limit).map((trip) => ({ ...trip }));
  const nextCursor = page.length === limit ? page[page.length - 1].id : undefined;

  return { trips: page, nextCursor };
};

const inMemoryTrips: Trip[] = [];

const listTripsFirestore = (options: Omit<ListTripsOptions, 'driverId'> & { driverId?: string }) =>
  applyFilters(options);

const createTripInMemory = (
  payload: CreateTripInput,
  driver: { id: string; name?: string | null },
): Trip => {
  const now = new Date().toISOString();
  const trip: Trip = {
    id: randomUUID(),
    driverId: driver.id,
    driverName: sanitizeDisplayName(driver.name),
    ...payload,
    createdAt: now,
    updatedAt: now,
  };

  inMemoryTrips.unshift(trip);

  return { ...trip };
};

const createTripFirestore = async (
  payload: CreateTripInput,
  driver: { id: string; name?: string | null },
): Promise<Trip> => {
  const now = Timestamp.now();
  const docRef = collection().doc();
  const data = {
    driverId: driver.id,
    driverName: sanitizeDisplayName(driver.name),
    ...payload,
    createdAt: now,
    updatedAt: now,
  };

  await docRef.set(data);

  return serializeTrip(await docRef.get());
};

const updateTripInMemory = (id: string, updates: UpdateTripInput, driverId: string): Trip => {
  const index = inMemoryTrips.findIndex((trip) => trip.id === id);

  if (index === -1) {
    throw new AppError('Trip not found', 404);
  }

  const existing = inMemoryTrips[index];

  if (existing.driverId !== driverId) {
    throw new AppError('You are not allowed to modify this trip', 403);
  }

  const updated: Trip = {
    ...existing,
    ...updates,
    updatedAt: new Date().toISOString(),
  };

  inMemoryTrips[index] = updated;

  return { ...updated };
};

const updateTripFirestore = async (id: string, updates: UpdateTripInput, driverId: string): Promise<Trip> => {
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

const deleteTripInMemory = (id: string, driverId: string) => {
  const index = inMemoryTrips.findIndex((trip) => trip.id === id);

  if (index === -1) {
    throw new AppError('Trip not found', 404);
  }

  if (inMemoryTrips[index].driverId !== driverId) {
    throw new AppError('You are not allowed to delete this trip', 403);
  }

  inMemoryTrips.splice(index, 1);
};

const deleteTripFirestore = async (id: string, driverId: string): Promise<void> => {
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

export const listTrips = async (options: Omit<ListTripsOptions, 'driverId'>) =>
  isUsingMockFirebase
    ? listTripsInMemory({ ...options, driverId: undefined })
    : listTripsFirestore({ ...options, driverId: undefined });

export const listTripsByDriver = async (driverId: string, options: Omit<ListTripsOptions, 'driverId'>) =>
  isUsingMockFirebase
    ? listTripsInMemory({ ...options, driverId })
    : listTripsFirestore({ ...options, driverId });

export const createTrip = async (
  payload: CreateTripInput,
  driver: { id: string; name?: string | null },
): Promise<Trip> =>
  (isUsingMockFirebase ? createTripInMemory(payload, driver) : createTripFirestore(payload, driver));

export const updateTrip = async (
  id: string,
  updates: UpdateTripInput,
  driverId: string,
): Promise<Trip> =>
  (isUsingMockFirebase ? updateTripInMemory(id, updates, driverId) : updateTripFirestore(id, updates, driverId));

export const deleteTrip = async (id: string, driverId: string): Promise<void> =>
  (isUsingMockFirebase ? deleteTripInMemory(id, driverId) : deleteTripFirestore(id, driverId));
