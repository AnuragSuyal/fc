import 'package:flutter/material.dart';
import 'package:pinput/pinput.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/constants.dart';

class OTPScreen extends StatefulWidget {
  final String phone;

  const OTPScreen({super.key, required this.phone});

  @override
  State<OTPScreen> createState() => _OTPScreenState();
}

class _OTPScreenState extends State<OTPScreen> {
  String? _otp;
  bool _isLoading = false;
  int _secondsRemaining = 60;
  bool _canResend = false;
  String? _error;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (!_isDisposed && mounted) {
      setState(fn);
    }
  }

  void _startTimer() {
    Future.delayed(const Duration(seconds: 1), () {
      if (_isDisposed) return;

      _safeSetState(() {
        if (_secondsRemaining > 0) {
          _secondsRemaining--;
          _canResend = false;
          _startTimer();
        } else {
          _canResend = true;
        }
      });
    });
  }

  Future<void> _verifyOTP() async {
    if (_otp == null || _otp!.length < 6) {
      _safeSetState(() => _error = 'Please enter a 6-digit OTP');
      return;
    }

    _safeSetState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final success = await AuthService.verifyOTP(
        phone: widget.phone,
        otp: _otp!,
      );

      if (!mounted) return;

      if (success) {
        await Provider.of<AuthProvider>(context, listen: false)
            .refreshBalance();
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
        }
      } else {
        _safeSetState(() {
          _error = 'Invalid OTP. Please try again.';
          _isLoading = false;
        });
      }
    } catch (e) {
      _safeSetState(() {
        _error = 'Verification failed: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _resendOTP() async {
    if (!_canResend) return;

    _safeSetState(() {
      _isLoading = true;
      _error = null;
      _secondsRemaining = 60;
      _canResend = false;
    });

    try {
      final response = await AuthService.sendOTP(widget.phone);

      if (!mounted) return;

      _startTimer();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(response['message'] ?? 'OTP resent successfully'),
          backgroundColor: AppColors.successGreen,
        ),
      );
    } catch (e) {
      _safeSetState(() {
        _error = 'Failed to resend: $e';
      });
    } finally {
      _safeSetState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mood = context.mood;

    final defaultPinTheme = PinTheme(
      width: 52,
      height: 60,
      textStyle: theme.textTheme.titleLarge?.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w800,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: mood.outlineSoft),
      ),
    );

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Container(
        decoration: BoxDecoration(gradient: mood.shellGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(36),
                      border: Border.all(color: mood.outlineSoft),
                    ),
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
                            'Secure sign in',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Verify your number',
                          style: theme.textTheme.displaySmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'We sent a 6-digit code to ${widget.phone}.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const Spacer(),
                        Center(
                          child: Pinput(
                            length: 6,
                            defaultPinTheme: defaultPinTheme,
                            focusedPinTheme: defaultPinTheme.copyDecorationWith(
                              border: Border.all(
                                color: AppColors.primaryBlue,
                                width: 1.6,
                              ),
                              borderRadius: BorderRadius.circular(22),
                            ),
                            onCompleted: (pin) {
                              _safeSetState(() => _otp = pin);
                              _verifyOTP();
                            },
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (_error != null)
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.errorRed.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.error_outline_rounded,
                                  color: AppColors.errorRed,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _error!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: AppColors.errorRed,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 18),
                        Align(
                          alignment: Alignment.center,
                          child: _canResend
                              ? TextButton(
                                  onPressed: _resendOTP,
                                  child: const Text('Resend code'),
                                )
                              : Text(
                                  'Resend available in $_secondsRemaining s',
                                  style: theme.textTheme.bodySmall,
                                ),
                        ),
                        const Spacer(),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _isLoading ? null : _verifyOTP,
                            child: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Verify and continue'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
