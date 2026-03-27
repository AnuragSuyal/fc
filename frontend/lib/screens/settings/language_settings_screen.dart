import 'package:flutter/material.dart';
import '../../services/settings_service.dart';
import '../../utils/constants.dart';
import '../../widgets/rounded_scaffold.dart';

class LanguageSettingsScreen extends StatefulWidget {
  final Map<String, dynamic> settings;
  final VoidCallback onUpdate;

  const LanguageSettingsScreen({
    super.key,
    required this.settings,
    required this.onUpdate,
  });

  @override
  State<LanguageSettingsScreen> createState() => _LanguageSettingsScreenState();
}

class _LanguageSettingsScreenState extends State<LanguageSettingsScreen> {
  late String _language;
  late String _currency;
  bool _isLoading = false;

  final List<Map<String, String>> _languages = [
    {'code': 'en', 'name': 'English'},
    {'code': 'es', 'name': 'EspaÃ±ol'},
    {'code': 'hi', 'name': 'à¤¹à¤¿à¤¨à¥à¤¦à¥€'},
    {'code': 'fr', 'name': 'FranÃ§ais'},
    {'code': 'de', 'name': 'Deutsch'},
    {'code': 'zh', 'name': 'ä¸­æ–‡'},
    {'code': 'ja', 'name': 'æ—¥æœ¬èªž'},
    {'code': 'ko', 'name': 'í•œêµ­ì–´'},
  ];

  final List<Map<String, String>> _currencies = [
    {'code': 'USD', 'symbol': '\$', 'name': 'US Dollar'},
    {'code': 'EUR', 'symbol': 'â‚¬', 'name': 'Euro'},
    {'code': 'GBP', 'symbol': 'Â£', 'name': 'British Pound'},
    {'code': 'JPY', 'symbol': 'Â¥', 'name': 'Japanese Yen'},
    {'code': 'INR', 'symbol': 'â‚¹', 'name': 'Indian Rupee'},
    {'code': 'CAD', 'symbol': 'C\$', 'name': 'Canadian Dollar'},
    {'code': 'AUD', 'symbol': 'A\$', 'name': 'Australian Dollar'},
  ];

  @override
  void initState() {
    super.initState();
    _language = widget.settings['settings']?['language'] ?? 'en';
    _currency = widget.settings['settings']?['currency'] ?? 'USD';
  }

  Future<void> _saveSettings() async {
    setState(() => _isLoading = true);

    final success = await SettingsService.updateLanguage({
      'language': _language,
      'currency': _currency,
    });

    if (!mounted) return;

    if (success) {
      widget.onUpdate();
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Language settings updated'),
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
      title: 'Language & Currency',
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
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Language',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                ),
                ..._languages.map((lang) => RadioListTile<String>(
                      title: Text(lang['name']!),
                      value: lang['code']!,
                      // ignore: deprecated_member_use
                      groupValue: _language,
                      // ignore: deprecated_member_use
                      onChanged: (value) {
                        setState(() => _language = value!);
                      },
                      activeColor: AppColors.primaryBlue,
                    )),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Currency',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                ),
                ..._currencies.map((cur) => RadioListTile<String>(
                      title: Text('${cur['name']} (${cur['symbol']})'),
                      subtitle: Text(cur['code']!),
                      value: cur['code']!,
                      // ignore: deprecated_member_use
                      groupValue: _currency,
                      // ignore: deprecated_member_use
                      onChanged: (value) {
                        setState(() => _currency = value!);
                      },
                      activeColor: AppColors.primaryBlue,
                    )),
              ],
            ),
    );
  }
}






