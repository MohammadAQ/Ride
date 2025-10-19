import 'package:cloud_firestore/cloud_firestore.dart';

class User {
  final String id;
  final String email;
  final String username;
  final String role; // 'driver' or 'passenger'
  final double? rating; // For drivers, optional

  User({
    required this.id,
    required this.email,
    required this.username,
    required this.role,
    this.rating,
  });

  factory User.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map<String, dynamic>;
    return User(
      id: doc.id,
      email: data['email'] ?? '',
      username: data['username'] ?? '',
      role: data['role'] ?? 'passenger',
      rating: (data['rating'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'email': email,
      'username': username,
      'role': role,
      'rating': rating,
    };
  }
}

