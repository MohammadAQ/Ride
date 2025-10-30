import 'package:cloud_firestore/cloud_firestore.dart';

class TripValidationException implements Exception {
  TripValidationException(this.message);

  final String message;

  @override
  String toString() => 'TripValidationException($message)';
}

class DriverTripValidationService {
  DriverTripValidationService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<void> ensureCanCreateTrip({
    required String driverId,
    required DateTime startTime,
    required String languageCode,
  }) async {
    final String normalizedLanguage = _normalizeLanguage(languageCode);
    final String trimmedDriverId = driverId.trim();
    if (trimmedDriverId.isEmpty) {
      return;
    }

    final QuerySnapshot<Map<String, dynamic>> driverTripsSnapshot = await _firestore
        .collection('trips')
        .where('driverId', isEqualTo: trimmedDriverId)
        .get();

    final List<_TripRecord> driverTrips = driverTripsSnapshot.docs
        .map((doc) => _TripRecord(id: doc.id, data: doc.data()))
        .toList(growable: false);

    final DateTime now = DateTime.now();

    // Rule 8: Prevent publishing while another trip is active (start <= now < end).
    for (final _TripRecord trip in driverTrips) {
      final DateTime? tripStart = trip.start;
      if (tripStart == null) {
        continue;
      }
      final DateTime? tripEnd = trip.end;
      if (tripEnd == null || !tripEnd.isAfter(tripStart)) {
        continue;
      }
      if ((now.isAfter(tripStart) || now.isAtSameMomentAs(tripStart)) && now.isBefore(tripEnd)) {
        throw TripValidationException(
          _localizedMessage(
            normalizedLanguage,
            'You already have an ongoing trip that hasn\'t ended yet.',
            'لديك رحلة حالية لم تنتهِ بعد، لا يمكنك إنشاء رحلة جديدة.',
          ),
        );
      }
    }

    // Rule 1: Reject if another trip exists within ±1 hour of the requested start.
    for (final _TripRecord trip in driverTrips) {
      final DateTime? tripStart = trip.start;
      if (tripStart == null) {
        continue;
      }
      final Duration difference = tripStart.difference(startTime).abs();
      if (_isSameDay(tripStart, startTime) && difference.inMinutes <= 60) {
        throw TripValidationException(
          _localizedMessage(
            normalizedLanguage,
            'You already have another trip scheduled around this time.',
            'لديك رحلة أخرى مجدولة في نفس الوقت تقريبًا.',
          ),
        );
      }
    }

    // Rule 4: Enforce a maximum of two trips per calendar day.
    final int sameDayTrips = driverTrips
        .where((trip) => _isSameDay(trip.start, startTime))
        .length;
    if (sameDayTrips >= 2) {
      throw TripValidationException(
        _localizedMessage(
          normalizedLanguage,
          'You have reached the daily limit of 2 trips.',
          'لقد وصلت إلى الحد اليومي المسموح به (رحلتان فقط).',
        ),
      );
    }
  }

  Future<void> ensureCanEditTrip({
    required String tripId,
    required String driverId,
    required DateTime updatedStartTime,
    required int updatedTotalSeats,
    required String languageCode,
  }) async {
    final String normalizedLanguage = _normalizeLanguage(languageCode);
    final String trimmedTripId = tripId.trim();
    if (trimmedTripId.isEmpty) {
      throw TripValidationException(
        _localizedMessage(
          normalizedLanguage,
          'Unable to edit this trip because it could not be found.',
          'تعذر العثور على الرحلة لتعديلها.',
        ),
      );
    }

    final DocumentSnapshot<Map<String, dynamic>> snapshot =
        await _firestore.collection('trips').doc(trimmedTripId).get();
    if (!snapshot.exists) {
      throw TripValidationException(
        _localizedMessage(
          normalizedLanguage,
          'Unable to edit this trip because it could not be found.',
          'تعذر العثور على الرحلة لتعديلها.',
        ),
      );
    }

    final Map<String, dynamic>? data = snapshot.data();
    if (data == null) {
      throw TripValidationException(
        _localizedMessage(
          normalizedLanguage,
          'Unable to edit this trip because it could not be found.',
          'تعذر العثور على الرحلة لتعديلها.',
        ),
      );
    }

    final DateTime? existingStart = _parseTripStart(data);
    final DateTime? existingEnd = _parseTripEnd(data, fallbackStart: existingStart);
    final DateTime now = DateTime.now();
    final bool isSameScheduledDay =
        existingStart != null && _isSameDay(existingStart, updatedStartTime);

    if (existingEnd != null && now.isAfter(existingEnd)) {
      throw TripValidationException(
        _localizedMessage(
          normalizedLanguage,
          'You cannot edit or delete a completed trip.',
          'لا يمكن تعديل أو حذف رحلة مكتملة أو منتهية.',
        ),
      );
    }

    if (existingStart != null) {
      final DateTime threshold = existingStart.subtract(const Duration(minutes: 30));
      if (!now.isBefore(threshold)) {
        throw TripValidationException(
          _localizedMessage(
            normalizedLanguage,
            'You cannot edit this trip within 30 minutes of departure.',
            'لا يمكنك تعديل الرحلة قبل موعد الانطلاق بـ30 دقيقة.',
          ),
        );
      }
    }

    final int activeBookings = await _countActiveBookings(trimmedTripId);
    if (activeBookings > 0) {
      throw TripValidationException(
        _localizedMessage(
          normalizedLanguage,
          'You cannot edit this trip after passengers have booked.',
          'لا يمكنك تعديل الرحلة بعد حجز أول راكب.',
        ),
      );
    }

    if (updatedTotalSeats < activeBookings) {
      throw TripValidationException(
        _localizedMessage(
          normalizedLanguage,
          'You cannot reduce seats below the number of booked passengers.',
          'لا يمكنك تقليل عدد المقاعد أقل من عدد المقاعد المحجوزة.',
        ),
      );
    }

    final QuerySnapshot<Map<String, dynamic>> driverTripsSnapshot = await _firestore
        .collection('trips')
        .where('driverId', isEqualTo: driverId)
        .get();
    final List<_TripRecord> driverTrips = driverTripsSnapshot.docs
        .where((doc) => doc.id != trimmedTripId)
        .map((doc) => _TripRecord(id: doc.id, data: doc.data()))
        .toList(growable: false);

    for (final _TripRecord trip in driverTrips) {
      final DateTime? tripStart = trip.start;
      if (tripStart == null) {
        continue;
      }
      final Duration difference = tripStart.difference(updatedStartTime).abs();
      if (_isSameDay(tripStart, updatedStartTime) && difference.inMinutes <= 60) {
        throw TripValidationException(
          _localizedMessage(
            normalizedLanguage,
            'You already have another trip scheduled around this time.',
            'لديك رحلة أخرى مجدولة في نفس الوقت تقريبًا.',
          ),
        );
      }
    }

    final int sameDayTrips = driverTrips
        .where((trip) => _isSameDay(trip.start, updatedStartTime))
        .length;
    if (!isSameScheduledDay && sameDayTrips >= 2) {
      throw TripValidationException(
        _localizedMessage(
          normalizedLanguage,
          'You have reached the daily limit of 2 trips.',
          'لقد وصلت إلى الحد اليومي المسموح به (رحلتان فقط).',
        ),
      );
    }
  }

  Future<void> ensureCanDeleteTrip({
    required String tripId,
    required String languageCode,
  }) async {
    final String normalizedLanguage = _normalizeLanguage(languageCode);
    final String trimmedTripId = tripId.trim();
    if (trimmedTripId.isEmpty) {
      throw TripValidationException(
        _localizedMessage(
          normalizedLanguage,
          'Unable to delete this trip because it could not be found.',
          'تعذر العثور على الرحلة لحذفها.',
        ),
      );
    }

    final DocumentSnapshot<Map<String, dynamic>> snapshot =
        await _firestore.collection('trips').doc(trimmedTripId).get();
    if (!snapshot.exists) {
      throw TripValidationException(
        _localizedMessage(
          normalizedLanguage,
          'Unable to delete this trip because it could not be found.',
          'تعذر العثور على الرحلة لحذفها.',
        ),
      );
    }

    final Map<String, dynamic>? data = snapshot.data();
    if (data == null) {
      throw TripValidationException(
        _localizedMessage(
          normalizedLanguage,
          'Unable to delete this trip because it could not be found.',
          'تعذر العثور على الرحلة لحذفها.',
        ),
      );
    }

    final DateTime? start = _parseTripStart(data);
    final DateTime? end = _parseTripEnd(data, fallbackStart: start);
    final DateTime now = DateTime.now();

    if (end != null && now.isAfter(end)) {
      throw TripValidationException(
        _localizedMessage(
          normalizedLanguage,
          'You cannot edit or delete a completed trip.',
          'لا يمكن تعديل أو حذف رحلة مكتملة أو منتهية.',
        ),
      );
    }

    final int activeBookings = await _countActiveBookings(trimmedTripId);
    if (activeBookings > 0) {
      throw TripValidationException(
        _localizedMessage(
          normalizedLanguage,
          'You cannot delete this trip while passengers are booked.',
          'لا يمكنك حذف الرحلة طالما هناك ركاب محجوزين.',
        ),
      );
    }
  }

  Future<int> _countActiveBookings(String tripId) async {
    final QuerySnapshot<Map<String, dynamic>> bookingsSnapshot = await _firestore
        .collection('bookings')
        .where('tripId', isEqualTo: tripId)
        .get();

    int activeCount = 0;
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in bookingsSnapshot.docs) {
      final Map<String, dynamic>? booking = doc.data();
      if (booking == null) {
        continue;
      }
      final String status = (booking['status'] ?? '').toString().toLowerCase();
      if (status != 'canceled') {
        activeCount += 1;
      }
    }
    return activeCount;
  }

  String _normalizeLanguage(String languageCode) {
    final String normalized = languageCode.trim().toLowerCase();
    if (normalized.startsWith('ar')) {
      return 'ar';
    }
    return 'en';
  }

  String _localizedMessage(String languageCode, String english, String arabic) {
    return languageCode == 'ar' ? arabic : english;
  }
}

class _TripRecord {
  _TripRecord({required this.id, required this.data});

  final String id;
  final Map<String, dynamic> data;

  DateTime? get start => _parseTripStart(data);

  DateTime? get end => _parseTripEnd(data, fallbackStart: start);
}

bool _isSameDay(DateTime? a, DateTime? b) {
  if (a == null || b == null) {
    return false;
  }
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

DateTime? _parseTripStart(Map<String, dynamic> data) {
  final dynamic dateValue = data['date'];
  final dynamic timeValue = data['time'];
  DateTime? baseDate;

  if (dateValue is Timestamp) {
    baseDate = dateValue.toDate();
  } else if (dateValue is String) {
    baseDate = _tryParseDate(dateValue);
  }

  if (baseDate == null) {
    return null;
  }

  if (timeValue is String) {
    final List<String> parts = timeValue.split(':');
    if (parts.length >= 2) {
      final int? hour = int.tryParse(parts[0]);
      final int? minute = int.tryParse(parts[1]);
      if (hour != null && minute != null) {
        return DateTime(baseDate.year, baseDate.month, baseDate.day, hour, minute);
      }
    }
  }

  return DateTime(baseDate.year, baseDate.month, baseDate.day, baseDate.hour, baseDate.minute);
}

DateTime? _parseTripEnd(Map<String, dynamic> data, {DateTime? fallbackStart}) {
  final dynamic explicitEnd = data['endDateTime'] ?? data['estimatedArrivalTime'] ?? data['arrivalDateTime'];
  DateTime? parsedEnd;
  if (explicitEnd is Timestamp) {
    parsedEnd = explicitEnd.toDate();
  } else if (explicitEnd is String) {
    parsedEnd = DateTime.tryParse(explicitEnd);
  }

  if (parsedEnd != null) {
    return parsedEnd;
  }

  final dynamic endDateValue = data['endDate'] ?? data['arrivalDate'];
  final dynamic endTimeValue = data['endTime'] ?? data['arrivalTime'];
  DateTime? endDate;

  if (endDateValue is Timestamp) {
    endDate = endDateValue.toDate();
  } else if (endDateValue is String) {
    endDate = _tryParseDate(endDateValue);
  }

  if (endDate != null) {
    if (endTimeValue is String) {
      final List<String> parts = endTimeValue.split(':');
      if (parts.length >= 2) {
        final int? hour = int.tryParse(parts[0]);
        final int? minute = int.tryParse(parts[1]);
        if (hour != null && minute != null) {
          return DateTime(endDate.year, endDate.month, endDate.day, hour, minute);
        }
      }
    }
    return DateTime(endDate.year, endDate.month, endDate.day, endDate.hour, endDate.minute);
  }

  final int durationMinutes = _parseInt(data['durationMinutes']);
  if (durationMinutes > 0 && fallbackStart != null) {
    return fallbackStart.add(Duration(minutes: durationMinutes));
  }

  final int estimatedDuration = _parseInt(data['estimatedDurationMinutes']);
  if (estimatedDuration > 0 && fallbackStart != null) {
    return fallbackStart.add(Duration(minutes: estimatedDuration));
  }

  if (fallbackStart == null) {
    return null;
  }

  return fallbackStart.add(const Duration(hours: 3));
}

DateTime? _tryParseDate(String value) {
  if (value.isEmpty) {
    return null;
  }
  final DateTime? parsed = DateTime.tryParse(value);
  if (parsed != null) {
    return parsed;
  }

  final List<String> parts = value.split('-');
  if (parts.length >= 3) {
    final int? year = int.tryParse(parts[0]);
    final int? month = int.tryParse(parts[1]);
    final int? day = int.tryParse(parts[2]);
    if (year != null && month != null && day != null) {
      return DateTime(year, month, day);
    }
  }

  return null;
}

int _parseInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}
