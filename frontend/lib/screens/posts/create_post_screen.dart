import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/post_service.dart';
import '../../utils/constants.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _contentController = TextEditingController();
  final List<_SelectedPostImage> _selectedImages = [];
  final ImagePicker _picker = ImagePicker();

  bool _isLoading = false;
  String? _error;

  bool get _canPost =>
      !_isLoading &&
      (_contentController.text.trim().isNotEmpty || _selectedImages.isNotEmpty);

  @override
  void initState() {
    super.initState();
    _contentController.addListener(_handleComposerChanged);
  }

  @override
  void dispose() {
    _contentController
      ..removeListener(_handleComposerChanged)
      ..dispose();
    super.dispose();
  }

  void _handleComposerChanged() {
    if (!mounted) return;
    setState(() {
      if (_error != null &&
          (_contentController.text.trim().isNotEmpty ||
              _selectedImages.isNotEmpty)) {
        _error = null;
      }
    });
  }

  Future<void> _pickFromGallery() async {
    try {
      final picked = await _picker.pickMultiImage(
        maxWidth: 1440,
        maxHeight: 1440,
        imageQuality: 88,
      );

      if (picked.isEmpty) return;
      await _appendImages(picked);
    } catch (error) {
      _showSnack('Could not open your gallery right now.');
    }
  }

  Future<void> _takePhoto() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1440,
        maxHeight: 1440,
        imageQuality: 88,
      );

      if (picked == null) return;
      await _appendImages([picked]);
    } catch (error) {
      _showSnack('Could not open the camera right now.');
    }
  }

  Future<void> _appendImages(List<XFile> files) async {
    final remainingSlots = 9 - _selectedImages.length;
    final nextFiles = files.take(remainingSlots).toList(growable: false);

    if (nextFiles.isEmpty) {
      _showSnack('You can add up to 9 photos in one post.');
      return;
    }

    final prepared = <_SelectedPostImage>[];
    for (final file in nextFiles) {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) continue;
      prepared.add(_SelectedPostImage(file: file, bytes: bytes));
    }

    if (!mounted || prepared.isEmpty) return;

    setState(() {
      _selectedImages.addAll(prepared);
      _error = null;
    });

    if (files.length > remainingSlots) {
      _showSnack('Only the first $remainingSlots photos were added.');
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  void _showMediaSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceGrey,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Add to your post',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Choose multiple gallery photos or snap one quickly from the camera.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),
                _MediaChoiceTile(
                  icon: Icons.photo_library_outlined,
                  title: 'Gallery',
                  subtitle: 'Pick one or more photos',
                  onTap: () {
                    Navigator.pop(context);
                    _pickFromGallery();
                  },
                ),
                const SizedBox(height: 10),
                _MediaChoiceTile(
                  icon: Icons.photo_camera_outlined,
                  title: 'Camera',
                  subtitle: 'Capture a fresh photo',
                  onTap: () {
                    Navigator.pop(context);
                    _takePhoto();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _createPost() async {
    final content = _contentController.text.trim();
    if (content.isEmpty && _selectedImages.isEmpty) {
      setState(() => _error = 'Write something or add a photo to share.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final post = await PostService.createPost(
        content: content,
        imageFiles: _selectedImages.map((image) => image.file).toList(),
      );

      if (!mounted) return;
      Navigator.pop(context, post != null);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Create Post'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: _canPost ? _createPost : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.surfaceGrey,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Post',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0xFFE4E8EE)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0A101828),
                    blurRadius: 18,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Share a quick update',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Post a thought, a win, or a photo. Your friends will see it in Social Move and your profile feed.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _ActionChip(
                        icon: Icons.add_photo_alternate_outlined,
                        label: _selectedImages.isEmpty
                            ? 'Add Photos'
                            : '${_selectedImages.length}/9 Photos',
                        onTap: _showMediaSheet,
                      ),
                      _ActionChip(
                        icon: Icons.auto_awesome_outlined,
                        label: 'Profile + Social Move',
                        isStatic: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _contentController,
                    minLines: 8,
                    maxLines: 14,
                    maxLength: 2000,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: "What's on your mind?",
                      alignLabelWithHint: true,
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      counterStyle: const TextStyle(
                        color: AppColors.textSecondary,
                      ),
                      contentPadding: const EdgeInsets.all(18),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide:
                            const BorderSide(color: Color(0xFFD7DEE7)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide:
                            const BorderSide(color: Color(0xFFD7DEE7)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(
                          color: AppColors.primaryBlue,
                          width: 1.4,
                        ),
                      ),
                    ),
                  ),
                  if (_selectedImages.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 116,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _selectedImages.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          final image = _selectedImages[index];
                          return Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(22),
                                child: Image.memory(
                                  image.bytes,
                                  width: 116,
                                  height: 116,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Material(
                                  color: Colors.black.withValues(alpha: 0.72),
                                  shape: const CircleBorder(),
                                  child: InkWell(
                                    customBorder: const CircleBorder(),
                                    onTap: () => _removeImage(index),
                                    child: const Padding(
                                      padding: EdgeInsets.all(6),
                                      child: Icon(
                                        Icons.close_rounded,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F3),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFFFD5DD)),
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
                        style: const TextStyle(
                          color: AppColors.errorRed,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SelectedPostImage {
  final XFile file;
  final Uint8List bytes;

  const _SelectedPostImage({
    required this.file,
    required this.bytes,
  });
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isStatic;

  const _ActionChip({
    required this.icon,
    required this.label,
    this.onTap,
    this.isStatic = false,
  });

  @override
  Widget build(BuildContext context) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isStatic ? const Color(0xFFF7F8FA) : Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD9DEE6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppColors.textPrimary),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) {
      return child;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: child,
    );
  }
}

class _MediaChoiceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MediaChoiceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Ink(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFDDE4EC)),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: AppColors.textPrimary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
