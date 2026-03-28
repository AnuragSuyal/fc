import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/settings_service.dart';
import '../../services/upload_service.dart';
import '../../utils/constants.dart';
import '../../utils/media_url.dart';
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
  final ImagePicker _imagePicker = ImagePicker();

  late TextEditingController _usernameController;
  late TextEditingController _bioController;
  String? _avatarUrl;
  String? _coverPhotoUrl;
  bool _isSavingChanges = false;
  bool _isUploadingAvatar = false;
  bool _isUploadingCover = false;
  bool _isBootstrapping = true;
  bool _isDisposed = false;

  bool get _hasActiveUpload => _isUploadingAvatar || _isUploadingCover;
  bool get _isBusy => _isSavingChanges || _hasActiveUpload;

  void _safeSetState(VoidCallback fn) {
    if (!_isDisposed && mounted) {
      setState(fn);
    }
  }

  void _handleDraftChanged() => _safeSetState(() {});

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController();
    _bioController = TextEditingController();
    _usernameController.addListener(_handleDraftChanged);
    _bioController.addListener(_handleDraftChanged);
    _hydrateInitialState();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _usernameController.removeListener(_handleDraftChanged);
    _bioController.removeListener(_handleDraftChanged);
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

    final nextAvatar = resolveMediaUrl(data['avatar']?.toString());
    if (overwrite) {
      _avatarUrl = nextAvatar;
    } else if ((_avatarUrl == null || _avatarUrl!.isEmpty) &&
        nextAvatar != null) {
      _avatarUrl = nextAvatar;
    }

    final nextCover = resolveMediaUrl(data['coverPhoto']?.toString());
    if (overwrite) {
      _coverPhotoUrl = nextCover;
    } else if ((_coverPhotoUrl == null || _coverPhotoUrl!.isEmpty) &&
        nextCover != null) {
      _coverPhotoUrl = nextCover;
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

  Future<ImageSource?> _selectImageSource({
    required bool isAvatar,
  }) async {
    final label = isAvatar ? 'profile photo' : 'cover photo';
    final theme = Theme.of(context);

    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Choose your $label',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                leading: const CircleAvatar(
                  backgroundColor: Colors.black12,
                  child: Icon(Icons.photo_camera_outlined, color: Colors.black),
                ),
                title: const Text('Camera'),
                subtitle: Text('Take a new $label now'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              const SizedBox(height: 8),
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                leading: const CircleAvatar(
                  backgroundColor: Colors.black12,
                  child:
                      Icon(Icons.photo_library_outlined, color: Colors.black),
                ),
                title: const Text('Gallery'),
                subtitle: Text('Pick an existing $label'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<CroppedFile?> _cropSelectedImage(
    XFile image, {
    required bool isAvatar,
  }) async {
    final cropTitle = isAvatar ? 'Crop profile photo' : 'Crop cover photo';

    return ImageCropper().cropImage(
      sourcePath: image.path,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 92,
      aspectRatio: isAvatar
          ? const CropAspectRatio(ratioX: 1, ratioY: 1)
          : const CropAspectRatio(ratioX: 16, ratioY: 9),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: cropTitle,
          toolbarColor: AppColors.primaryBlue,
          toolbarWidgetColor: Colors.white,
          statusBarLight: false,
          backgroundColor: Colors.black,
          activeControlsWidgetColor: AppColors.primaryBlue,
          initAspectRatio: isAvatar
              ? CropAspectRatioPreset.square
              : CropAspectRatioPreset.ratio16x9,
          lockAspectRatio: isAvatar,
        ),
        IOSUiSettings(
          title: cropTitle,
          aspectRatioLockEnabled: isAvatar,
          aspectRatioPickerButtonHidden: isAvatar,
          resetAspectRatioEnabled: !isAvatar,
        ),
        WebUiSettings(
          context: context,
          presentStyle: WebPresentStyle.dialog,
          size: CropperSize(
            width: isAvatar ? 420 : 720,
            height: isAvatar ? 620 : 580,
          ),
          viewwMode: WebViewMode.mode_1,
          dragMode: WebDragMode.move,
          initialAspectRatio: isAvatar ? 1 : 16 / 9,
          movable: true,
          rotatable: true,
          scalable: true,
          zoomable: true,
          zoomOnTouch: true,
          zoomOnWheel: true,
          cropBoxMovable: true,
          cropBoxResizable: !isAvatar,
          background: false,
          modal: true,
          center: true,
          guides: true,
          checkOrientation: true,
          themeData: const WebThemeData(
            scaleSliderMinValue: 0.8,
            scaleSliderMaxValue: 2.8,
            scaleSliderDivisions: 24,
          ),
          translations: WebTranslations(
            title: cropTitle,
            rotateLeftTooltip: 'Rotate left',
            rotateRightTooltip: 'Rotate right',
            cancelButton: 'Cancel',
            cropButton: 'Crop',
          ),
        ),
      ],
    );
  }

  Future<bool> _confirmCroppedImage(
    CroppedFile croppedFile, {
    required bool isAvatar,
  }) async {
    final Uint8List bytes = await croppedFile.readAsBytes();
    if (!mounted) return false;

    final theme = Theme.of(context);
    final preview = AspectRatio(
      aspectRatio: isAvatar ? 1 : 16 / 9,
      child: Image.memory(
        bytes,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      ),
    );

    return (await showDialog<bool>(
          context: context,
          builder: (context) => Dialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            backgroundColor: theme.colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    isAvatar
                        ? 'Use this as your profile photo?'
                        : 'Use this as your cover photo?',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isAvatar
                        ? 'You can reposition it now and update it when it looks right.'
                        : 'This image will appear at the top of your profile after confirmation.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 18),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(isAvatar ? 999 : 24),
                      border: Border.all(color: AppColors.surfaceGrey),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(isAvatar ? 999 : 24),
                      child: isAvatar ? ClipOval(child: preview) : preview,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, false),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primaryBlue,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Update'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        )) ??
        false;
  }

  Future<void> _pickImage({
    required bool isAvatar,
  }) async {
    if (_isBusy) return;

    try {
      final source = await _selectImageSource(isAvatar: isAvatar);
      if (source == null || !mounted) return;

      final image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 95,
        maxWidth: isAvatar ? 1600 : 2400,
      );
      if (image == null || !mounted) return;

      final cropped = await _cropSelectedImage(image, isAvatar: isAvatar);
      if (cropped == null || !mounted) return;

      final confirmed = await _confirmCroppedImage(cropped, isAvatar: isAvatar);
      if (!confirmed || !mounted) return;

      await _uploadAndPersistImage(cropped.path, isAvatar: isAvatar);
    } catch (error) {
      _showSnackBar(
        _errorMessage(error),
        backgroundColor: Colors.red,
      );
    }
  }

  Future<void> _uploadAndPersistImage(
    String sourcePath, {
    required bool isAvatar,
  }) async {
    _safeSetState(() {
      if (isAvatar) {
        _isUploadingAvatar = true;
      } else {
        _isUploadingCover = true;
      }
    });

    try {
      final uploadResult = isAvatar
          ? await UploadService.uploadAvatar(sourcePath)
          : await UploadService.uploadImage(sourcePath);

      final uploadedUrl = resolveMediaUrl(uploadResult['url']?.toString());
      if (uploadedUrl == null) {
        throw Exception(
          isAvatar
              ? 'Failed to upload profile photo.'
              : 'Failed to upload cover photo.',
        );
      }

      final response = await SettingsService.saveProfileOrThrow({
        if (isAvatar) 'avatar': uploadedUrl else 'coverPhoto': uploadedUrl,
      });

      if (!mounted) return;

      final userData = response['user'];
      final user = userData is Map<String, dynamic>
          ? userData
          : userData is Map
              ? Map<String, dynamic>.from(userData)
              : null;

      final nextAvatar =
          resolveMediaUrl(user?['avatar']?.toString()) ?? _avatarUrl;
      final nextCover =
          resolveMediaUrl(user?['coverPhoto']?.toString()) ?? _coverPhotoUrl;

      _safeSetState(() {
        _avatarUrl = isAvatar ? uploadedUrl : nextAvatar;
        _coverPhotoUrl = isAvatar ? nextCover : uploadedUrl;
      });

      context.read<AuthProvider>().updateUserDetails(
            username: user?['username']?.toString(),
            email: user?['email']?.toString(),
            avatar: isAvatar ? uploadedUrl : nextAvatar,
            coverPhoto: isAvatar ? nextCover : uploadedUrl,
            bio: user?['bio']?.toString(),
            region: user?['region']?.toString(),
          );

      widget.onUpdate();
      _showSnackBar(
        isAvatar
            ? 'Profile photo updated successfully'
            : 'Cover photo updated successfully',
        backgroundColor: Colors.green,
      );
    } catch (error) {
      _showSnackBar(
        _errorMessage(error),
        backgroundColor: Colors.red,
      );
    } finally {
      _safeSetState(() {
        if (isAvatar) {
          _isUploadingAvatar = false;
        } else {
          _isUploadingCover = false;
        }
      });
    }
  }

  Future<void> _saveChanges() async {
    if (_isBusy) return;

    final usernameError = _validateUsername(_usernameController.text);
    if (usernameError != null) {
      _showSnackBar(usernameError, backgroundColor: Colors.red);
      return;
    }

    final bio = _bioController.text.trim();
    if (bio.length > 500) {
      _showSnackBar(
        'Bio can be up to 500 characters long.',
        backgroundColor: Colors.red,
      );
      return;
    }

    _safeSetState(() => _isSavingChanges = true);

    try {
      final response = await SettingsService.saveProfileOrThrow({
        'username': _usernameController.text.trim(),
        'bio': bio,
      });

      if (!mounted) return;

      final userData = response['user'];
      final user = userData is Map<String, dynamic>
          ? userData
          : userData is Map
              ? Map<String, dynamic>.from(userData)
              : null;

      final nextUsername =
          user?['username']?.toString() ?? _usernameController.text.trim();
      final nextBio = user?['bio']?.toString() ?? bio;
      final nextAvatar =
          resolveMediaUrl(user?['avatar']?.toString()) ?? _avatarUrl;
      final nextCover =
          resolveMediaUrl(user?['coverPhoto']?.toString()) ?? _coverPhotoUrl;

      context.read<AuthProvider>().updateUserDetails(
            username: nextUsername,
            email: user?['email']?.toString(),
            avatar: nextAvatar,
            coverPhoto: nextCover,
            bio: nextBio,
            region: user?['region']?.toString(),
          );

      widget.onUpdate();

      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Profile updated successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      _safeSetState(() => _isSavingChanges = false);
      _showSnackBar(
        _errorMessage(error),
        backgroundColor: Colors.red,
      );
    }
  }

  String? _validateUsername(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 'Username is required.';
    }
    if (trimmed.length < 3 || trimmed.length > 20) {
      return 'Username must be between 3 and 20 characters.';
    }
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(trimmed)) {
      return 'Username can only contain letters, numbers, and underscores.';
    }
    return null;
  }

  String _errorMessage(Object error) =>
      error.toString().replaceFirst('Exception: ', '').trim();

  void _showSnackBar(
    String message, {
    required Color backgroundColor,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _usernameController.text.trim().isEmpty
        ? 'Guest'
        : _usernameController.text.trim();

    return RoundedScaffold(
      title: 'Profile Information',
      actions: [
        TextButton(
          onPressed: _isBusy || _isBootstrapping ? null : _saveChanges,
          child: Text(
            _isSavingChanges ? 'Saving...' : 'Save',
            style: TextStyle(
              color: _isBusy ? Colors.grey : AppColors.primaryBlue,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
      body: _isBootstrapping
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                AbsorbPointer(
                  absorbing: _isSavingChanges,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        SizedBox(
                          height: 218,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              _buildCoverCard(),
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
                                        username: displayName,
                                        radius: 52,
                                        fontSize: 34,
                                      ),
                                    ),
                                    Positioned(
                                      right: 0,
                                      bottom: 0,
                                      child: Container(
                                        width: 46,
                                        height: 46,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: AppColors.surfaceGrey,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black
                                                  .withValues(alpha: 0.08),
                                              blurRadius: 16,
                                              offset: const Offset(0, 6),
                                            ),
                                          ],
                                        ),
                                        child: _isUploadingAvatar
                                            ? const Padding(
                                                padding: EdgeInsets.all(12),
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2.4,
                                                  color: Colors.black,
                                                ),
                                              )
                                            : IconButton(
                                                icon: const Icon(
                                                  Icons.camera_alt_rounded,
                                                  color: Colors.black,
                                                ),
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
                        const SizedBox(height: 28),
                        TextField(
                          controller: _usernameController,
                          enabled: !_isBusy,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: 'Username',
                            hintText: 'Choose a username',
                            helperText:
                                '3-20 characters, letters, numbers, and underscores only',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            prefixIcon: const Icon(Icons.person),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _bioController,
                          enabled: !_isBusy,
                          minLines: 4,
                          maxLines: 4,
                          maxLength: 500,
                          decoration: InputDecoration(
                            labelText: 'Bio',
                            hintText: 'Tell people a little about yourself',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            alignLabelWithHint: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_isSavingChanges)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Theme.of(context)
                          .colorScheme
                          .surface
                          .withValues(alpha: 0.55),
                      child: const Center(
                        child: CircularProgressIndicator(),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildCoverCard() {
    final hasCover = _coverPhotoUrl != null && _coverPhotoUrl!.isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: 148,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF1F2937),
                    Color(0xFF374151),
                    Color(0xFF9CA3AF),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            if (hasCover)
              Image.network(
                _coverPhotoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.08),
                    Colors.black.withValues(alpha: 0.28),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: FilledButton.icon(
                onPressed: _isBusy ? null : () => _pickImage(isAvatar: false),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.black.withValues(alpha: 0.88),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                icon: _isUploadingCover
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.photo_camera_outlined),
                label: Text(_isUploadingCover ? 'Updating' : 'Cover'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
