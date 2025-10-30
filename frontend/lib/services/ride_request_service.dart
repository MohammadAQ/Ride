import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/ride_request.dart';

class RideRequestService {
  RideRequestService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String collectionName = 'ride_requests';

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(collectionName);

  static String buildRequestId(String rideId, String passengerId) {
    return '${rideId}_$passengerId';
  }

  Stream<RideRequest?> watchRequest({
    required String rideId,
    required String passengerId,
  }) {
    final String documentId = buildRequestId(rideId, passengerId);
    return _collection.doc(documentId).snapshots().map((snapshot) {
      if (!snapshot.exists) {
        return null;
      }
      return RideRequest.fromSnapshot(snapshot);
    });
  }

  Stream<List<RideRequest>> watchDriverPendingRequests(String driverId) {
    return _collection
        .where('driver_id', isEqualTo: driverId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) {
          final List<RideRequest> requests = snapshot.docs
              .map(RideRequest.fromSnapshot)
              .toList(growable: false);
          requests.sort((RideRequest a, RideRequest b) {
            final DateTime? aTime = a.timestamp;
            final DateTime? bTime = b.timestamp;
            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            return bTime.compareTo(aTime);
          });
          return requests;
        });
  }

  Stream<List<RideRequest>> watchPassengerRequests(String passengerId) {
    return _collection
        .where('passenger_id', isEqualTo: passengerId)
        .snapshots()
        .map((snapshot) {
          final List<RideRequest> requests = snapshot.docs
              .map(RideRequest.fromSnapshot)
              .toList(growable: false);
          requests.sort((RideRequest a, RideRequest b) {
            final DateTime? aTime = a.timestamp;
            final DateTime? bTime = b.timestamp;
            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            return bTime.compareTo(aTime);
          });
          return requests;
        });
  }

  Future<void> createRideRequest({
    required String rideId,
    required String driverId,
    required String passengerId,
  }) async {
    final String documentId = buildRequestId(rideId, passengerId);
    final Map<String, dynamic> data = <String, dynamic>{
      'ride_id': rideId,
      'driver_id': driverId,
      'passenger_id': passengerId,
      'status': 'pending',
      'reason': '',
      'timestamp': FieldValue.serverTimestamp(),
    };

    await _collection.doc(documentId).set(data, SetOptions(merge: true));
  }

  Future<void> acceptRequest(String requestId) {
    return _collection.doc(requestId).update(<String, dynamic>{
      'status': 'accepted',
      'reason': '',
    });
  }

  Future<void> rejectRequest(String requestId, String reason) {
    return _collection.doc(requestId).update(<String, dynamic>{
      'status': 'rejected',
      'reason': reason,
    });
  }
}
