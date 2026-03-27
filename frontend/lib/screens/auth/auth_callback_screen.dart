import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';

class AuthCallbackScreen extends StatefulWidget {
  const AuthCallbackScreen({super.key});

  @override
  State<AuthCallbackScreen> createState() => _AuthCallbackScreenState();
}

class _AuthCallbackScreenState extends State<AuthCallbackScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleCallback();
    });
  }

  Future<void> _handleCallback() async {
    try {
      final uri = Uri.base;
      final token = uri.queryParameters['token'];
      final error = uri.queryParameters['error'];

      if (error != null && error.isNotEmpty) {
        throw Exception(error);
      }

      if (token == null || token.isEmpty) {
        throw Exception('Authentication token missing');
      }

      await context.read<AuthProvider>().handleSocialToken(token);
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/home');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Login failed: ${error.toString().replaceFirst('Exception: ', '')}',
          ),
          backgroundColor: Colors.red,
        ),
      );
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('Completing login...'),
          ],
        ),
      ),
    );
  }
}
