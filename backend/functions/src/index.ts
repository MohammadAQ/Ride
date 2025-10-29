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
  functions.logger.info('Cleaning up invalid tokens', {
    userId: docRef.id,
    count: tokens.length,
  });
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
    functions.logger.info('Sending notification to tokens', {
      targetCount: tokens.length,
      title: notification.title,
    });
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

    functions.logger.info('Notification send summary', {
      targetCount: tokens.length,
      successCount: response.successCount,
      failureCount: response.failureCount,
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
  .onCreate(async (snapshot: functions.firestore.QueryDocumentSnapshot) => {
    const booking = snapshot.data() as BookingDoc | undefined;
    functions.logger.info('onBookingCreated triggered', {
      bookingId: snapshot.id,
      hasBooking: Boolean(booking),
    });

    if (!booking) {
      functions.logger.warn('onBookingCreated missing booking payload', {
        bookingId: snapshot.id,
      });
      return;
    }

    try {
      const driverId = stringFrom(booking.driverId ?? '', '');
      if (!driverId) {
        functions.logger.info('Booking created without driverId; skipping notification.', {
          bookingId: snapshot.id,
        });
        return;
      }

      const tripId = resolveTripId(booking);
      const passengerName = stringFrom(booking.passengerName ?? '', 'راكب');
      const passengerId = stringFrom(booking.passengerId ?? booking.userId ?? '', '');

      const driverTokens = await getUserTokens(driverId);
      if (!driverTokens || driverTokens.tokens.length === 0) {
        functions.logger.warn('Driver has no registered tokens', {
          bookingId: snapshot.id,
          driverId,
        });
        return;
      }

      functions.logger.info('Dispatching booking notification to driver', {
        bookingId: snapshot.id,
        driverId,
        tokenCount: driverTokens.tokens.length,
        tripId,
      });

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
    } catch (error) {
      functions.logger.error('onBookingCreated failed', error, {
        bookingId: snapshot.id,
      });
    }
  });

export const onBookingStatusUpdated = functions
  .runWith(runtimeOptions)
  .firestore.document('bookings/{bookingId}')
  .onUpdate(
    async (
      change: functions.Change<functions.firestore.DocumentSnapshot>,
    ) => {
    const before = change.before.data() as BookingDoc | undefined;
    const after = change.after.data() as BookingDoc | undefined;
    functions.logger.info('onBookingStatusUpdated triggered', {
      bookingId: change.after.id,
      hasAfter: Boolean(after),
      hasBefore: Boolean(before),
    });
    if (!after) {
      return;
    }

    try {
      const previousStatus = toLower(before?.status);
      const nextStatus = toLower(after.status);
      const tripId = resolveTripId(after);
      const driverId = stringFrom(after.driverId ?? '', '');
      const passengerId = stringFrom(after.passengerId ?? after.userId ?? '', '');
      const passengerName = stringFrom(after.passengerName ?? '', 'راكب');

      if (nextStatus === 'confirmed' && previousStatus !== 'confirmed') {
        const passengerTokens = await getUserTokens(passengerId);
        if (passengerTokens && passengerTokens.tokens.length) {
          functions.logger.info('Sending confirmation notification to passenger', {
            bookingId: change.after.id,
            passengerId,
            tokenCount: passengerTokens.tokens.length,
          });
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
        } else {
          functions.logger.warn('Passenger has no tokens to receive confirmation', {
            bookingId: change.after.id,
            passengerId,
          });
        }
      }

      if (nextStatus === 'canceled' && previousStatus !== 'canceled') {
        const driverTokens = await getUserTokens(driverId);
        if (driverTokens && driverTokens.tokens.length) {
          const body = passengerName
            ? `قام ${passengerName} بإلغاء الحجز.`
            : 'قام أحد الركاب بإلغاء الحجز.';
          functions.logger.info('Sending cancellation notification to driver', {
            bookingId: change.after.id,
            driverId,
            tokenCount: driverTokens.tokens.length,
          });
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
        } else {
          functions.logger.warn('Driver has no tokens to receive cancellation', {
            bookingId: change.after.id,
            driverId,
          });
        }
      }
    } catch (error) {
      functions.logger.error('onBookingStatusUpdated failed', error, {
        bookingId: change.after.id,
      });
    }
    },
  );

export const onBookingDeleted = functions
  .runWith(runtimeOptions)
  .firestore.document('bookings/{bookingId}')
  .onDelete(async (snapshot: functions.firestore.QueryDocumentSnapshot) => {
    const booking = snapshot.data() as BookingDoc | undefined;
    functions.logger.info('onBookingDeleted triggered', {
      bookingId: snapshot.id,
      hasBooking: Boolean(booking),
    });
    if (!booking) {
      return;
    }

    try {
      const passengerId = stringFrom(booking.passengerId ?? booking.userId ?? '', '');
      if (!passengerId) {
        functions.logger.warn('Booking deleted without passengerId; skipping.', {
          bookingId: snapshot.id,
        });
        return;
      }

      const tripId = resolveTripId(booking);
      const driverId = stringFrom(booking.driverId ?? '', '');
      const passengerTokens = await getUserTokens(passengerId);

      if (!passengerTokens || passengerTokens.tokens.length === 0) {
        functions.logger.warn('Passenger has no tokens for deletion notice', {
          bookingId: snapshot.id,
          passengerId,
        });
        return;
      }

      functions.logger.info('Sending deletion notification to passenger', {
        bookingId: snapshot.id,
        passengerId,
        tokenCount: passengerTokens.tokens.length,
      });

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
    } catch (error) {
      functions.logger.error('onBookingDeleted failed', error, {
        bookingId: snapshot.id,
      });
    }
  });

export const sendTestNotification = functions
  .runWith(runtimeOptions)
  .https.onCall(async (data: unknown, context: functions.https.CallableContext) => {
    const uid = context.auth?.uid;
    if (!uid) {
      throw new functions.https.HttpsError('unauthenticated', 'Authentication required.');
    }

    const payload = (data ?? {}) as Record<string, unknown>;
    const requestedToken = stringFrom(payload.token, '');
    if (!requestedToken) {
      throw new functions.https.HttpsError('invalid-argument', 'FCM token is required.');
    }

    functions.logger.info('sendTestNotification invoked', {
      uid,
      tokenPreview: `${requestedToken.substring(0, 12)}…`,
    });

    try {
      const ownerTokens = await getUserTokens(uid);
      const tokens = Array.from(new Set([requestedToken].filter((token) => token.trim().length > 0)));

      if (!tokens.length) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'No FCM tokens were provided for the test notification.',
        );
      }

      if (ownerTokens && !ownerTokens.tokens.includes(requestedToken)) {
        functions.logger.warn('Requested token not stored under user document', {
          uid,
          storedCount: ownerTokens.tokens.length,
        });
      }

      const notification: admin.messaging.Notification = {
        title: 'اختبار الإشعارات',
        body: 'تم إرسال هذا الإشعار للتأكد من إعداد التنبيهات.',
      };

      const dataPayload = buildDataPayload({
        type: 'test_notification',
        triggeredBy: uid,
      });

      const response = await admin.messaging().sendMulticast({
        tokens,
        notification,
        data: dataPayload,
      });

      const invalidTokens: string[] = [];
      response.responses.forEach((res, index) => {
        if (!res.success) {
          const token = tokens[index];
          const code = res.error?.code ?? 'unknown';
          functions.logger.warn('Test notification delivery failure', code, token, res.error);
          if (
            code === 'messaging/registration-token-not-registered' ||
            code === 'messaging/invalid-registration-token'
          ) {
            invalidTokens.push(token);
          }
        }
      });

      if (invalidTokens.length && ownerTokens) {
        await cleanupTokens(ownerTokens.ref, invalidTokens);
      }

      functions.logger.info('sendTestNotification summary', {
        uid,
        targetCount: tokens.length,
        successCount: response.successCount,
        failureCount: response.failureCount,
      });

      return {
        targetCount: tokens.length,
        successCount: response.successCount,
        failureCount: response.failureCount,
      };
    } catch (error) {
      functions.logger.error('sendTestNotification failed', error, { uid });
      if (error instanceof functions.https.HttpsError) {
        throw error;
      }
      throw new functions.https.HttpsError('internal', 'Failed to send test notification.');
    }
  });
