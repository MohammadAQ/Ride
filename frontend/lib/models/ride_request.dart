import 'package:cloud_firestore/cloud_firestore.dart';

class RideRequest {
  const RideRequest({
    required this.id,
    required this.rideId,
    required this.driverId,
    required this.passengerId,
    required this.status,
    required this.reason,
    required this.timestamp,
  });

  final String id;
  final String rideId;
  final String driverId;
  final String passengerId;
  final String status;
  final String reason;
  final DateTime? timestamp;

  factory RideRequest.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final Map<String, dynamic>? data = snapshot.data();
    return RideRequest(
      id: snapshot.id,
      rideId: (data?['ride_id'] ?? '').toString(),
      driverId: (data?['driver_id'] ?? '').toString(),
      passengerId: (data?['passenger_id'] ?? '').toString(),
      status: (data?['status'] ?? 'pending').toString(),
      reason: (data?['reason'] ?? '').toString(),
      timestamp: _parseTimestamp(data?['timestamp']),
    );
  }

  static DateTime? _parseTimestamp(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return null;
  }
}
