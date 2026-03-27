import 'package:flutter/material.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/constants.dart';
import '../../widgets/mascot_header.dart';
import 'otp_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;
  bool _showPhoneInput = false;
  final TextEditingController _phoneController = TextEditingController();

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _handleGuestLogin() async {
    setState(() => _isLoading = true);

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.guestLogin();

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (success) {
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  Future<void> _handleSocialLogin(String provider) async {
    setState(() => _isLoading = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final baseUrl = '${AppConfig.baseUrl}/auth';
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final url = '$baseUrl/$provider?t=$timestamp';

      final result = await FlutterWebAuth2.authenticate(
        url: url,
        callbackUrlScheme: 'friendcircle',
      );

      final token = Uri.parse(result).queryParameters['token'];
      if (token != null && token.isNotEmpty) {
        await authProvider.handleSocialToken(token);

        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        throw 'Authentication failed or cancelled';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to login with $provider: $e'),
            backgroundColor: AppColors.errorRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handlePhoneLogin() async {
    if (!_showPhoneInput) {
      setState(() => _showPhoneInput = true);
      return;
    }

    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter phone number'),
          backgroundColor: AppColors.errorRed,
        ),
      );
      return;
    }

    final fullPhone = phone.startsWith('+') ? phone : '+91$phone';

    setState(() => _isLoading = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final otp = await authProvider.sendOTP(fullPhone);

      if (!mounted) return;

      if (otp != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Test OTP: $otp'),
            backgroundColor: AppColors.accentSky,
            duration: const Duration(seconds: 8),
          ),
        );
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OTPScreen(phone: fullPhone),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send OTP: $e'),
            backgroundColor: AppColors.errorRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mood = context.mood;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Container(
        decoration: BoxDecoration(gradient: mood.shellGradient),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const MascotHeader(),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: 0.92),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(38),
                    ),
                    border: Border.all(color: mood.outlineSoft),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 26, 24, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: mood.surfaceSoft,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'Fresh, original social-party look',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Welcome back',
                          style: theme.textTheme.displaySmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Jump into rooms, games, and casual hangouts with the new Friend Circle vibe.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (_showPhoneInput) ...[
                          TextField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              hintText: 'Phone number',
                              prefixIcon: Icon(Icons.phone_iphone_rounded),
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                        _AuthActionButton(
                          text: 'Continue with Google',
                          color: AppColors.accentSky,
                          icon: Icons.public_rounded,
                          onTap: _isLoading
                              ? null
                              : () => _handleSocialLogin('google'),
                        ),
                        const SizedBox(height: 14),
                        _AuthActionButton(
                          text: 'Continue with Facebook',
                          color: AppColors.accentBerry,
                          icon: Icons.thumb_up_alt_rounded,
                          onTap: _isLoading
                              ? null
                              : () => _handleSocialLogin('facebook'),
                        ),
                        const SizedBox(height: 14),
                        _AuthActionButton(
                          text: _showPhoneInput
                              ? 'Send OTP'
                              : 'Continue with mobile',
                          color: AppColors.primaryBlue,
                          icon: Icons.sms_rounded,
                          onTap: _isLoading ? null : _handlePhoneLogin,
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.center,
                          child: TextButton(
                            onPressed: _isLoading ? null : _handleGuestLogin,
                            child: const Text('Continue as guest'),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Need an account? ',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            GestureDetector(
                              onTap: () =>
                                  Navigator.pushNamed(context, '/register'),
                              child: Text(
                                'Sign up',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: AppColors.primaryBlue,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_isLoading) ...[
                          const SizedBox(height: 24),
                          const Center(child: CircularProgressIndicator()),
                        ],
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: mood.surfaceSoft,
                            borderRadius: BorderRadius.circular(26),
                          ),
                          child: Text(
                            'By logging in, you agree to our Terms of Service and Privacy Policy.',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthActionButton extends StatelessWidget {
  const _AuthActionButton({
    required this.text,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  final String text;
  final Color color;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(26),
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: color.withValues(alpha: 0.24)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.12),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_forward_rounded,
                color: color,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
