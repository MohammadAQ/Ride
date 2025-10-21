import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  const ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'ApiException(statusCode: $statusCode, message: $message)';
}

class TripsResponse {
  const TripsResponse({required this.trips, this.nextCursor});

  final List<Map<String, dynamic>> trips;
  final String? nextCursor;
}

class ApiService {
  ApiService({http.Client? client}) : _client = client ?? http.Client();

  static String get baseUrl {
    if (kIsWeb) {
      return 'http://localhost:8080/api/v1';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'http://10.0.2.2:8080/api/v1';
      default:
        return 'http://localhost:8080/api/v1';
    }
  }

  final http.Client _client;

  Future<String?> _getToken({required bool requiredForRequest}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (requiredForRequest) {
        throw const ApiException(401, 'User is not authenticated');
      }
      return null;
    }

    return user.getIdToken();
  }

  Map<String, String> _buildHeaders({String? token, bool withJson = false}) {
    final headers = <String, String>{
      'Accept': 'application/json',
    };
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    if (withJson) {
      headers['Content-Type'] = 'application/json';
    }
    return headers;
  }

  void _logResponse(String method, Uri uri, http.Response response) {
    if (!kDebugMode) {
      return;
    }

    debugPrint(
      '[ApiService] $method ${uri.toString()} -> ${response.statusCode}: ${response.body}',
    );
  }

  Never _throwForResponse(String method, Uri uri, http.Response response) {
    String message = 'Request failed with status code ${response.statusCode}';

    try {
      if (response.bodyBytes.isNotEmpty) {
        final decoded = json.decode(utf8.decode(response.bodyBytes));
        if (decoded is Map<String, dynamic> && decoded['message'] != null) {
          message = decoded['message'].toString();
        }
      }
    } catch (_) {
      // Ignore JSON parsing issues for error responses and fall back to the default message.
    }

    throw ApiException(response.statusCode, message);
  }

  dynamic _parseSuccessBody(http.Response response) {
    if (response.bodyBytes.isEmpty) {
      return null;
    }

    final bodyString = utf8.decode(response.bodyBytes);

    try {
      return json.decode(bodyString);
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          '[ApiService] Failed to decode response from '
          '${response.request?.url.toString() ?? 'unknown'}: $error',
        );
        debugPrint(stackTrace.toString());
      }
      throw const ApiException(
        500,
        'تعذر قراءة استجابة الخادم. يرجى المحاولة مرة أخرى لاحقًا.',
      );
    }
  }

  List<Map<String, dynamic>> _normaliseTripList(List<dynamic> source) {
    final trips = <Map<String, dynamic>>[];

    for (final item in source) {
      if (item is Map<String, dynamic>) {
        trips.add(Map<String, dynamic>.from(item));
      } else if (item is Map) {
        trips.add(item.map((key, value) => MapEntry(key.toString(), value)));
      }
    }

    return trips;
  }

  List<Map<String, dynamic>> _extractTrips(dynamic decoded) {
    if (decoded == null) {
      return <Map<String, dynamic>>[];
    }

    if (decoded is List) {
      return _normaliseTripList(decoded);
    }

    if (decoded is Map<String, dynamic>) {
      final data = decoded['trips'] ?? decoded['data'] ?? decoded['results'];
      if (data is List) {
        return _normaliseTripList(data);
      }
      return <Map<String, dynamic>>[];
    }

    if (decoded is Map) {
      final map = decoded.map((key, value) => MapEntry(key.toString(), value));
      final data = map['trips'] ?? map['data'] ?? map['results'];
      if (data is List) {
        return _normaliseTripList(data);
      }
    }

    return <Map<String, dynamic>>[];
  }

  String? _extractNextCursor(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      final next = decoded['nextCursor'] ?? decoded['cursor'];
      if (next == null) {
        return null;
      }
      if (next is String) {
        return next.isEmpty ? null : next;
      }
      final nextAsString = next.toString();
      return nextAsString.isEmpty ? null : nextAsString;
    }

    if (decoded is Map) {
      final map = decoded.map((key, value) => MapEntry(key.toString(), value));
      final next = map['nextCursor'] ?? map['cursor'];
      if (next == null) {
        return null;
      }
      if (next is String) {
        return next.isEmpty ? null : next;
      }
      final nextAsString = next.toString();
      return nextAsString.isEmpty ? null : nextAsString;
    }

    return null;
  }

  Map<String, dynamic> _mapFromDynamic(dynamic data) {
    if (data == null) {
      return <String, dynamic>{};
    }

    if (data is Map<String, dynamic>) {
      return Map<String, dynamic>.from(data);
    }

    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), value));
    }

    return <String, dynamic>{};
  }

  Future<TripsResponse> fetchTrips({
    String? fromCity,
    String? toCity,
    int? limit,
    String? cursor,
  }) async {
    final params = <String, String>{};
    if (fromCity != null && fromCity.trim().isNotEmpty) {
      params['fromCity'] = fromCity.trim();
    }
    if (toCity != null && toCity.trim().isNotEmpty) {
      params['toCity'] = toCity.trim();
    }
    if (limit != null) {
      params['limit'] = limit.toString();
    }
    if (cursor != null && cursor.isNotEmpty) {
      params['cursor'] = cursor;
    }
    final uri = Uri.parse('$baseUrl/trips').replace(queryParameters: params.isEmpty ? null : params);
    final token = await _getToken(requiredForRequest: false);
    final response = await _client.get(uri, headers: _buildHeaders(token: token));

    _logResponse('GET', uri, response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwForResponse('GET', uri, response);
    }

    final body = _parseSuccessBody(response);
    final trips = _extractTrips(body);
    final nextCursor = _extractNextCursor(body);

    return TripsResponse(trips: trips, nextCursor: nextCursor);
  }

  Future<TripsResponse> fetchMyTrips({int? limit, String? cursor}) async {
    final params = <String, String>{};
    if (limit != null) {
      params['limit'] = limit.toString();
    }
    if (cursor != null && cursor.isNotEmpty) {
      params['cursor'] = cursor;
    }

    final uri = Uri.parse('$baseUrl/trips/mine').replace(queryParameters: params.isEmpty ? null : params);
    final token = await _getToken(requiredForRequest: true);
    final response = await _client.get(uri, headers: _buildHeaders(token: token));

    _logResponse('GET', uri, response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwForResponse('GET', uri, response);
    }

    final body = _parseSuccessBody(response);
    final trips = _extractTrips(body);
    final nextCursor = _extractNextCursor(body);

    return TripsResponse(trips: trips, nextCursor: nextCursor);
  }

  Future<Map<String, dynamic>> createTrip(Map<String, dynamic> payload) async {
    final token = await _getToken(requiredForRequest: true);
    final uri = Uri.parse('$baseUrl/trips');
    final response = await _client.post(
      uri,
      headers: _buildHeaders(token: token, withJson: true),
      body: json.encode(payload),
    );

    _logResponse('POST', uri, response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwForResponse('POST', uri, response);
    }

    return _mapFromDynamic(_parseSuccessBody(response));
  }

  Future<Map<String, dynamic>> updateTrip(String id, Map<String, dynamic> payload) async {
    final token = await _getToken(requiredForRequest: true);
    final uri = Uri.parse('$baseUrl/trips/$id');
    final response = await _client.patch(
      uri,
      headers: _buildHeaders(token: token, withJson: true),
      body: json.encode(payload),
    );

    _logResponse('PATCH', uri, response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwForResponse('PATCH', uri, response);
    }

    return _mapFromDynamic(_parseSuccessBody(response));
  }

  Future<void> deleteTrip(String id) async {
    final token = await _getToken(requiredForRequest: true);
    final uri = Uri.parse('$baseUrl/trips/$id');
    final response = await _client.delete(
      uri,
      headers: _buildHeaders(token: token),
    );

    _logResponse('DELETE', uri, response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwForResponse('DELETE', uri, response);
    }
  }
}
