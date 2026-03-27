import 'package:flutter/foundation.dart';
import 'api_service.dart';

class SettingsService {
  // Get all settings
  static Future<Map<String, dynamic>> getSettings() async {
    try {
      final response = await ApiService.get('/settings');
      return response;
    } catch (e) {
      debugPrint('Error getting settings: $e');
      return {};
    }
  }

  // Update notifications
  static Future<bool> updateNotifications(Map<String, dynamic> settings) async {
    try {
      await ApiService.put('/settings/notifications', settings);
      return true;
    } catch (e) {
      debugPrint('Error updating notifications: $e');
      return false;
    }
  }

  // Update privacy
  static Future<bool> updatePrivacy(Map<String, dynamic> settings) async {
    try {
      await ApiService.put('/settings/privacy', settings);
      return true;
    } catch (e) {
      debugPrint('Error updating privacy: $e');
      return false;
    }
  }

  // Update quiet hours
  static Future<bool> updateQuietHours(Map<String, dynamic> settings) async {
    try {
      await ApiService.put('/settings/quiet-hours', settings);
      return true;
    } catch (e) {
      debugPrint('Error updating quiet hours: $e');
      return false;
    }
  }

  // Update language & currency
  static Future<bool> updateLanguage(Map<String, dynamic> settings) async {
    try {
      await ApiService.put('/settings/language', settings);
      return true;
    } catch (e) {
      debugPrint('Error updating language: $e');
      return false;
    }
  }

  // Update profile
  static Future<Map<String, dynamic>?> saveProfile(
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await ApiService.put('/settings/profile', data);
      return response is Map<String, dynamic>
          ? response
          : Map<String, dynamic>.from(response as Map);
    } catch (e) {
      debugPrint('Error updating profile: $e');
      return null;
    }
  }

  static Future<bool> updateProfile(Map<String, dynamic> data) async {
    final response = await saveProfile(data);
    return response != null;
  }

  // Change password
  static Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final response = await ApiService.post('/settings/change-password', {
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      });
      return {'success': true, 'data': response};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // Delete account
  static Future<bool> deleteAccount() async {
    try {
      await ApiService.delete('/settings/account');
      return true;
    } catch (e) {
      debugPrint('Error deleting account: $e');
      return false;
    }
  }
}





