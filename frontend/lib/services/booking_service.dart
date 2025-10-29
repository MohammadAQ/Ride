import 'package:cloud_firestore/cloud_firestore.dart';

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
        throw BookingException('already-booked', 'لقد قمت بحجز هذه الرحلة مسبقًا.');
      }

      final DocumentSnapshot<Map<String, dynamic>> existingBooking =
          await transaction.get(bookingRef);
      if (existingBooking.exists) {
        throw BookingException('already-booked', 'لقد قمت بحجز هذه الرحلة مسبقًا.');
      }

      final int availableSeats = _parseInt(tripData['availableSeats']);
      if (availableSeats <= 0) {
        throw BookingException('sold-out', 'لا توجد مقاعد متاحة في هذه الرحلة.');
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

      transaction.set(bookingRef, <String, dynamic>{
        'userId': userId,
        'tripId': tripId,
        'driverId': driverId,
        'status': 'confirmed',
        'bookedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
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

      final List<String> updatedBookedUsers = List<String>.from(bookedUsers)
        ..removeWhere((String id) => id == userId);

      final int availableSeats = _parseInt(tripData['availableSeats']);
      final int totalSeats = _parseInt(tripData['totalSeats']);
      final int increasedSeats = availableSeats + 1;
      final int expectedAvailable = totalSeats > 0
          ? totalSeats - updatedBookedUsers.length
          : increasedSeats;
      final int sanitizedAvailable =
          expectedAvailable < 0 ? 0 : expectedAvailable;

      transaction.update(tripRef, <String, dynamic>{
        'availableSeats': sanitizedAvailable,
        'bookedUsers': updatedBookedUsers,
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
}
