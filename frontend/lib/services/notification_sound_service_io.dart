import 'package:flutter/services.dart';

Future<void> playSound(String soundId) async {
  try {
    await SystemSound.play(SystemSoundType.alert);
  } catch (_) {}
}
