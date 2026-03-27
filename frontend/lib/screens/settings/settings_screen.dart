import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/settings_service.dart';
import '../../providers/auth_provider.dart';
import '../../utils/constants.dart';
import 'account_settings_screen.dart';
import 'notification_settings_screen.dart';
import 'privacy_settings_screen.dart';
import 'quiet_hours_screen.dart';
import 'language_settings_screen.dart';
import 'support_screen.dart';
import 'change_password_screen.dart';
import '../../widgets/rounded_scaffold.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<String, dynamic> _settings = {};
  bool _isLoading = true;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _safeSetState(VoidCallback fn) {
    if (!_isDisposed && mounted) {
      setState(fn);
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  Future<void> _loadSettings() async {
    _safeSetState(() => _isLoading = true);

    final settings = await SettingsService.getSettings();

    if (!mounted) return;

    _safeSetState(() {
      _settings = settings;
      _isLoading = false;
    });
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (!mounted) return;
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      await authProvider.logout();
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return RoundedScaffold(
      title: 'Settings',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Account Section
                _buildSection(
                  title: 'Account',
                  children: [
                    _buildSettingsTile(
                      icon: Icons.person,
                      label: 'Profile Information',
                      subtitle: 'Edit your username, bio, and avatar',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AccountSettingsScreen(
                              settings: _settings,
                              onUpdate: _loadSettings,
                            ),
                          ),
                        );
                      },
                    ),
                    _buildSettingsTile(
                      icon: Icons.lock,
                      label: 'Change Password',
                      subtitle: 'Update your password',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ChangePasswordScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Notifications Section
                _buildSection(
                  title: 'Notifications',
                  children: [
                    _buildSettingsTile(
                      icon: Icons.notifications,
                      label: 'Notification Settings',
                      subtitle: 'Manage push notifications and alerts',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => NotificationSettingsScreen(
                              settings: _settings,
                              onUpdate: _loadSettings,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Privacy Section
                _buildSection(
                  title: 'Privacy',
                  children: [
                    _buildSettingsTile(
                      icon: Icons.privacy_tip,
                      label: 'Privacy Settings',
                      subtitle: 'Control who can see your activity',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => PrivacySettingsScreen(
                              settings: _settings,
                              onUpdate: _loadSettings,
                            ),
                          ),
                        );
                      },
                    ),
                    _buildSettingsTile(
                      icon: Icons.block,
                      label: 'Blocked Users',
                      subtitle: 'Manage blocked users',
                      onTap: () {
                        Navigator.pushNamed(context, '/friends?tab=4');
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Quiet Hours Section
                _buildSection(
                  title: 'Quiet Hours',
                  children: [
                    _buildSettingsTile(
                      icon: Icons.nightlight_round,
                      label: 'Quiet Hours',
                      subtitle: 'Set times to mute notifications',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => QuietHoursScreen(
                              settings: _settings,
                              onUpdate: _loadSettings,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Language & Region Section
                _buildSection(
                  title: 'Language & Region',
                  children: [
                    _buildSettingsTile(
                      icon: Icons.language,
                      label: 'Language',
                      subtitle: _settings['settings']?['language'] == 'en'
                          ? 'English'
                          : _settings['settings']?['language'] == 'es'
                              ? 'Spanish'
                              : _settings['settings']?['language'] == 'hi'
                                  ? 'Hindi'
                                  : 'English',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => LanguageSettingsScreen(
                              settings: _settings,
                              onUpdate: _loadSettings,
                            ),
                          ),
                        );
                      },
                    ),
                    _buildSettingsTile(
                      icon: Icons.attach_money,
                      label: 'Currency',
                      subtitle: _settings['settings']?['currency'] ?? 'USD',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => LanguageSettingsScreen(
                              settings: _settings,
                              onUpdate: _loadSettings,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Support Section
                _buildSection(
                  title: 'Support',
                  children: [
                    _buildSettingsTile(
                      icon: Icons.help,
                      label: 'Help Center',
                      subtitle: 'FAQs and guides',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SupportScreen(),
                          ),
                        );
                      },
                    ),
                    _buildSettingsTile(
                      icon: Icons.support_agent,
                      label: 'Contact Support',
                      subtitle: 'Get help from our team',
                      onTap: () {
                        // TODO: Open support chat or email
                      },
                    ),
                    _buildSettingsTile(
                      icon: Icons.description,
                      label: 'Terms of Service',
                      subtitle: 'Read our terms',
                      onTap: () {
                        // TODO: Show terms
                      },
                    ),
                    _buildSettingsTile(
                      icon: Icons.privacy_tip,
                      label: 'Privacy Policy',
                      subtitle: 'Read our privacy policy',
                      onTap: () {
                        // TODO: Show privacy policy
                      },
                    ),
                    _buildSettingsTile(
                      icon: Icons.info,
                      label: 'App Version',
                      subtitle: 'Version 1.2.0 (Build 42)',
                      onTap: null,
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Logout Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _logout,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Logout',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Delete Account
                Center(
                  child: TextButton(
                    onPressed: () {
                      _showDeleteAccountDialog();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red.shade400,
                    ),
                    child: const Text('Delete Account'),
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _buildSection(
      {required String title, required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
        ),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.primaryBlue.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: AppColors.primaryBlue, size: 20),
      ),
      title: Text(label),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: onTap,
    );
  }

  void _showDeleteAccountDialog() {
    final TextEditingController confirmController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This action is permanent and cannot be undone. '
              'All your data will be permanently deleted.',
              style: TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 16),
            const Text('Type "DELETE" to confirm:'),
            const SizedBox(height: 8),
            TextField(
              controller: confirmController,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (confirmController.text == 'DELETE') {
                Navigator.pop(context);
                final success = await SettingsService.deleteAccount();
                if (!context.mounted) return;
                if (success) {
                  final authProvider =
                      Provider.of<AuthProvider>(context, listen: false);
                  await authProvider.logout();
                  if (context.mounted) {
                    Navigator.pushReplacementNamed(context, '/login');
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Account deleted successfully'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  }
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );
  }
}





