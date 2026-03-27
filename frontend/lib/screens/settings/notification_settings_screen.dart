import 'package:flutter/material.dart';
import '../../services/settings_service.dart';
import '../../utils/constants.dart';
import '../../widgets/rounded_scaffold.dart';

class NotificationSettingsScreen extends StatefulWidget {
  final Map<String, dynamic> settings;
  final VoidCallback onUpdate;

  const NotificationSettingsScreen({
    super.key,
    required this.settings,
    required this.onUpdate,
  });

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  late Map<String, dynamic> _notifications;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _notifications =
        Map.from(widget.settings['settings']?['notifications'] ?? {});
  }

  Future<void> _saveSettings() async {
    setState(() => _isLoading = true);

    final success = await SettingsService.updateNotifications(_notifications);

    if (!mounted) return;

    if (success) {
      widget.onUpdate();
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notification settings updated'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update settings'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return RoundedScaffold(
      title: 'Notifications',
      actions: [
        TextButton(
          onPressed: _isLoading ? null : _saveSettings,
          child: Text(
            'Save',
            style: TextStyle(
              color: _isLoading ? Colors.grey : Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _buildSwitchTile(
                  title: 'Friend Online',
                  subtitle: 'Get notified when friends come online',
                  value: _notifications['friendOnline'] ?? true,
                  onChanged: (value) {
                    setState(() => _notifications['friendOnline'] = value);
                  },
                ),
                _buildSwitchTile(
                  title: 'Messages',
                  subtitle: 'New message notifications',
                  value: _notifications['messages'] ?? true,
                  onChanged: (value) {
                    setState(() => _notifications['messages'] = value);
                  },
                ),
                _buildSwitchTile(
                  title: 'Gifts',
                  subtitle: 'When you receive gifts',
                  value: _notifications['gifts'] ?? true,
                  onChanged: (value) {
                    setState(() => _notifications['gifts'] = value);
                  },
                ),
                _buildSwitchTile(
                  title: 'Game Invites',
                  subtitle: 'Invitations to play games',
                  value: _notifications['gameInvites'] ?? true,
                  onChanged: (value) {
                    setState(() => _notifications['gameInvites'] = value);
                  },
                ),
                _buildSwitchTile(
                  title: 'Event Reminders',
                  subtitle: 'Upcoming tournaments and events',
                  value: _notifications['eventReminders'] ?? false,
                  onChanged: (value) {
                    setState(() => _notifications['eventReminders'] = value);
                  },
                ),
                const Divider(),
                _buildSwitchTile(
                  title: 'Sound',
                  subtitle: 'Play sound for notifications',
                  value: _notifications['sound'] ?? true,
                  onChanged: (value) {
                    setState(() => _notifications['sound'] = value);
                  },
                ),
                _buildSwitchTile(
                  title: 'Vibrate',
                  subtitle: 'Vibrate on notifications',
                  value: _notifications['vibrate'] ?? true,
                  onChanged: (value) {
                    setState(() => _notifications['vibrate'] = value);
                  },
                ),
              ],
            ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
      activeThumbColor: AppColors.primaryBlue,
    );
  }
}






