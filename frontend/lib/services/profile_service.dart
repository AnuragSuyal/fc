import 'api_service.dart';

class ProfileService {
  // Get current user profile
  static Future<Map<String, dynamic>> getMyProfile() async {
    try {
      final response = await ApiService.get('/profile/me');
      return response;
    } catch (e) {
      return {};
    }
  }

  // Get user profile by ID
  static Future<Map<String, dynamic>> getProfile(String userId) async {
    try {
      final encodedUserId = Uri.encodeComponent(userId);
      final response = await ApiService.get('/profile/$encodedUserId');
      return response;
    } catch (e) {
      return {};
    }
  }

  // Get user badges
  static Future<List<dynamic>> getBadges(String userId) async {
    try {
      final encodedUserId = Uri.encodeComponent(userId);
      final response = await ApiService.get('/profile/$encodedUserId/badges');
      return response is List ? response : [];
    } catch (e) {
      return [];
    }
  }

  // Get game stats
  static Future<Map<String, dynamic>> getGameStats(String userId) async {
    try {
      final encodedUserId = Uri.encodeComponent(userId);
      final response =
          await ApiService.get('/profile/$encodedUserId/game-stats');
      return response;
    } catch (e) {
      return {};
    }
  }

  // Get profile visitors
  static Future<Map<String, dynamic>> getVisitors(
    String userId, {
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final encodedUserId = Uri.encodeComponent(userId);
      final response = await ApiService.get(
        '/profile/$encodedUserId/visitors?page=$page&limit=$limit',
      );
      return response;
    } catch (e) {
      return {'visitors': [], 'total': 0};
    }
  }

  // Add profile visit
  static Future<bool> addVisit(String userId, {String? message}) async {
    try {
      final encodedUserId = Uri.encodeComponent(userId);
      await ApiService.post('/profile/$encodedUserId/visit', {
        if (message != null) 'message': message,
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  // Update game stats (when game is played)
  static Future<bool> updateGameStats(String game, bool won) async {
    try {
      await ApiService.post('/profile/game-stats/update', {
        'game': game,
        'won': won,
      });
      return true;
    } catch (e) {
      return false;
    }
  }
}
