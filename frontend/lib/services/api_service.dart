import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.statusCode, this.message);

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

  static const String baseUrl = 'http://10.0.2.2:8080/api/v1';

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
    final headers = <String, String>{};
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    if (withJson) {
      headers['Content-Type'] = 'application/json';
    }
    return headers;
  }

  Map<String, dynamic> _decodeBody(http.Response response) {
    if (response.body.isEmpty) {
      return <String, dynamic>{};
    }

    return json.decode(response.body) as Map<String, dynamic>;
  }

  Never _throwForResponse(http.Response response) {
    final body = _decodeBody(response);
    final message = body['message']?.toString() ?? 'Request failed';
    throw ApiException(response.statusCode, message);
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

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwForResponse(response);
    }

    final body = _decodeBody(response);
    final trips = (body['data'] as List<dynamic>? ?? <dynamic>[])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final nextCursor = body['nextCursor'] as String?;

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

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwForResponse(response);
    }

    final body = _decodeBody(response);
    final trips = (body['data'] as List<dynamic>? ?? <dynamic>[])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final nextCursor = body['nextCursor'] as String?;

    return TripsResponse(trips: trips, nextCursor: nextCursor);
  }

  Future<Map<String, dynamic>> createTrip(Map<String, dynamic> payload) async {
    final token = await _getToken(requiredForRequest: true);
    final response = await _client.post(
      Uri.parse('$baseUrl/trips'),
      headers: _buildHeaders(token: token, withJson: true),
      body: json.encode(payload),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwForResponse(response);
    }

    return _decodeBody(response);
  }

  Future<Map<String, dynamic>> updateTrip(String id, Map<String, dynamic> payload) async {
    final token = await _getToken(requiredForRequest: true);
    final response = await _client.patch(
      Uri.parse('$baseUrl/trips/$id'),
      headers: _buildHeaders(token: token, withJson: true),
      body: json.encode(payload),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwForResponse(response);
    }

    return _decodeBody(response);
  }

  Future<void> deleteTrip(String id) async {
    final token = await _getToken(requiredForRequest: true);
    final response = await _client.delete(
      Uri.parse('$baseUrl/trips/$id'),
      headers: _buildHeaders(token: token),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwForResponse(response);
    }
  }
}
