import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../utils/constants.dart';
import 'auth_service.dart';

class ApiService {
  static const Duration _timeout = Duration(seconds: 20);
  static final http.Client _client = http.Client();
  static final Map<String, Future<dynamic>> _pendingGets = {};

  static String get baseUrl => AppConfig.baseUrl;

  static Future<dynamic> get(String endpoint) async {
    final token = await AuthService.getToken();
    final requestKey = '$endpoint::${token ?? ''}';
    final existing = _pendingGets[requestKey];
    if (existing != null) {
      return existing;
    }

    final future = _performRequest(
      method: 'GET',
      endpoint: endpoint,
      retries: 1,
      send: () async {
        final currentToken = await AuthService.getToken();
        return _client
            .get(
              Uri.parse('$baseUrl$endpoint'),
              headers: _headers(currentToken),
            )
            .timeout(_timeout);
      },
    );
    _pendingGets[requestKey] = future;

    try {
      return await future;
    } finally {
      if (identical(_pendingGets[requestKey], future)) {
        _pendingGets.remove(requestKey);
      }
    }
  }

  static Future<dynamic> post(
      String endpoint, Map<String, dynamic> data) async {
    return _performRequest(
      method: 'POST',
      endpoint: endpoint,
      retries: 1,
      send: () async {
        final token = await AuthService.getToken();
        return _client
            .post(
              Uri.parse('$baseUrl$endpoint'),
              headers: _headers(token),
              body: json.encode(data),
            )
            .timeout(_timeout);
      },
    );
  }

  static Future<dynamic> put(String endpoint, Map<String, dynamic> data) async {
    return _performRequest(
      method: 'PUT',
      endpoint: endpoint,
      retries: 1,
      send: () async {
        final token = await AuthService.getToken();
        return _client
            .put(
              Uri.parse('$baseUrl$endpoint'),
              headers: _headers(token),
              body: json.encode(data),
            )
            .timeout(_timeout);
      },
    );
  }

  static Future<dynamic> patch(
      String endpoint, Map<String, dynamic> data) async {
    return _performRequest(
      method: 'PATCH',
      endpoint: endpoint,
      retries: 1,
      send: () async {
        final token = await AuthService.getToken();
        return _client
            .patch(
              Uri.parse('$baseUrl$endpoint'),
              headers: _headers(token),
              body: json.encode(data),
            )
            .timeout(_timeout);
      },
    );
  }

  static Future<dynamic> delete(String endpoint) async {
    return _performRequest(
      method: 'DELETE',
      endpoint: endpoint,
      retries: 1,
      send: () async {
        final token = await AuthService.getToken();
        return _client
            .delete(
              Uri.parse('$baseUrl$endpoint'),
              headers: _headers(token),
            )
            .timeout(_timeout);
      },
    );
  }

  static Map<String, String> _headers(String? token) => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  static Future<dynamic> _performRequest({
    required String method,
    required String endpoint,
    required Future<http.Response> Function() send,
    int retries = 0,
  }) async {
    var attempt = 0;
    var attemptedRefresh = false;

    while (true) {
      try {
        final response = await send();
        if (response.statusCode == 401 &&
            !attemptedRefresh &&
            _shouldAttemptRefresh(endpoint)) {
          attemptedRefresh = true;
          final refreshed = await AuthService.refreshSession();
          if (refreshed) {
            continue;
          }
          await AuthService.clearSession();
        }
        return _handleResponse(response);
      } on TimeoutException catch (e) {
        if (attempt >= retries) {
          debugPrint('$method $endpoint Error: $e');
          _rethrow(e);
        }
      } on SocketException catch (e) {
        if (attempt >= retries) {
          debugPrint('$method $endpoint Error: $e');
          _rethrow(e);
        }
      } catch (e) {
        debugPrint('$method $endpoint Error: $e');
        _rethrow(e);
      }

      attempt += 1;
      await Future<void>.delayed(Duration(milliseconds: 250 * attempt));
    }
  }

  static bool _shouldAttemptRefresh(String endpoint) {
    const excludedEndpoints = {
      '/auth/login',
      '/auth/register',
      '/auth/guest',
      '/auth/refresh',
      '/auth/otp/send',
      '/auth/otp/verify',
      '/auth/social/token',
    };
    return !excludedEndpoints.contains(endpoint);
  }

  static dynamic _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      try {
        return _decodePayload(response.body);
      } catch (_) {
        return response.body;
      }
    }
    try {
      final body = json.decode(response.body);
      String msg = 'Server error: ${response.statusCode}';
      if (body is Map) {
        if (body['details'] is List && (body['details'] as List).isNotEmpty) {
          final firstDetail = (body['details'] as List).first;
          if (firstDetail is Map && firstDetail['message'] is String) {
            msg = firstDetail['message'];
          }
        }
        if (body['error'] is Map) {
          msg = body['error']['message'] ?? msg;
        } else if (body['error'] is String) {
          msg = body['error'];
        } else if (body['message'] is String) {
          msg = body['message'];
        }
      }
      throw Exception(msg);
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Server error: ${response.statusCode}');
    }
  }

  static Never _rethrow(Object e) {
    if (e is Exception) throw e;
    throw Exception('Network error: $e');
  }

  static dynamic _decodePayload(String body) {
    if (body.length < 12000) {
      return json.decode(body);
    }

    return compute(_decodeJsonBody, body);
  }
}

dynamic _decodeJsonBody(String body) => json.decode(body);
