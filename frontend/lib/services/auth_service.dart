import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'api_service.dart';

class AuthService {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'auth_token';
  static const _refreshTokenKey = 'auth_refresh_token';

  static final http.Client _client = http.Client();

  static String? _cachedToken;
  static String? _cachedRefreshToken;
  static Future<String?>? _pendingTokenRead;
  static Future<String?>? _pendingRefreshTokenRead;
  static Future<bool>? _pendingRefresh;

  static Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
  }) async {
    final response = await ApiService.post('/auth/register', {
      'username': username,
      'email': email,
      'password': password,
    });
    await _persistSessionFromResponse(response, clearRefreshIfMissing: true);
    return _asMap(response);
  }

  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await ApiService.post('/auth/login', {
      'email': email,
      'password': password,
    });
    await _persistSessionFromResponse(response, clearRefreshIfMissing: true);
    return _asMap(response);
  }

  static Future<Map<String, dynamic>> guestLogin() async {
    final response = await ApiService.post('/auth/guest', {});
    await _persistSessionFromResponse(response, clearRefreshIfMissing: true);
    return _asMap(response);
  }

  static Future<Map<String, dynamic>> handleSocialToken(String token) async {
    final response = await ApiService.post('/auth/social/token', {
      'token': token,
    });
    await _persistSessionFromResponse(response, clearRefreshIfMissing: true);
    return _asMap(response);
  }

  static Future<Map<String, dynamic>> getCurrentUser() async {
    return _asMap(await ApiService.get('/auth/me'));
  }

  static Future<void> logout({bool revokeSession = true}) async {
    try {
      if (revokeSession && await getToken() != null) {
        await ApiService.post('/auth/logout', {});
      }
    } catch (_) {
      // Ignore logout failures. Local session still needs to be cleared.
    } finally {
      await clearSession();
    }
  }

  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  static Future<Map<String, dynamic>> sendOTP(String phone) async {
    return _asMap(await ApiService.post('/auth/otp/send', {'phone': phone}));
  }

  static Future<bool> verifyOTP({
    required String phone,
    required String otp,
  }) async {
    final response = await ApiService.post('/auth/otp/verify', {
      'phone': phone,
      'otp': otp,
    });

    await _persistSessionFromResponse(response, clearRefreshIfMissing: true);
    return _accessTokenFromResponse(response) != null;
  }

  static Future<void> saveToken(String token) {
    return saveSession(
      accessToken: token,
      clearRefreshIfMissing: true,
    );
  }

  static Future<void> saveSession({
    required String accessToken,
    String? refreshToken,
    bool clearRefreshIfMissing = false,
  }) async {
    _cachedToken = accessToken;
    _pendingTokenRead = null;
    await _storage.write(key: _tokenKey, value: accessToken);

    if (refreshToken != null && refreshToken.isNotEmpty) {
      _cachedRefreshToken = refreshToken;
      _pendingRefreshTokenRead = null;
      await _storage.write(key: _refreshTokenKey, value: refreshToken);
    } else if (clearRefreshIfMissing) {
      _cachedRefreshToken = null;
      _pendingRefreshTokenRead = null;
      await _storage.delete(key: _refreshTokenKey);
    }
  }

  static Future<void> clearSession() async {
    _cachedToken = null;
    _cachedRefreshToken = null;
    _pendingTokenRead = null;
    _pendingRefreshTokenRead = null;
    _pendingRefresh = null;

    await Future.wait([
      _storage.delete(key: _tokenKey),
      _storage.delete(key: _refreshTokenKey),
    ]);
  }

  static Future<bool> refreshSession({bool rotate = false}) async {
    final pending = _pendingRefresh;
    if (pending != null) {
      return pending;
    }

    final future = _refreshSessionInternal(rotate: rotate);
    _pendingRefresh = future;
    try {
      return await future;
    } finally {
      if (identical(_pendingRefresh, future)) {
        _pendingRefresh = null;
      }
    }
  }

  static Future<String?> getToken() async {
    if (_cachedToken != null) {
      return _cachedToken;
    }

    final pending = _pendingTokenRead;
    if (pending != null) {
      return pending;
    }

    final future = _storage.read(key: _tokenKey).then((token) {
      _cachedToken = token;
      return token;
    });
    _pendingTokenRead = future;

    try {
      return await future;
    } finally {
      if (identical(_pendingTokenRead, future)) {
        _pendingTokenRead = null;
      }
    }
  }

  static Future<String?> getRefreshToken() async {
    if (_cachedRefreshToken != null) {
      return _cachedRefreshToken;
    }

    final pending = _pendingRefreshTokenRead;
    if (pending != null) {
      return pending;
    }

    final future = _storage.read(key: _refreshTokenKey).then((token) {
      _cachedRefreshToken = token;
      return token;
    });
    _pendingRefreshTokenRead = future;

    try {
      return await future;
    } finally {
      if (identical(_pendingRefreshTokenRead, future)) {
        _pendingRefreshTokenRead = null;
      }
    }
  }

  static Future<void> _persistSessionFromResponse(
    dynamic response, {
    bool clearRefreshIfMissing = false,
  }) async {
    final accessToken = _accessTokenFromResponse(response);
    if (accessToken == null || accessToken.isEmpty) {
      return;
    }

    final refreshToken = _refreshTokenFromResponse(response);
    await saveSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      clearRefreshIfMissing: clearRefreshIfMissing,
    );
  }

  static String? _accessTokenFromResponse(dynamic response) {
    if (response is! Map) return null;
    final token = response['accessToken'] ?? response['token'];
    if (token is String && token.isNotEmpty) {
      return token;
    }
    return null;
  }

  static String? _refreshTokenFromResponse(dynamic response) {
    if (response is! Map) return null;
    final token = response['refreshToken'];
    if (token is String && token.isNotEmpty) {
      return token;
    }
    return null;
  }

  static Map<String, dynamic> _asMap(dynamic response) {
    if (response is Map<String, dynamic>) return response;
    if (response is Map) {
      return Map<String, dynamic>.from(response);
    }
    return <String, dynamic>{};
  }

  static Future<bool> _refreshSessionInternal({bool rotate = false}) async {
    final refreshToken = await getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      await clearSession();
      return false;
    }

    try {
      final response = await _client
          .post(
            Uri.parse('${ApiService.baseUrl}/auth/refresh'),
            headers: const {'Content-Type': 'application/json'},
            body: json.encode({
              'refreshToken': refreshToken,
              'rotate': rotate,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        await clearSession();
        return false;
      }

      final payload = response.body.isEmpty
          ? const <String, dynamic>{}
          : json.decode(response.body) as Map<String, dynamic>;

      final nextAccessToken = payload['accessToken'] ?? payload['token'];
      if (nextAccessToken is! String || nextAccessToken.isEmpty) {
        await clearSession();
        return false;
      }

      await saveSession(
        accessToken: nextAccessToken,
        refreshToken: payload['refreshToken'] as String?,
      );
      return true;
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
