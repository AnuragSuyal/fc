import 'package:flutter/material.dart';
import '../../services/settings_service.dart';
import '../../utils/constants.dart';
import '../../widgets/rounded_scaffold.dart';

class PrivacySettingsScreen extends StatefulWidget {
  final Map<String, dynamic> settings;
  final VoidCallback onUpdate;

  const PrivacySettingsScreen({
    super.key,
    required this.settings,
    required this.onUpdate,
  });

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  late Map<String, dynamic> _privacy;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _privacy = Map.from(widget.settings['settings']?['privacy'] ?? {});
  }

  Future<void> _saveSettings() async {
    setState(() => _isLoading = true);

    final success = await SettingsService.updatePrivacy(_privacy);

    if (!mounted) return;

    if (success) {
      widget.onUpdate();
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Privacy settings updated'),
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
      title: 'Privacy',
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
                  title: 'Show Online Status',
                  subtitle: 'Let others see when you\'re online',
                  value: _privacy['showOnline'] ?? true,
                  onChanged: (value) {
                    setState(() => _privacy['showOnline'] = value);
                  },
                ),
                _buildSwitchTile(
                  title: 'Show Activity',
                  subtitle: 'Share what room you\'re in',
                  value: _privacy['showActivity'] ?? true,
                  onChanged: (value) {
                    setState(() => _privacy['showActivity'] = value);
                  },
                ),
                _buildSwitchTile(
                  title: 'Allow Friend Requests',
                  subtitle: 'Receive friend requests from others',
                  value: _privacy['allowFriendRequests'] ?? true,
                  onChanged: (value) {
                    setState(() => _privacy['allowFriendRequests'] = value);
                  },
                ),
                _buildSwitchTile(
                  title: 'Show Location',
                  subtitle: 'Share your location for nearby feature',
                  value: _privacy['showLocation'] ?? false,
                  onChanged: (value) {
                    setState(() => _privacy['showLocation'] = value);
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






