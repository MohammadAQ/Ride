import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:carpal_app/models/user_profile.dart';

/// A lightweight in-memory cache for Firestore-backed [UserProfile] documents.
///
/// This cache keeps already fetched profiles in memory and deduplicates
/// concurrent fetches for the same user. It returns `null` when the profile is
/// missing from Firestore and remembers that result to avoid redundant reads.
class UserProfileCache {
  UserProfileCache._();

  static final Map<String, UserProfile?> _cache = <String, UserProfile?>{};
  static final Map<String, Future<UserProfile?>> _inFlight =
      <String, Future<UserProfile?>>{};

  /// Returns a cached profile for [userId] if it exists, otherwise `null`.
  static UserProfile? get(String userId) {
    final String trimmedId = userId.trim();
    if (trimmedId.isEmpty) {
      return null;
    }
    return _cache[trimmedId];
  }

  /// Whether the cache already contains an entry (including `null`) for the
  /// provided [userId].
  static bool hasEntry(String userId) {
    final String trimmedId = userId.trim();
    if (trimmedId.isEmpty) {
      return false;
    }
    return _cache.containsKey(trimmedId);
  }

  /// Stores [profile] in the cache.
  static void storeProfile(UserProfile profile) {
    final String trimmedId = profile.id.trim();
    if (trimmedId.isEmpty) {
      return;
    }
    _cache[trimmedId] = profile;
  }

  /// Marks a user as missing so subsequent lookups do not trigger another
  /// Firestore read.
  static void markMissing(String userId) {
    final String trimmedId = userId.trim();
    if (trimmedId.isEmpty) {
      return;
    }
    _cache[trimmedId] = null;
  }

  /// Fetches the profile from Firestore unless it is already cached.
  static Future<UserProfile?> fetch(
    String userId, {
    bool forceRefresh = false,
  }) async {
    final String trimmedId = userId.trim();
    if (trimmedId.isEmpty) {
      return null;
    }

    if (!forceRefresh) {
      if (_cache.containsKey(trimmedId)) {
        return _cache[trimmedId];
      }
      final Future<UserProfile?>? pending = _inFlight[trimmedId];
      if (pending != null) {
        return pending;
      }
    }

    Future<UserProfile?> future = _loadFromFirestore(trimmedId);
    if (!forceRefresh) {
      _inFlight[trimmedId] = future;
    }

    try {
      final UserProfile? profile = await future;
      if (profile != null) {
        _cache[trimmedId] = profile;
      } else {
        _cache[trimmedId] = null;
      }
      return profile;
    } catch (_) {
      return _cache[trimmedId];
    } finally {
      if (!forceRefresh) {
        _inFlight.remove(trimmedId);
      }
    }
  }

  static Future<UserProfile?> _loadFromFirestore(String userId) async {
    final DocumentSnapshot<Map<String, dynamic>> snapshot = await FirebaseFirestore
        .instance
        .collection('users')
        .doc(userId)
        .get();

    if (!snapshot.exists) {
      return null;
    }

    return UserProfile.fromFirestoreSnapshot(snapshot);
  }
}
