import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:ride/models/ride_request.dart';

class RideRequestException implements Exception {
  RideRequestException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'RideRequestException(code: $code, message: $message)';
}

class RideRequestService {
  RideRequestService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('ride_requests');

  Future<RideRequest> createRideRequest({
    required String rideId,
    required String driverId,
    required String passengerId,
    int seatsRequested = 1,
  }) async {
    final QuerySnapshot<Map<String, dynamic>> existing = await _collection
        .where('ride_id', isEqualTo: rideId)
        .where('passenger_id', isEqualTo: passengerId)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      return RideRequest.fromQuerySnapshot(existing.docs.first);
    }

    final DocumentReference<Map<String, dynamic>> ref = await _collection.add({
      'ride_id': rideId,
      'driver_id': driverId,
      'passenger_id': passengerId,
      'status': 'pending',
      'reason': '',
      'seats_requested': seatsRequested,
      'created_at': FieldValue.serverTimestamp(),
    });

    return RideRequest(
      id: ref.id,
      rideId: rideId,
      driverId: driverId,
      passengerId: passengerId,
      status: RideRequestStatus.pending,
      reason: '',
      seatsRequested: seatsRequested,
      createdAt: null,
    );
  }

  Stream<List<RideRequest>> passengerRequestsStream(String passengerId) {
    final String trimmedId = passengerId.trim();
    if (trimmedId.isEmpty) {
      return const Stream<List<RideRequest>>.empty();
    }

    return _collection
        .where('passenger_id', isEqualTo: trimmedId)
        .orderBy('created_at', descending: true)
        .snapshots()
        .map(
      (QuerySnapshot<Map<String, dynamic>> snapshot) {
        return snapshot.docs
            .map(RideRequest.fromQuerySnapshot)
            .toList(growable: false);
      },
    );
  }

  Stream<RideRequest?> requestForPassengerStream({
    required String rideId,
    required String passengerId,
  }) {
    final String trimmedRideId = rideId.trim();
    final String trimmedPassengerId = passengerId.trim();
    if (trimmedRideId.isEmpty || trimmedPassengerId.isEmpty) {
      return const Stream<RideRequest?>.empty();
    }

    return _collection
        .where('ride_id', isEqualTo: trimmedRideId)
        .where('passenger_id', isEqualTo: trimmedPassengerId)
        .orderBy('created_at', descending: true)
        .limit(1)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snapshot) {
      if (snapshot.docs.isEmpty) {
        return null;
      }
      return RideRequest.fromQuerySnapshot(snapshot.docs.first);
    });
  }

  Stream<List<RideRequest>> pendingRequestsForRideStream({
    required String driverId,
    required String rideId,
  }) {
    final String trimmedDriverId = driverId.trim();
    final String trimmedRideId = rideId.trim();
    if (trimmedDriverId.isEmpty || trimmedRideId.isEmpty) {
      return const Stream<List<RideRequest>>.empty();
    }

    return _collection
        .where('driver_id', isEqualTo: trimmedDriverId)
        .where('ride_id', isEqualTo: trimmedRideId)
        .where('status', isEqualTo: 'pending')
        .orderBy('created_at', descending: true)
        .snapshots()
        .map(
      (QuerySnapshot<Map<String, dynamic>> snapshot) {
        return snapshot.docs
            .map(RideRequest.fromQuerySnapshot)
            .toList(growable: false);
      },
    );
  }

  Future<void> cancelPendingRequest({
    required String rideId,
    required String passengerId,
  }) async {
    final QuerySnapshot<Map<String, dynamic>> querySnapshot = await _collection
        .where('ride_id', isEqualTo: rideId.trim())
        .where('passenger_id', isEqualTo: passengerId.trim())
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    if (querySnapshot.docs.isEmpty) {
      return;
    }

    final QueryDocumentSnapshot<Map<String, dynamic>> doc =
        querySnapshot.docs.first;
    await _collection.doc(doc.id).update(<String, dynamic>{
      'status': 'canceled_by_passenger',
      'reason': 'Canceled by passenger',
    });
  }

  Future<void> rejectRideRequest({
    required String requestId,
    required String reason,
  }) async {
    final String trimmedRequestId = requestId.trim();
    if (trimmedRequestId.isEmpty) {
      throw RideRequestException('invalid-request', 'requestId cannot be empty');
    }

    await _collection.doc(trimmedRequestId).update(<String, dynamic>{
      'status': 'rejected',
      'reason': reason.trim(),
    });
  }

  Future<void> acceptRideRequest({
    required String rideId,
    required String requestId,
  }) async {
    final String trimmedRideId = rideId.trim();
    final String trimmedRequestId = requestId.trim();

    if (trimmedRideId.isEmpty) {
      throw RideRequestException('invalid-ride', 'rideId cannot be empty');
    }
    if (trimmedRequestId.isEmpty) {
      throw RideRequestException('invalid-request', 'requestId cannot be empty');
    }

    final DocumentReference<Map<String, dynamic>> requestRef =
        _collection.doc(trimmedRequestId);

    await _firestore.runTransaction((Transaction transaction) async {
      final DocumentSnapshot<Map<String, dynamic>> requestSnapshot =
          await transaction.get(requestRef);

      if (!requestSnapshot.exists) {
        throw RideRequestException(
          'request-not-found',
          'Ride request not found',
        );
      }

      final Map<String, dynamic> requestData =
          requestSnapshot.data() ?? <String, dynamic>{};
      final String status =
          (requestData['status'] ?? 'pending').toString().toLowerCase();

      if (status != 'pending') {
        throw RideRequestException(
          'request-not-pending',
          'Request is not pending',
        );
      }

      final int seatsRequested = _parseInt(requestData['seats_requested']);

      DocumentReference<Map<String, dynamic>> rideRef =
          _firestore.collection('rides').doc(trimmedRideId);
      DocumentSnapshot<Map<String, dynamic>> rideSnapshot =
          await transaction.get(rideRef);

      if (!rideSnapshot.exists) {
        final DocumentReference<Map<String, dynamic>> fallbackRef =
            _firestore.collection('trips').doc(trimmedRideId);
        final DocumentSnapshot<Map<String, dynamic>> fallbackSnapshot =
            await transaction.get(fallbackRef);
        if (!fallbackSnapshot.exists) {
          throw RideRequestException(
            'ride-not-found',
            'Ride not found',
          );
        }
        rideRef = fallbackRef;
        rideSnapshot = fallbackSnapshot;
      }

      final Map<String, dynamic> rideData =
          rideSnapshot.data() ?? <String, dynamic>{};
      final int seatsAvailable =
          _parseInt(rideData['available_seats'] ?? rideData['availableSeats']);

      if (seatsAvailable < seatsRequested) {
        throw RideRequestException(
          'not_enough_seats',
          'Not enough seats available',
        );
      }

      transaction.update(requestRef, <String, dynamic>{
        'status': 'accepted',
        'reason': '',
      });

      final int updatedSeats = seatsAvailable - seatsRequested;
      transaction.update(rideRef, <String, dynamic>{
        'available_seats': updatedSeats,
        'availableSeats': updatedSeats,
      });
    });
  }

  int _parseInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      final int? parsed = int.tryParse(value);
      if (parsed != null) {
        return parsed;
      }
    }
    return 0;
  }
}
