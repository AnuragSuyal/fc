import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'api_service.dart';

class LocationService {
  // Check if location permission is granted
  static Future<bool> hasPermission() async {
    final status = await Permission.location.status;
    return status.isGranted;
  }

  // Request location permission
  static Future<bool> requestPermission() async {
    final status = await Permission.location.request();
    return status.isGranted;
  }

  // Get current location
  static Future<Position?> getCurrentLocation() async {
    try {
      bool permission = await hasPermission();
      if (!permission) {
        permission = await requestPermission();
        if (!permission) return null;
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
    } catch (e) {
      debugPrint('Error getting location: $e');
      return null;
    }
  }

  // Update location on server
  static Future<bool> updateLocation({
    required double latitude,
    required double longitude,
    bool sharing = true,
    int radius = 10,
  }) async {
    try {
      await ApiService.post('/location/update', {
        'latitude': latitude,
        'longitude': longitude,
        'sharing': sharing,
        'radius': radius,
      });
      return true;
    } catch (e) {
      debugPrint('Error updating location: $e');
      return false;
    }
  }

  // Get location status
  static Future<Map<String, dynamic>?> getLocationStatus() async {
    try {
      final response = await ApiService.get('/location/status');
      return response;
    } catch (e) {
      debugPrint('Error getting location status: $e');
      return null;
    }
  }

  // Get nearby users
  static Future<List<dynamic>> getNearbyUsers({int maxDistance = 10}) async {
    try {
      final response =
          await ApiService.get('/location/nearby?maxDistance=$maxDistance');
      return response['users'] ?? [];
    } catch (e) {
      debugPrint('Error getting nearby users: $e');
      return [];
    }
  }

  // Disable location sharing
  static Future<bool> disableLocationSharing() async {
    try {
      await ApiService.post('/location/disable', {});
      return true;
    } catch (e) {
      debugPrint('Error disabling location: $e');
      return false;
    }
  }
}






