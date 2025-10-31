import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:ride/models/ride_request.dart';

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
        .map((snapshot) {
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

  Future<void> updateRequestStatus({
    required String requestId,
    required String status,
    String reason = '',
    int? seatsRequested,
    String? rideId,
  }) async {
    final DocumentReference<Map<String, dynamic>> requestRef =
        _collection.doc(requestId);

    await _firestore.runTransaction((Transaction transaction) async {
      final DocumentSnapshot<Map<String, dynamic>> requestSnapshot =
          await transaction.get(requestRef);

      if (!requestSnapshot.exists) {
        return;
      }

      transaction.update(requestRef, <String, dynamic>{
        'status': status,
        'reason': reason,
      });

      if (status != 'accepted' || rideId == null || rideId.trim().isEmpty) {
        // TODO: Trigger notification for the passenger when status changes.
        return;
      }

      final Map<String, dynamic> requestData =
          requestSnapshot.data() ?? <String, dynamic>{};
      final int seats = seatsRequested ?? _parseInt(requestData['seats_requested']);
      final DocumentReference<Map<String, dynamic>> rideRef =
          _firestore.collection('trips').doc(rideId);
      final DocumentSnapshot<Map<String, dynamic>> rideSnapshot =
          await transaction.get(rideRef);

      if (!rideSnapshot.exists) {
        return;
      }

      final Map<String, dynamic> rideData =
          rideSnapshot.data() ?? <String, dynamic>{};
      final int currentSeats = _parseInt(rideData['availableSeats']);
      final int updatedSeats = math.max(0, currentSeats - seats);

      transaction.update(rideRef, <String, dynamic>{
        'availableSeats': updatedSeats,
      });

      // TODO: Trigger notification for the passenger when status changes.
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
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }
}
