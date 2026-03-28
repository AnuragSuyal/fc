import 'notification_sound_service_stub.dart'
    if (dart.library.html) 'notification_sound_service_web.dart'
    if (dart.library.io) 'notification_sound_service_io.dart' as impl;

class NotificationSoundService {
  static final Map<String, DateTime> _lastPlayedAt = <String, DateTime>{};

  static Future<void> playFriendRequest() => _play(
        'friend_request',
        cooldown: const Duration(milliseconds: 1200),
      );

  static Future<void> playFriendOnline() => _play(
        'friend_online',
        cooldown: const Duration(milliseconds: 1500),
      );

  static Future<void> playFriendUpdate() => _play(
        'friend_update',
        cooldown: const Duration(milliseconds: 900),
      );

  static Future<void> playMessage() => _play(
        'message',
        cooldown: const Duration(milliseconds: 700),
      );

  static Future<void> _play(
    String soundId, {
    required Duration cooldown,
  }) async {
    final now = DateTime.now();
    final lastPlayed = _lastPlayedAt[soundId];
    if (lastPlayed != null && now.difference(lastPlayed) < cooldown) {
      return;
    }

    _lastPlayedAt[soundId] = now;
    await impl.playSound(soundId);
  }
}
