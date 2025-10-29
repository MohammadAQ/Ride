import 'user_profile.dart';

class Trip {
  const Trip({
    required this.id,
    required this.driverId,
    required this.driverName,
    required this.fromCity,
    required this.toCity,
    required this.date,
    required this.time,
    required this.price,
    required this.carModel,
    required this.carColor,
    required this.phoneNumber,
    this.notes,
    required this.totalSeats,
    required this.availableSeats,
    required this.bookedUsers,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String driverId;
  final String driverName;
  final String fromCity;
  final String toCity;
  final DateTime date;
  final String time;
  final double price;
  final String carModel;
  final String carColor;
  final String phoneNumber;
  final String? notes;
  final int totalSeats;
  final int availableSeats;
  final List<String> bookedUsers;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Trip.fromJson(Map<String, dynamic> json) {
    List<String> parseBookedUsers(dynamic value) {
      if (value is List) {
        return value
            .map((dynamic item) => item?.toString())
            .whereType<String>()
            .map((String userId) => userId.trim())
            .where((String userId) => userId.isNotEmpty)
            .toList(growable: false);
      }
      return <String>[];
    }

    int parseInt(dynamic value, [int defaultValue = 0]) {
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.toInt();
      }
      final int? parsed = int.tryParse(value?.toString() ?? '');
      return parsed ?? defaultValue;
    }

    final List<String> bookedUsers = parseBookedUsers(json['bookedUsers']);
    final int availableSeats = parseInt(json['availableSeats'], 0);
    final int totalSeats = () {
      final int parsedTotal = parseInt(json['totalSeats'], 0);
      if (parsedTotal > 0) {
        return parsedTotal;
      }
      return bookedUsers.length + availableSeats;
    }();

    return Trip(
      id: json['id']?.toString() ?? '',
      driverId: json['driverId']?.toString() ?? '',
      driverName: UserProfile.sanitizeDisplayName(json['driverName']),
      fromCity: json['fromCity']?.toString() ?? '',
      toCity: json['toCity']?.toString() ?? '',
      date: DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now(),
      time: json['time']?.toString() ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      carModel: json['carModel']?.toString() ?? '',
      carColor: json['carColor']?.toString() ?? '',
      phoneNumber: json['phoneNumber']?.toString() ?? '',
      notes: json['notes']?.toString(),
      totalSeats: totalSeats,
      availableSeats: availableSeats,
      bookedUsers: bookedUsers,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'driverId': driverId,
      'driverName': driverName,
      'fromCity': fromCity,
      'toCity': toCity,
      'date': date.toIso8601String(),
      'time': time,
      'price': price,
      'carModel': carModel,
      'carColor': carColor,
      'phoneNumber': phoneNumber,
      if (notes != null) 'notes': notes,
      'totalSeats': totalSeats,
      'availableSeats': availableSeats,
      'bookedUsers': bookedUsers,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}
