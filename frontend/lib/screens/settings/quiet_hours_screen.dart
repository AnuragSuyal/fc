import 'package:flutter/material.dart';
import '../../services/settings_service.dart';
import '../../utils/constants.dart';
import '../../widgets/rounded_scaffold.dart';

class QuietHoursScreen extends StatefulWidget {
  final Map<String, dynamic> settings;
  final VoidCallback onUpdate;

  const QuietHoursScreen({
    super.key,
    required this.settings,
    required this.onUpdate,
  });

  @override
  State<QuietHoursScreen> createState() => _QuietHoursScreenState();
}

class _QuietHoursScreenState extends State<QuietHoursScreen> {
  late Map<String, dynamic> _quietHours;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _quietHours = Map.from(widget.settings['settings']?['quietHours'] ??
        {'enabled': false, 'start': '22:00', 'end': '08:00'});
  }

  Future<void> _saveSettings() async {
    setState(() => _isLoading = true);

    final success = await SettingsService.updateQuietHours(_quietHours);

    if (!mounted) return;

    if (success) {
      widget.onUpdate();
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Quiet hours updated'),
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

  Future<void> _selectTime(bool isStart) async {
    final initialTime = isStart
        ? _parseTime(_quietHours['start'])
        : _parseTime(_quietHours['end']);

    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
          hour: initialTime['hour'] ?? 0, minute: initialTime['minute'] ?? 0),
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _quietHours['start'] = _formatTime(picked);
        } else {
          _quietHours['end'] = _formatTime(picked);
        }
      });
    }
  }

  Map<String, int> _parseTime(String time) {
    if (time.isEmpty) return {'hour': 0, 'minute': 0};
    final parts = time.split(':');
    if (parts.length != 2) return {'hour': 0, 'minute': 0};
    return {
      'hour': int.tryParse(parts[0]) ?? 0,
      'minute': int.tryParse(parts[1]) ?? 0,
    };
  }

  String _formatTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return RoundedScaffold(
      title: 'Quiet Hours',
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
                SwitchListTile(
                  title: const Text('Enable Quiet Hours'),
                  subtitle:
                      const Text('Mute notifications during specified hours'),
                  value: _quietHours['enabled'] ?? false,
                  onChanged: (value) {
                    setState(() => _quietHours['enabled'] = value);
                  },
                  activeThumbColor: AppColors.primaryBlue,
                ),
                if (_quietHours['enabled'] == true) ...[
                  const Divider(),
                  ListTile(
                    title: const Text('Start Time'),
                    subtitle: Text(_quietHours['start']),
                    trailing: const Icon(Icons.access_time),
                    onTap: () => _selectTime(true),
                  ),
                  ListTile(
                    title: const Text('End Time'),
                    subtitle: Text(_quietHours['end']),
                    trailing: const Icon(Icons.access_time),
                    onTap: () => _selectTime(false),
                  ),
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'During quiet hours, you will not receive push notifications, '
                      'sounds, or vibrations. Important alerts may still appear.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}






