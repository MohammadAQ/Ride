import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:carpal_app/models/user_profile.dart';

class BookingException implements Exception {
  BookingException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'BookingException(code: $code, message: $message)';
}

class BookingService {
  BookingService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<void> bookTrip({required String tripId, required String userId}) async {
    if (tripId.isEmpty) {
      throw BookingException('invalid-trip', 'معرّف الرحلة غير صالح.');
    }
    if (userId.isEmpty) {
      throw BookingException('invalid-user', 'يجب تسجيل الدخول للحجز.');
    }

    final DocumentReference<Map<String, dynamic>> tripRef =
        _firestore.collection('trips').doc(tripId);
    final DocumentReference<Map<String, dynamic>> bookingRef =
        _firestore.collection('bookings').doc('${tripId}_$userId');

    // Resolve the passenger name before entering the transaction so the value
    // is ready when we write the booking document. This guarantees the driver
    // dashboard always has a passengerName field to display instead of showing
    // "راكب غير معروف" for new bookings.
    final String passengerName = await _resolvePassengerName(userId);

    try {
      await _firestore.runTransaction((Transaction transaction) async {
        final DocumentSnapshot<Map<String, dynamic>> tripSnapshot =
            await transaction.get(tripRef);

        if (!tripSnapshot.exists) {
          throw BookingException('not-found', 'هذه الرحلة غير متاحة.');
        }

        final Map<String, dynamic>? tripData = tripSnapshot.data();

        if (tripData == null) {
          throw BookingException('invalid-data', 'تعذر قراءة بيانات الرحلة.');
        }

        final String driverId = _parseString(tripData['driverId']);
        if (driverId.isNotEmpty && driverId == userId) {
          throw BookingException(
            'driver-booking',
            'لا يمكنك حجز رحلتك الخاصة.',
          );
        }

        final List<dynamic> bookedUsersRaw = tripData['bookedUsers'] is List
            ? List<dynamic>.from(tripData['bookedUsers'] as List)
            : <dynamic>[];
        final List<String> bookedUsers = bookedUsersRaw
            .map((dynamic value) => value?.toString() ?? '')
            .where((String value) => value.isNotEmpty)
            .toList(growable: false);

        if (bookedUsers.contains(userId)) {
          throw BookingException(
              'already-booked', 'لقد قمت بحجز هذه الرحلة مسبقًا.');
        }

        final DocumentSnapshot<Map<String, dynamic>> existingBooking =
            await transaction.get(bookingRef);

        Map<String, dynamic>? existingBookingData;
        String existingBookingStatus = '';

        if (existingBooking.exists) {
          existingBookingData = existingBooking.data();
          if (existingBookingData == null) {
            throw BookingException('invalid-data', 'تعذر قراءة بيانات الحجز.');
          }

          existingBookingStatus =
              _parseString(existingBookingData['status']).toLowerCase();

          if (existingBookingStatus != 'canceled') {
            throw BookingException(
                'already-booked', 'لقد قمت بحجز هذه الرحلة مسبقًا.');
          }
        }

        final int availableSeats = _parseInt(tripData['availableSeats']);
        if (availableSeats <= 0) {
          throw BookingException(
              'sold-out', 'لا توجد مقاعد متاحة في هذه الرحلة.');
        }

        if (kDebugMode) {
          // Keep a verbose log so we can verify the booking payload matches the
          // dashboard query (tripId/tripRef/driverId) whenever a booking is
          // created. This helps track down index issues quickly in debug logs.
          debugPrint(
            'Creating booking -> tripId: $tripId | userId: $userId | '
            'driverId: $driverId | bookingDoc: ${bookingRef.path}',
          );
        }

        final List<String> updatedBookedUsers =
            List<String>.from(bookedUsers)..add(userId);
        final int updatedAvailableSeats = availableSeats - 1;
        final int sanitizedAvailableSeats =
            updatedAvailableSeats < 0 ? 0 : updatedAvailableSeats;

        transaction.update(tripRef, <String, dynamic>{
          'availableSeats': sanitizedAvailableSeats,
          'bookedUsers': updatedBookedUsers,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        if (existingBookingStatus == 'canceled') {
          transaction.update(bookingRef, <String, dynamic>{
            // Ensure both the string ID and the DocumentReference are always
            // present so dashboard queries match regardless of type.
            'tripId': tripId,
            'tripRef': tripRef,
            'driverId': driverId,
            'userId': userId,
            'passengerId': userId,
            // Persist the resolved passenger name so the dashboard has an
            // immediate value even if the profile cache misses later on.
            'passengerName': passengerName,
            'status': 'confirmed',
            'bookedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            'canceledAt': FieldValue.delete(),
          });
        } else {
          transaction.set(bookingRef, <String, dynamic>{
            'userId': userId,
            'passengerId': userId,
            // Store the plain string tripId for backwards compatibility with
            // existing queries and analytics.
            'tripId': tripId,
            // Store a DocumentReference to the trip to support reference-based
            // filters used by the dashboard when older bookings saved a
            // reference.
            'tripRef': tripRef,
            'driverId': driverId,
            // Persist the resolved passenger name so it is always available to
            // the trip dashboard, even if the user later changes their
            // profile.
            'passengerName': passengerName,
            'status': 'confirmed',
            'bookedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            // Persist createdAt so we can order bookings consistently.
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      });
    } on BookingException {
      rethrow;
    } on FirebaseException catch (error) {
      throw BookingException(
        error.code,
        // Provide a localized message instead of exposing the raw Firebase
        // error to the caller so the UI can present something clearer.
        'تعذر إتمام الحجز بسبب خطأ في الاتصال بالخادم. الرجاء المحاولة لاحقًا.',
      );
    } catch (error) {
      throw BookingException(
        'unknown',
        'حدث خطأ غير متوقع أثناء إنشاء الحجز. الرجاء المحاولة مرة أخرى لاحقًا.',
      );
    }
  }

  Future<void> cancelBooking({
    required String tripId,
    required String userId,
  }) async {
    if (tripId.isEmpty) {
      throw BookingException('invalid-trip', 'معرّف الرحلة غير صالح.');
    }
    if (userId.isEmpty) {
      throw BookingException('invalid-user', 'يجب تسجيل الدخول لإلغاء الحجز.');
    }

    final DocumentReference<Map<String, dynamic>> tripRef =
        _firestore.collection('trips').doc(tripId);
    final DocumentReference<Map<String, dynamic>> bookingRef =
        _firestore.collection('bookings').doc('${tripId}_$userId');

    await _firestore.runTransaction((Transaction transaction) async {
      final DocumentSnapshot<Map<String, dynamic>> bookingSnapshot =
          await transaction.get(bookingRef);

      if (!bookingSnapshot.exists) {
        throw BookingException('booking-not-found', 'لم يتم العثور على الحجز.');
      }

      final Map<String, dynamic>? bookingData = bookingSnapshot.data();
      if (bookingData == null) {
        throw BookingException('invalid-data', 'تعذر قراءة بيانات الحجز.');
      }

      final String bookingUserId = _parseString(bookingData['userId']);
      if (bookingUserId != userId) {
        throw BookingException('unauthorized', 'لا يمكنك إلغاء هذا الحجز.');
      }

      final String status = _parseString(bookingData['status']).toLowerCase();
      if (status == 'canceled') {
        throw BookingException('already-canceled', 'تم إلغاء هذا الحجز مسبقًا.');
      }

      final DocumentSnapshot<Map<String, dynamic>> tripSnapshot =
          await transaction.get(tripRef);

      if (!tripSnapshot.exists) {
        throw BookingException('not-found', 'هذه الرحلة لم تعد متاحة.');
      }

      final Map<String, dynamic>? tripData = tripSnapshot.data();
      if (tripData == null) {
        throw BookingException('invalid-data', 'تعذر قراءة بيانات الرحلة.');
      }

      final List<dynamic> bookedUsersRaw = tripData['bookedUsers'] is List
          ? List<dynamic>.from(tripData['bookedUsers'] as List)
          : <dynamic>[];
      final List<String> bookedUsers = bookedUsersRaw
          .map((dynamic value) => value?.toString() ?? '')
          .where((String value) => value.isNotEmpty)
          .toList();

      if (!bookedUsers.contains(userId)) {
        throw BookingException('not-booked', 'لم تقم بحجز هذه الرحلة.');
      }

      final int availableSeats = _parseInt(tripData['availableSeats']);
      final int totalSeats = _parseInt(tripData['totalSeats']);
      final int increasedSeats = availableSeats + 1;
      final int maxSeats = totalSeats > 0 ? totalSeats : increasedSeats;
      final int sanitizedAvailable =
          increasedSeats > maxSeats ? maxSeats : increasedSeats;

      transaction.update(tripRef, <String, dynamic>{
        'availableSeats': sanitizedAvailable,
        'bookedUsers': FieldValue.arrayRemove(<String>[userId]),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      transaction.update(bookingRef, <String, dynamic>{
        'status': 'canceled',
        'canceledAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  static int _parseInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _parseString(dynamic value) {
    if (value == null) {
      return '';
    }
    return value.toString().trim();
  }

  Future<String> _resolvePassengerName(String userId) async {
    final String trimmedId = userId.trim();
    if (trimmedId.isEmpty) {
      return 'مستخدم';
    }

    try {
      final DocumentSnapshot<Map<String, dynamic>> snapshot = await _firestore
          .collection('users')
          .doc(trimmedId)
          .get();

      if (snapshot.exists) {
        final Map<String, dynamic> data = snapshot.data() ?? <String, dynamic>{};
        final UserProfile profile =
            UserProfile.fromFirestore(snapshot.id, data);
        if (profile.displayName.isNotEmpty && profile.displayName != 'مستخدم') {
          return profile.displayName;
        }
      }
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          'Failed to resolve passenger name for $trimmedId: $error\n$stackTrace',
        );
      }
    }

    // Returning the generic label keeps the booking write resilient so the
    // transaction still succeeds even if the profile lookup fails.
    return 'مستخدم';
  }
}
