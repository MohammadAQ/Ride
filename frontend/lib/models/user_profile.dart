import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfile {
  const UserProfile({
    required this.id,
    required this.displayName,
    this.email,
    this.phone,
    this.photoUrl,
    this.tripsCount,
    this.rating,
  });

  final String id;
  final String displayName;
  final String? email;
  final String? phone;
  final String? photoUrl;
  final int? tripsCount;
  final double? rating;

  String get initial {
    final String trimmed = displayName.trim();
    if (trimmed.isNotEmpty &&
        trimmed != 'مستخدم' &&
        trimmed.toLowerCase() != 'user') {
      return trimmed[0].toUpperCase();
    }
    final String trimmedId = id.trim();
    if (trimmedId.isNotEmpty) {
      return trimmedId[0].toUpperCase();
    }
    return '?';
  }

  UserProfile copyWith({
    String? displayName,
    String? email,
    String? phone,
    String? photoUrl,
    int? tripsCount,
    double? rating,
  }) {
    return UserProfile(
      id: id,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      photoUrl: photoUrl ?? this.photoUrl,
      tripsCount: tripsCount ?? this.tripsCount,
      rating: rating ?? this.rating,
    );
  }

  static UserProfile fromFirestore(String id, Map<String, dynamic> data) {
    return UserProfile(
      id: id,
      displayName: sanitizeDisplayName(data['displayName']),
      email: sanitizeOptionalText(data['email']),
      phone: sanitizeOptionalText(data['phone']),
      photoUrl: _sanitizeUrl(data['photoUrl']),
      tripsCount: _toInt(data['tripsCount']),
      rating: _toDouble(data['rating']),
    );
  }

  static UserProfile fromFirestoreSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    return fromFirestore(snapshot.id, snapshot.data() ?? <String, dynamic>{});
  }

  static String sanitizeDisplayName(dynamic value) {
    return sanitizeOptionalText(value) ?? 'مستخدم';
  }

  static String? sanitizeOptionalText(dynamic value) {
    if (value == null) return null;
    final String text = value.toString().trim();
    if (text.isEmpty) return null;
    return text.replaceAll(
      RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]'),
      '',
    );
  }

  static String? sanitizePhotoUrl(dynamic value) => _sanitizeUrl(value);

  static String? _sanitizeUrl(dynamic value) {
    if (value == null) return null;
    final String text = value.toString().trim();
    if (text.isEmpty) return null;
    final Uri? uri = Uri.tryParse(text);
    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      return null;
    }
    return text;
  }

  static int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString());
  }
}
