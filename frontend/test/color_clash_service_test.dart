import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/color_clash_service.dart';

void main() {
  test('ColorClashService.createIdempotencyKey builds a safe key', () {
    final key = ColorClashService.createIdempotencyKey(
      'queue-join',
      random: Random(7),
      timestamp: DateTime.fromMicrosecondsSinceEpoch(123456789),
    );

    expect(key, startsWith('queue-join-123456789-'));
    expect(key.split('-').last.length, 16);
  });

  test('ColorClashService.createIdempotencyKey stays stable with seeded random',
      () {
    final keyA = ColorClashService.createIdempotencyKey(
      'room-create',
      random: Random(11),
      timestamp: DateTime.fromMicrosecondsSinceEpoch(333),
    );
    final keyB = ColorClashService.createIdempotencyKey(
      'room-create',
      random: Random(11),
      timestamp: DateTime.fromMicrosecondsSinceEpoch(333),
    );

    expect(keyA, keyB);
  });
}
