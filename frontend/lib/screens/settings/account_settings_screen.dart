import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../services/upload_service.dart';
import '../../providers/auth_provider.dart';
import '../../services/settings_service.dart';
import '../../utils/constants.dart';
import '../../widgets/rounded_scaffold.dart';
import '../../widgets/user_avatar.dart';

class AccountSettingsScreen extends StatefulWidget {
  final Map<String, dynamic> settings;
  final VoidCallback onUpdate;

  const AccountSettingsScreen({
    super.key,
    required this.settings,
    required this.onUpdate,
  });

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  late TextEditingController _usernameController;
  late TextEditingController _bioController;
  String? _avatarUrl;
  String? _coverPhotoUrl;
  bool _isLoading = false;
  bool _isBootstrapping = true;
  bool _isDisposed = false;

  void _safeSetState(VoidCallback fn) {
    if (!_isDisposed && mounted) {
      setState(fn);
    }
  }

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController();
    _bioController = TextEditingController();
    _hydrateInitialState();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _populateFromSettings(
    Map<String, dynamic> data, {
    bool overwrite = false,
  }) {
    String textValue(dynamic value) => value?.toString() ?? '';

    if (overwrite || _usernameController.text.trim().isEmpty) {
      _usernameController.text = textValue(data['username']);
    }
    if (overwrite || _bioController.text.trim().isEmpty) {
      _bioController.text = textValue(data['bio']);
    }

    final nextAvatar = data['avatar']?.toString();
    if (overwrite || (_avatarUrl == null || _avatarUrl!.isEmpty)) {
      _avatarUrl = (nextAvatar != null && nextAvatar.isNotEmpty)
          ? nextAvatar
          : _avatarUrl;
    }

    final nextCover = data['coverPhoto']?.toString();
    if (overwrite || (_coverPhotoUrl == null || _coverPhotoUrl!.isEmpty)) {
      _coverPhotoUrl = (nextCover != null && nextCover.isNotEmpty)
          ? nextCover
          : _coverPhotoUrl;
    }
  }

  Future<void> _hydrateInitialState() async {
    final authUser = context.read<AuthProvider>().user;
    if (authUser != null) {
      _populateFromSettings({
        'username': authUser.username,
        'avatar': authUser.avatar,
        'coverPhoto': authUser.coverPhoto,
        'bio': authUser.bio,
      });
    }

    if (widget.settings.isNotEmpty) {
      _populateFromSettings(widget.settings, overwrite: true);
    }

    final needsServerHydration = widget.settings.isEmpty ||
        _usernameController.text.trim().isEmpty ||
        ((_avatarUrl == null || _avatarUrl!.isEmpty) &&
            (_coverPhotoUrl == null || _coverPhotoUrl!.isEmpty));

    if (needsServerHydration) {
      final settings = await SettingsService.getSettings();
      if (!mounted) return;
      if (settings.isNotEmpty) {
        _populateFromSettings(settings, overwrite: true);
      }
    }

    _safeSetState(() => _isBootstrapping = false);
  }

  Future<void> _pickImage({
    required bool isAvatar,
  }) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );

    if (image != null) {
      _safeSetState(() => _isLoading = true);

      try {
        final result = isAvatar
            ? await UploadService.uploadAvatar(image)
            : await UploadService.uploadImage(image);

        final url = result['url']?.toString();
        if (url != null && mounted) {
          _safeSetState(() {
            if (isAvatar) {
              _avatarUrl = url;
            } else {
              _coverPhotoUrl = url;
            }
            _isLoading = false;
          });

          if (isAvatar) {
            context.read<AuthProvider>().updateAvatar(url);
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isAvatar
                    ? 'Profile photo updated successfully'
                    : 'Room/profile cover updated successfully',
              ),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          _safeSetState(() => _isLoading = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  isAvatar
                      ? 'Failed to upload profile photo'
                      : 'Failed to upload cover photo',
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } catch (e) {
        _safeSetState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                e.toString().replaceFirst('Exception: ', ''),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _saveChanges() async {
    _safeSetState(() => _isLoading = true);

    final payload = <String, dynamic>{
      'username': _usernameController.text.trim(),
      'bio': _bioController.text.trim(),
      if (_avatarUrl != null && _avatarUrl!.isNotEmpty) 'avatar': _avatarUrl,
      if (_coverPhotoUrl != null && _coverPhotoUrl!.isNotEmpty)
        'coverPhoto': _coverPhotoUrl,
    };

    final response = await SettingsService.saveProfile(payload);

    if (!mounted) return;

    if (response != null) {
      final user = response['user'];
      if (user is Map<String, dynamic>) {
        context.read<AuthProvider>().updateUserDetails(
              username: user['username']?.toString(),
              email: user['email']?.toString(),
              avatar: user['avatar']?.toString(),
              coverPhoto: user['coverPhoto']?.toString(),
              bio: user['bio']?.toString(),
            );
      }
      widget.onUpdate();
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      _safeSetState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update profile'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return RoundedScaffold(
      title: 'Profile Information',
      actions: [
        TextButton(
          onPressed: _isLoading ? null : _saveChanges,
          child: Text(
            'Save',
            style: TextStyle(
              color: _isLoading ? Colors.grey : AppColors.primaryBlue,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
      body: _isBootstrapping
          ? const Center(child: CircularProgressIndicator())
          : _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 210,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              height: 148,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(24),
                                gradient: _coverPhotoUrl == null ||
                                        _coverPhotoUrl!.isEmpty
                                    ? const LinearGradient(
                                        colors: [
                                          Color(0xFF1F2937),
                                          Color(0xFF4F46E5),
                                          Color(0xFF0EA5E9),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      )
                                    : null,
                                image: _coverPhotoUrl != null &&
                                        _coverPhotoUrl!.isNotEmpty
                                    ? DecorationImage(
                                        image: NetworkImage(_coverPhotoUrl!),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              alignment: Alignment.topRight,
                              padding: const EdgeInsets.all(12),
                              child: FilledButton.tonalIcon(
                                onPressed: () => _pickImage(isAvatar: false),
                                icon: const Icon(Icons.photo_camera_outlined),
                                label: const Text('Cover'),
                              ),
                            ),
                            Positioned(
                              left: 20,
                              bottom: 0,
                              child: Stack(
                                children: [
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Theme.of(context)
                                            .scaffoldBackgroundColor,
                                        width: 4,
                                      ),
                                    ),
                                    child: UserAvatar(
                                      imageUrl: _avatarUrl,
                                      username: _usernameController.text,
                                      radius: 52,
                                      fontSize: 34,
                                    ),
                                  ),
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      decoration: const BoxDecoration(
                                        color: AppColors.primaryBlue,
                                        shape: BoxShape.circle,
                                      ),
                                      child: IconButton(
                                        icon: const Icon(Icons.camera_alt,
                                            color: Colors.white),
                                        onPressed: () =>
                                            _pickImage(isAvatar: true),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Username
                      TextField(
                        controller: _usernameController,
                        decoration: InputDecoration(
                          labelText: 'Username',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          prefixIcon: const Icon(Icons.person),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Bio
                      TextField(
                        controller: _bioController,
                        maxLines: 3,
                        maxLength: 500,
                        decoration: InputDecoration(
                          labelText: 'Bio',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignLabelWithHint: true,
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
