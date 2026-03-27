import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Central place for all env-specific URLs.
/// Override at build time with: --dart-define=API_URL=https://api.yourserver.com
class AppConfig {
  static const String _apiUrl =
      String.fromEnvironment('API_URL', defaultValue: '');

  static String get baseUrl {
    if (_apiUrl.isNotEmpty) return normalizeBackendUrl(_apiUrl);
    if (kIsWeb) return 'http://localhost:5000/api';
    return 'http://10.0.2.2:5000/api'; // Android emulator
  }

  static String get socketUrl {
    if (_apiUrl.isNotEmpty) {
      return normalizeBackendUrl(_apiUrl.replaceAll('/api', ''));
    }
    if (kIsWeb) return 'http://localhost:5000';
    return 'http://10.0.2.2:5000';
  }

  static String normalizeBackendUrl(String url) {
    if (url.isEmpty || kIsWeb) return url;

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority) return url;

    final isLocalHost = uri.host == 'localhost' ||
        uri.host == '127.0.0.1' ||
        uri.host == '0.0.0.0';
    if (!isLocalHost) return url;

    if (defaultTargetPlatform == TargetPlatform.android) {
      return uri.replace(host: '10.0.2.2').toString();
    }

    return url;
  }
}

class AppColors {
  static const primaryBlue = Color(0xFF131416);
  static const secondaryBlue = Color(0xFF5B6168);
  static const successGreen = Color(0xFF26BE87);
  static const errorRed = Color(0xFFE85168);
  static const warningOrange = Color(0xFFFFB64D);
  static const backgroundWhite = Color(0xFFF4F5F6);
  static const surfaceGrey = Color(0xFFE6E8EB);
  static const surfaceBubble = Color(0xFFF8F8F9);
  static const accentYellow = Color(0xFFD8DADF);
  static const accentSky = Color(0xFF8E959D);
  static const accentBerry = Color(0xFF23272D);
  static const textPrimary = Color(0xFF131416);
  static const textSecondary = Color(0xFF6A7178);
  static const textTertiary = Color(0xFFB0B5BC);
}

class AppStrings {
  static const appName = 'Friend Circle';
  static const welcome = 'Welcome Back!';
  static const signIn = 'Sign in to continue';
  static const createAccount = 'Create Account';
  static const joinToday = 'Join Friend Circle today';
  static const email = 'Email';
  static const password = 'Password';
  static const username = 'Username';
  static const confirmPassword = 'Confirm Password';
  static const login = 'Sign In';
  static const register = 'Sign Up';
  static const guestLogin = 'Continue as Guest';
  static const forgotPassword = 'Forgot Password?';
  static const alreadyHaveAccount = 'Already have an account? ';
  static const dontHaveAccount = "Don't have an account? ";
}
