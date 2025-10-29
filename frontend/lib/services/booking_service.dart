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
      final int totalSeats = _parseInt(tripData['totalSeats']);
      final int fallbackTotal = totalSeats > 0 ? totalSeats : bookedUsers.length + availableSeats;
      final int seatsRemaining = availableSeats > 0 ? availableSeats : fallbackTotal - bookedUsers.length;

      if (seatsRemaining <= 0) {
        throw BookingException('sold-out', 'لا توجد مقاعد متاحة في هذه الرحلة.');
      }

      final int updatedAvailableSeats = seatsRemaining - 1;
      final List<String> updatedBookedUsers = List<String>.from(bookedUsers)..add(userId);

      transaction.update(tripRef, <String, dynamic>{
        'availableSeats': updatedAvailableSeats,
        'bookedUsers': updatedBookedUsers,
        if (totalSeats <= 0) 'totalSeats': updatedBookedUsers.length + updatedAvailableSeats,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      transaction.set(bookingRef, <String, dynamic>{
        'userId': userId,
        'tripId': tripId,
        'status': 'confirmed',
        'bookedAt': FieldValue.serverTimestamp(),
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
}
