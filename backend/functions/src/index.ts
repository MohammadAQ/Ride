import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions';

/**
 * Cloud Functions that send push notifications for booking events.
 *
 * Test plan (mirrors the client-side checklist):
 * 1. Create a new booking → driver tokens receive "حجز جديد".
 * 2. Driver confirms the booking → passenger receives "تم تأكيد رحلتك".
 * 3. Passenger cancels → driver receives a cancellation alert.
 * 4. Driver deletes/cancels the booking → passenger receives the deletion alert.
 */
admin.initializeApp();

const db = admin.firestore();
const runtimeOptions = { timeoutSeconds: 60, memory: '256MB' as const };

type UserTokenResult = {
  tokens: string[];
  ref: FirebaseFirestore.DocumentReference<FirebaseFirestore.DocumentData>;
  displayName: string;
};

type BookingDoc = {
  tripId?: unknown;
  tripRef?: admin.firestore.DocumentReference;
  passengerId?: unknown;
  userId?: unknown;
  driverId?: unknown;
  passengerName?: unknown;
  status?: unknown;
};

function stringFrom(value: unknown, fallback = ''): string {
  if (value === null || value === undefined) {
    return fallback;
  }

  if (typeof value === 'string') {
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : fallback;
  }

  if (value instanceof admin.firestore.DocumentReference) {
    return value.id;
  }

  return String(value);
}

function toLower(value: unknown): string {
  return stringFrom(value).toLowerCase();
}

function buildDataPayload(input: Record<string, unknown>): Record<string, string> {
  const data: Record<string, string> = {};
  for (const [key, value] of Object.entries(input)) {
    if (value === undefined || value === null) {
      continue;
    }
    data[key] = String(value);
  }
  return data;
}

async function getUserTokens(userId: string): Promise<UserTokenResult | null> {
  const trimmed = userId.trim();
  if (!trimmed) {
    return null;
  }

  const docRef = db.collection('users').doc(trimmed);
  const snapshot = await docRef.get();
  const data = snapshot.data() ?? {};
  const rawTokens = (data.fcmTokens ?? {}) as Record<string, unknown>;
  const tokens = Object.keys(rawTokens).filter((token) => token.trim().length > 0);
  const displayName = typeof data.displayName === 'string' ? data.displayName : '';

  return { tokens, ref: docRef, displayName };
}

async function cleanupTokens(
  docRef: FirebaseFirestore.DocumentReference,
  tokens: string[],
): Promise<void> {
  if (!tokens.length) {
    return;
  }
  const updates: Record<string, FirebaseFirestore.FieldValue> = {};
  for (const token of tokens) {
    updates[`fcmTokens.${token}`] = admin.firestore.FieldValue.delete();
  }
  await docRef.update(updates);
}

async function sendToTokens(
  tokens: string[],
  notification: admin.messaging.Notification,
  data: Record<string, string>,
  ownerDoc?: FirebaseFirestore.DocumentReference,
): Promise<void> {
  if (tokens.length === 0) {
    functions.logger.debug('Skipping send; no tokens available.', notification);
    return;
  }

  try {
    const response = await admin.messaging().sendMulticast({ tokens, notification, data });
    const invalidTokens: string[] = [];

    response.responses.forEach((res, index) => {
      if (res.success) {
        return;
      }

      const token = tokens[index];
      const code = res.error?.code ?? 'unknown';
      functions.logger.warn('Failed to deliver notification', code, token, res.error);

      if (
        code === 'messaging/registration-token-not-registered' ||
        code === 'messaging/invalid-registration-token'
      ) {
        invalidTokens.push(token);
      }
    });

    if (invalidTokens.length && ownerDoc) {
      await cleanupTokens(ownerDoc, invalidTokens);
    }
  } catch (error) {
    functions.logger.error('sendToTokens error', error);
  }
}

function resolveTripId(booking: BookingDoc): string {
  const explicit = stringFrom(booking.tripId ?? '', '');
  if (explicit) {
    return explicit;
  }
  if (booking.tripRef instanceof admin.firestore.DocumentReference) {
    return booking.tripRef.id;
  }
  return '';
}

export const onBookingCreated = functions
  .runWith(runtimeOptions)
  .firestore.document('bookings/{bookingId}')
  .onCreate(async (snapshot) => {
    const booking = snapshot.data() as BookingDoc | undefined;
    if (!booking) {
      return;
    }

    const driverId = stringFrom(booking.driverId ?? '', '');
    if (!driverId) {
      functions.logger.info('Booking created without driverId; skipping notification.');
      return;
    }

    const tripId = resolveTripId(booking);
    const passengerName = stringFrom(booking.passengerName ?? '', 'راكب');
    const passengerId = stringFrom(booking.passengerId ?? booking.userId ?? '', '');

    const driverTokens = await getUserTokens(driverId);
    if (!driverTokens || driverTokens.tokens.length === 0) {
      return;
    }

    await sendToTokens(
      driverTokens.tokens,
      {
        title: 'حجز جديد',
        body: `قام ${passengerName} بحجز رحلتك.`,
      },
      buildDataPayload({
        type: 'booking_created',
        tripId,
        route: 'trip_details',
        passengerId,
      }),
      driverTokens.ref,
    );
  });

export const onBookingStatusUpdated = functions
  .runWith(runtimeOptions)
  .firestore.document('bookings/{bookingId}')
  .onUpdate(async (change) => {
    const before = change.before.data() as BookingDoc | undefined;
    const after = change.after.data() as BookingDoc | undefined;
    if (!after) {
      return;
    }

    const previousStatus = toLower(before?.status);
    const nextStatus = toLower(after.status);
    const tripId = resolveTripId(after);
    const driverId = stringFrom(after.driverId ?? '', '');
    const passengerId = stringFrom(after.passengerId ?? after.userId ?? '', '');
    const passengerName = stringFrom(after.passengerName ?? '', 'راكب');

    if (nextStatus === 'confirmed' && previousStatus !== 'confirmed') {
      const passengerTokens = await getUserTokens(passengerId);
      if (passengerTokens && passengerTokens.tokens.length) {
        await sendToTokens(
          passengerTokens.tokens,
          {
            title: 'تم تأكيد رحلتك',
            body: 'السائق أكد رحلتك',
          },
          buildDataPayload({
            type: 'booking_confirmed',
            tripId,
            route: 'trip_details',
            driverId,
          }),
          passengerTokens.ref,
        );
      }
    }

    if (nextStatus === 'canceled' && previousStatus !== 'canceled') {
      const driverTokens = await getUserTokens(driverId);
      if (driverTokens && driverTokens.tokens.length) {
        const body = passengerName
          ? `قام ${passengerName} بإلغاء الحجز.`
          : 'قام أحد الركاب بإلغاء الحجز.';
        await sendToTokens(
          driverTokens.tokens,
          {
            title: 'تم إلغاء الحجز',
            body,
          },
          buildDataPayload({
            type: 'booking_canceled',
            tripId,
            route: 'trip_details',
            passengerId,
          }),
          driverTokens.ref,
        );
      }
    }
  });

export const onBookingDeleted = functions
  .runWith(runtimeOptions)
  .firestore.document('bookings/{bookingId}')
  .onDelete(async (snapshot) => {
    const booking = snapshot.data() as BookingDoc | undefined;
    if (!booking) {
      return;
    }

    const passengerId = stringFrom(booking.passengerId ?? booking.userId ?? '', '');
    if (!passengerId) {
      return;
    }

    const tripId = resolveTripId(booking);
    const driverId = stringFrom(booking.driverId ?? '', '');
    const passengerTokens = await getUserTokens(passengerId);

    if (!passengerTokens || passengerTokens.tokens.length === 0) {
      return;
    }

    await sendToTokens(
      passengerTokens.tokens,
      {
        title: 'تم إلغاء رحلتك',
        body: 'قام السائق بإلغاء الحجز.',
      },
      buildDataPayload({
        type: 'booking_deleted',
        tripId,
        route: 'trip_details',
        driverId,
      }),
      passengerTokens.ref,
    );
  });
