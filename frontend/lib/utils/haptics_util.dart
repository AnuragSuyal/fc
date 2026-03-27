import 'package:haptic_feedback/haptic_feedback.dart';

class HapticsUtil {
  /// Rising intensity vibration for successful gift receipt
  static Future<void> giftReceived() async {
    try {
      final canVibrate = await Haptics.canVibrate();
      if (!canVibrate) return;

      await Haptics.vibrate(HapticsType.light);
      await Future.delayed(const Duration(milliseconds: 150));
      await Haptics.vibrate(HapticsType.medium);
      await Future.delayed(const Duration(milliseconds: 150));
      await Haptics.vibrate(HapticsType.heavy);
    } catch (e) {
      // Ignore haptic errors
    }
  }

  /// Heavy 3-pulse impact for critical errors
  static Future<void> error() async {
    try {
      final canVibrate = await Haptics.canVibrate();
      if (!canVibrate) return;

      for (int i = 0; i < 3; i++) {
        await Haptics.vibrate(HapticsType.heavy);
        if (i < 2) await Future.delayed(const Duration(milliseconds: 200));
      }
    } catch (e) {
      // Ignore haptic errors
    }
  }

  /// Light tap for button clicks
  static Future<void> lightImpact() async {
    try {
      final canVibrate = await Haptics.canVibrate();
      if (!canVibrate) return;
      await Haptics.vibrate(HapticsType.light);
    } catch (e) {
      // Ignore haptic errors on unsupported devices.
    }
  }

  /// Selection click feedback
  static Future<void> selectionClick() async {
    try {
      final canVibrate = await Haptics.canVibrate();
      if (!canVibrate) return;
      await Haptics.vibrate(HapticsType.selection);
    } catch (e) {
      // Ignore haptic errors on unsupported devices.
    }
  }
}






