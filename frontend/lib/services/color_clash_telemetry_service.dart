import 'dart:convert';

import 'package:flutter/foundation.dart';

class ColorClashTelemetryService {
  const ColorClashTelemetryService();

  void track(
    String event, {
    Map<String, Object?> payload = const <String, Object?>{},
  }) {
    debugPrint(
      '[ColorClash][$event] ${jsonEncode(_sanitize(payload))}',
    );
  }

  Map<String, Object?> _sanitize(Map<String, Object?> payload) {
    final normalized = <String, Object?>{};
    for (final entry in payload.entries) {
      normalized[entry.key] = _sanitizeValue(entry.value);
    }
    return normalized;
  }

  Object? _sanitizeValue(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toIso8601String();
    if (value is num || value is bool || value is String) return value;
    if (value is Iterable) {
      return value.map(_sanitizeValue).toList(growable: false);
    }
    if (value is Map) {
      return value.map(
        (key, entry) => MapEntry('$key', _sanitizeValue(entry)),
      );
    }
    return '$value';
  }
}
