import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfile {
  const UserProfile({
    required this.id,
    required this.displayName,
    this.email,
    this.phone,
    this.photoUrl,
    this.tripCount,
    this.reviewsCount,
    this.rating,
  });

  final String id;
  final String displayName;
  final String? email;
  final String? phone;
  final String? photoUrl;
  final int? tripCount;
  final int? reviewsCount;
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

  static const Object _unset = Object();

  UserProfile copyWith({
    String? displayName,
    Object? email = _unset,
    Object? phone = _unset,
    Object? photoUrl = _unset,
    Object? tripCount = _unset,
    Object? reviewsCount = _unset,
    Object? rating = _unset,
  }) {
    return UserProfile(
      id: id,
      displayName: displayName ?? this.displayName,
      email: email == _unset ? this.email : email as String?,
      phone: phone == _unset ? this.phone : phone as String?,
      photoUrl: photoUrl == _unset ? this.photoUrl : photoUrl as String?,
      tripCount: tripCount == _unset ? this.tripCount : tripCount as int?,
      reviewsCount: reviewsCount == _unset
          ? this.reviewsCount
          : reviewsCount as int?,
      rating: rating == _unset ? this.rating : rating as double?,
    );
  }

  static UserProfile fromFirestore(String id, Map<String, dynamic> data) {
    return UserProfile(
      id: id,
      displayName: _resolveDisplayName(data),
      email: null,
      phone: sanitizeOptionalText(data['phone']),
      photoUrl: _sanitizeUrl(data['photoUrl']),
      tripCount: _toInt(data['tripCount'] ?? data['tripsCount']),
      reviewsCount: _toInt(data['reviewsCount']),
      rating: _toDouble(data['rating']),
    );
  }

  static UserProfile fromFirestoreSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    return fromFirestore(snapshot.id, snapshot.data() ?? <String, dynamic>{});
  }

  static final RegExp _emailPattern =
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$', caseSensitive: false);

  static String sanitizeDisplayName(dynamic value) {
    final String? sanitized = sanitizeOptionalText(value);
    if (sanitized == null) {
      return 'مستخدم';
    }
    if (_emailPattern.hasMatch(sanitized)) {
      return 'مستخدم';
    }
    return sanitized;
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

  static String _resolveDisplayName(Map<String, dynamic> data) {
    final List<dynamic> candidates = <dynamic>[
      data['displayName'],
      data['fullName'],
      data['name'],
      data['username'],
      _combineNameParts(data['firstName'], data['lastName']),
    ];

    for (final dynamic candidate in candidates) {
      final String sanitized = sanitizeDisplayName(candidate);
      if (sanitized != 'مستخدم') {
        return sanitized;
      }
    }

    return 'مستخدم';
  }

  static String? _combineNameParts(dynamic first, dynamic last) {
    final String? firstName = sanitizeOptionalText(first);
    final String? lastName = sanitizeOptionalText(last);
    if (firstName == null && lastName == null) {
      return null;
    }
    if (firstName != null && lastName != null) {
      return '$firstName $lastName'.trim();
    }
    return firstName ?? lastName;
  }
}
