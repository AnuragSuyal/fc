import 'dart:math';

import 'api_service.dart';
import '../models/mini_draw_model.dart';

class MiniDrawUnlockResult {
  const MiniDrawUnlockResult({
    required this.summary,
    required this.duplicate,
    required this.chargedCoins,
    this.transactionId,
    this.newBalance,
  });

  final MiniDrawSessionSummary summary;
  final bool duplicate;
  final int chargedCoins;
  final String? transactionId;
  final Map<String, dynamic>? newBalance;
}

class MiniDrawService {
  MiniDrawService._();

  static final Random _random = Random();

  static Future<MiniDrawSnapshot> getSnapshot(String roomId) async {
    final response = await ApiService.get('/rooms/$roomId/draw', dedupe: false);
    return MiniDrawSnapshot.fromJson(_asMap(response));
  }

  static Future<MiniDrawUnlockResult> unlock(String roomId) async {
    final response = await ApiService.post(
      '/rooms/$roomId/draw/unlock',
      const <String, dynamic>{},
      headers: _idempotencyHeaders('mini-draw-unlock-$roomId'),
    );
    final json = _asMap(response);
    return MiniDrawUnlockResult(
      summary: MiniDrawSessionSummary.fromJson(
        json['summary'] is Map<String, dynamic>
            ? json['summary'] as Map<String, dynamic>
            : json['summary'] is Map
                ? Map<String, dynamic>.from(json['summary'] as Map)
                : null,
      ),
      duplicate: json['duplicate'] == true,
      chargedCoins: _asInt(json['chargedCoins'], fallback: 0),
      transactionId: json['transactionId']?.toString(),
      newBalance: json['newBalance'] is Map<String, dynamic>
          ? json['newBalance'] as Map<String, dynamic>
          : json['newBalance'] is Map
              ? Map<String, dynamic>.from(json['newBalance'] as Map)
              : null,
    );
  }

  static Future<MiniDrawSessionSummary> updateSettings(
    String roomId, {
    bool? enabled,
    MiniDrawAccessPolicy? accessPolicy,
  }) async {
    final response = await ApiService.put('/rooms/$roomId/draw/settings', {
      if (enabled != null) 'enabled': enabled,
      if (accessPolicy != null)
        'accessPolicy': miniDrawAccessPolicyToJson(accessPolicy),
    });
    final json = _asMap(response);
    return MiniDrawSessionSummary.fromJson(
      json['summary'] is Map<String, dynamic>
          ? json['summary'] as Map<String, dynamic>
          : json['summary'] is Map
              ? Map<String, dynamic>.from(json['summary'] as Map)
              : null,
    );
  }

  static Future<MiniDrawSessionSummary> clear(String roomId) async {
    final response =
        await ApiService.post('/rooms/$roomId/draw/clear', const {});
    return _summaryFromResponse(response);
  }

  static Future<MiniDrawSessionSummary> undo(String roomId) async {
    final response =
        await ApiService.post('/rooms/$roomId/draw/undo', const {});
    return _summaryFromResponse(response);
  }

  static Future<MiniDrawSessionSummary> redo(String roomId) async {
    final response =
        await ApiService.post('/rooms/$roomId/draw/redo', const {});
    return _summaryFromResponse(response);
  }

  static MiniDrawSessionSummary _summaryFromResponse(dynamic response) {
    final json = _asMap(response);
    return MiniDrawSessionSummary.fromJson(
      json['summary'] is Map<String, dynamic>
          ? json['summary'] as Map<String, dynamic>
          : json['summary'] is Map
              ? Map<String, dynamic>.from(json['summary'] as Map)
              : null,
    );
  }

  static Map<String, String> _idempotencyHeaders(String prefix) => {
        'Idempotency-Key': createIdempotencyKey(prefix),
      };

  static String createIdempotencyKey(String prefix, {DateTime? timestamp}) {
    final clock = timestamp ?? DateTime.now();
    final entropy = List<String>.generate(
      4,
      (_) => _random.nextInt(1 << 16).toRadixString(16).padLeft(4, '0'),
      growable: false,
    ).join();
    return '$prefix-${clock.microsecondsSinceEpoch}-$entropy';
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }

  static int _asInt(dynamic value, {int fallback = 0}) {
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? fallback;
  }
}
