import 'package:cloud_firestore/cloud_firestore.dart';

enum RideRequestStatus {
  pending,
  accepted,
  rejected,
  canceledByPassenger,
}

class RideRequest {
  const RideRequest({
    required this.id,
    required this.rideId,
    required this.driverId,
    required this.passengerId,
    required this.status,
    required this.reason,
    required this.seatsRequested,
    this.createdAt,
  });

  final String id;
  final String rideId;
  final String driverId;
  final String passengerId;
  final RideRequestStatus status;
  final String reason;
  final int seatsRequested;
  final DateTime? createdAt;

  bool get hasReason => reason.trim().isNotEmpty;

  static RideRequest fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final Map<String, dynamic> data = snapshot.data() ?? <String, dynamic>{};
    return RideRequest(
      id: snapshot.id,
      rideId: _string(data['ride_id']),
      driverId: _string(data['driver_id']),
      passengerId: _string(data['passenger_id']),
      status: _statusFromString(_string(data['status'])),
      reason: _string(data['reason']),
      seatsRequested: _int(data['seats_requested']),
      createdAt: _timestampToDate(data['created_at']),
    );
  }

  static RideRequest fromQuerySnapshot(
    QueryDocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    return fromSnapshot(snapshot);
  }

  RideRequest copyWith({
    RideRequestStatus? status,
    String? reason,
    int? seatsRequested,
    DateTime? createdAt,
  }) {
    return RideRequest(
      id: id,
      rideId: rideId,
      driverId: driverId,
      passengerId: passengerId,
      status: status ?? this.status,
      reason: reason ?? this.reason,
      seatsRequested: seatsRequested ?? this.seatsRequested,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  static RideRequestStatus _statusFromString(String value) {
    switch (value.toLowerCase()) {
      case 'accepted':
        return RideRequestStatus.accepted;
      case 'rejected':
        return RideRequestStatus.rejected;
      case 'canceled_by_passenger':
        return RideRequestStatus.canceledByPassenger;
      case 'pending':
      default:
        return RideRequestStatus.pending;
    }
  }

  static String _string(dynamic value) {
    if (value == null) {
      return '';
    }
    return value.toString().trim();
  }

  static int _int(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    final String text = _string(value);
    if (text.isEmpty) {
      return 1;
    }
    return int.tryParse(text) ?? 1;
  }

  static DateTime? _timestampToDate(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return null;
  }
}
