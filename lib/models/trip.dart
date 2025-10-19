import 'package:cloud_firestore/cloud_firestore.dart';

class Trip {
  final String id;
  final String driverId;
  final String startPoint;
  final String destination;
  final DateTime time;
  final int availableSeats;
  final double suggestedCost;
  final List<String> passengers;

  Trip({
    required this.id,
    required this.driverId,
    required this.startPoint,
    required this.destination,
    required this.time,
    required this.availableSeats,
    required this.suggestedCost,
    this.passengers = const [],
  });

  factory Trip.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map<String, dynamic>;
    return Trip(
      id: doc.id,
      driverId: data['driverId'] ?? '',
      startPoint: data['startPoint'] ?? '',
      destination: data['destination'] ?? '',
      time: (data['time'] as Timestamp).toDate(),
      availableSeats: data['availableSeats'] ?? 0,
      suggestedCost: (data['suggestedCost'] as num?)?.toDouble() ?? 0.0,
      passengers: List<String>.from(data['passengers'] ?? []),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'driverId': driverId,
      'startPoint': startPoint,
      'destination': destination,
      'time': Timestamp.fromDate(time),
      'availableSeats': availableSeats,
      'suggestedCost': suggestedCost,
      'passengers': passengers,
    };
  }
}

