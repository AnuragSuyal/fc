import 'package:flutter/material.dart';

import 'package:image_picker/image_picker.dart';

import '../../services/room_service.dart';
import '../../services/upload_service.dart';
import '../../utils/constants.dart';
import '../../widgets/currency_icon.dart';
import 'room_detail_screen.dart';

class CreateRoomScreen extends StatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _announcementController = TextEditingController();
  final _passwordController = TextEditingController();

  String _selectedType = 'voice';
  String _selectedCategory = 'all';
  int _maxParticipants = 20;
  int _entryFee = 0;
  bool _isPrivate = false;
  bool _hdVoice = true;
  bool _requireApproval = false;
  bool _isLoading = false;
  String? _submitError;
  String? _coverImageUrl;

  static const List<_RoomOption> _roomTypes = [
    _RoomOption('voice', 'Stage', 'Live voice room', Icons.mic_rounded,
        Color(0xFF7C6CFF)),
    _RoomOption('music', 'Audio', 'Shared listening room',
        Icons.music_note_rounded, Color(0xFF5FD1A5)),
    _RoomOption('video', 'Stream', 'Watch together room',
        Icons.smart_display_rounded, Color(0xFFFF8A65)),
    _RoomOption('chat', 'Chat', 'Text-first room', Icons.chat_bubble_rounded,
        Color(0xFF59B9FF)),
    _RoomOption('auction', 'Market', 'Fast trade room',
        Icons.storefront_rounded, Color(0xFFFFC857)),
    _RoomOption('game', 'Play', 'Party game room', Icons.sports_esports_rounded,
        Color(0xFFEF6CFF)),
  ];

  static const List<_RoomOption> _categories = [
    _RoomOption('all', 'All', 'Show everywhere', Icons.grid_view_rounded,
        Color(0xFF9AA1B4)),
    _RoomOption('voice', 'Live', 'Voice audience', Icons.waves_rounded,
        Color(0xFF7C6CFF)),
    _RoomOption('music', 'Audio', 'Music crowd', Icons.graphic_eq_rounded,
        Color(0xFF5FD1A5)),
    _RoomOption('video', 'Stream', 'Video fans', Icons.live_tv_rounded,
        Color(0xFFFF8A65)),
    _RoomOption(
        'chat', 'Chat', 'Text social', Icons.forum_rounded, Color(0xFF59B9FF)),
    _RoomOption('battle', 'Arena', 'Competitive rooms',
        Icons.local_fire_department_rounded, Color(0xFFFF6B6B)),
    _RoomOption('auction', 'Market', 'Trading rooms', Icons.sell_rounded,
        Color(0xFFFFC857)),
  ];

  _RoomOption get _selectedTypeOption =>
      _roomTypes.firstWhere((item) => item.value == _selectedType);
  _RoomOption get _selectedCategoryOption =>
      _categories.firstWhere((item) => item.value == _selectedCategory);

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _announcementController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleCreate() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _submitError = null;
    });

    try {
      final password = _passwordController.text.trim();
      final announcement = _announcementController.text.trim();
      final room = await RoomService.createRoom(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        announcement: announcement.isEmpty ? null : announcement,
        type: _selectedType,
        category: _selectedCategory,
        settings: {
          'isPrivate': _isPrivate,
          if (_isPrivate && password.isNotEmpty) 'password': password,
          'maxParticipants': _maxParticipants,
          'entryFee': _entryFee,
          'hdVoice': _hdVoice,
          'requireApproval': _requireApproval,
          'allowVideo': _selectedType == 'video',
          'allowScreenShare': _selectedType == 'video',
        },
        theme: {
          'background': _selectedType == 'video'
              ? 'cinema'
              : _selectedType == 'music'
                  ? 'pulse'
                  : _selectedType == 'game'
                      ? 'arcade'
                      : 'midnight',
          if (_coverImageUrl != null && _coverImageUrl!.isNotEmpty)
            'coverImage': _coverImageUrl,
        },
      );

      if (!mounted || room == null) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Room created and synced live.'),
          backgroundColor: AppColors.successGreen,
        ),
      );

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => RoomDetailScreen(room: room)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitError = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickRoomCover() async {
    if (_isLoading) return;

    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (image == null) return;

    setState(() {
      _isLoading = true;
      _submitError = null;
    });

    try {
      final upload = await UploadService.uploadImage(image);
      final url = upload['url']?.toString();
      if (url == null || url.isEmpty) {
        throw Exception('Room photo upload failed.');
      }

      if (!mounted) return;
      setState(() => _coverImageUrl = url);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Room photo added.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitError = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _selectType(String value) {
    setState(() {
      _selectedType = value;
      if (value == 'game' && _selectedCategory == 'all') {
        _selectedCategory = 'battle';
      } else if (value != 'game' &&
          _selectedCategory != 'all' &&
          _categories.any((item) => item.value == value)) {
        _selectedCategory = value;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedType = _selectedTypeOption;

    return Scaffold(
      backgroundColor: const Color(0xFF08080C),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.black,
          ),
        ),
        title: const Text(
          'Create Room',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      bottomNavigationBar: _buildBottomBar(),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF10101A), Color(0xFF09090E), Color(0xFF050507)],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 140),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeroCard(selectedType),
                  const SizedBox(height: 18),
                  if (_submitError != null) ...[
                    _buildErrorCard(),
                    const SizedBox(height: 18),
                  ],
                  _buildSectionCard(
                    title: 'Room details',
                    subtitle: 'Set the basics people will see before joining.',
                    child: Column(
                      children: [
                        _buildLabel('Room name'),
                        const SizedBox(height: 10),
                        _buildTextField(
                          controller: _nameController,
                          hintText: 'Late Night Hangout',
                          validator: (value) {
                            final name = value?.trim() ?? '';
                            if (name.isEmpty) return 'Room name is required';
                            if (name.length < 3) {
                              return 'Name must be at least 3 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 18),
                        _buildLabel('Description'),
                        const SizedBox(height: 10),
                        _buildTextField(
                          controller: _descriptionController,
                          hintText: 'What is happening in this room tonight?',
                          maxLines: 4,
                          validator: (value) {
                            if ((value?.trim().length ?? 0) > 200) {
                              return 'Description must be under 200 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 18),
                        _buildLabel('Announcement'),
                        const SizedBox(height: 10),
                        _buildTextField(
                          controller: _announcementController,
                          hintText: 'Pin a short note for everyone joining live',
                          maxLines: 3,
                          validator: (value) {
                            if ((value?.trim().length ?? 0) > 500) {
                              return 'Announcement must be under 500 characters';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSectionCard(
                    title: 'Room photo',
                    subtitle:
                        'Upload a local image for room info and previews.',
                    child: GestureDetector(
                      onTap: _pickRoomCover,
                      child: Container(
                        height: 170,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          gradient:
                              _coverImageUrl == null || _coverImageUrl!.isEmpty
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
                          image: _coverImageUrl != null &&
                                  _coverImageUrl!.isNotEmpty
                              ? DecorationImage(
                                  image: NetworkImage(_coverImageUrl!),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(22),
                            color: Colors.black.withValues(alpha: 0.18),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              FilledButton.tonalIcon(
                                onPressed: _pickRoomCover,
                                icon: const Icon(Icons.photo_library_outlined),
                                label: Text(_coverImageUrl == null
                                    ? 'Choose photo'
                                    : 'Change photo'),
                              ),
                              const Spacer(),
                              Text(
                                _coverImageUrl == null
                                    ? 'Tap to add a room cover from your device'
                                    : 'Room cover ready for live preview',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSectionCard(
                    title: 'Room style',
                    subtitle:
                        'Simple names, cleaner branding, same live features.',
                    child: _buildOptionGrid(
                      options: _roomTypes,
                      selectedValue: _selectedType,
                      onSelected: _selectType,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSectionCard(
                    title: 'Discovery',
                    subtitle:
                        'Pick where this room should show up in the live lobby.',
                    child: _buildOptionGrid(
                      options: _categories,
                      selectedValue: _selectedCategory,
                      onSelected: (value) {
                        setState(() => _selectedCategory = value);
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSectionCard(
                    title: 'Capacity and entry',
                    subtitle:
                        'Tune size and coin entry before the room goes live.',
                    child: Column(
                      children: [
                        _buildSliderRow(
                          label: 'Max participants',
                          valueText: '$_maxParticipants',
                          helper:
                              'Good for ${_maxParticipants <= 12 ? 'small circles' : _maxParticipants <= 40 ? 'active hangouts' : 'big public rooms'}',
                          icon: Icon(
                            Icons.groups_rounded,
                            color: selectedType.color,
                            size: 18,
                          ),
                          slider: Slider(
                            value: _maxParticipants.toDouble(),
                            min: 2,
                            max: 100,
                            divisions: 98,
                            activeColor: selectedType.color,
                            label: '$_maxParticipants',
                            onChanged: (value) {
                              setState(() => _maxParticipants = value.round());
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildSliderRow(
                          label: 'Entry fee',
                          valueText: '$_entryFee',
                          helper: _entryFee == 0
                              ? 'Open room for everyone'
                              : 'Coins required to join',
                          icon: const CurrencyIcon.coins(size: 18),
                          slider: Slider(
                            value: _entryFee.toDouble(),
                            min: 0,
                            max: 1000,
                            divisions: 100,
                            activeColor: Colors.amber,
                            label: '$_entryFee',
                            onChanged: (value) {
                              setState(() => _entryFee = value.round());
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSectionCard(
                    title: 'Privacy and access',
                    subtitle:
                        'Choose how people enter and whether hosts approve the room.',
                    child: Column(
                      children: [
                        _buildToggleTile(
                          title: 'Private room',
                          subtitle: 'Require a password before anyone joins',
                          value: _isPrivate,
                          activeColor: selectedType.color,
                          icon: Icons.lock_rounded,
                          onChanged: (value) {
                            setState(() {
                              _isPrivate = value;
                              if (!value) {
                                _passwordController.clear();
                              }
                            });
                          },
                        ),
                        if (_isPrivate) ...[
                          const SizedBox(height: 14),
                          _buildTextField(
                            controller: _passwordController,
                            hintText: 'Create a room password',
                            obscureText: true,
                            validator: (value) {
                              if (_isPrivate &&
                                  (value?.trim().isEmpty ?? true)) {
                                return 'Password is required for private rooms';
                              }
                              return null;
                            },
                          ),
                        ],
                        const SizedBox(height: 10),
                        _buildToggleTile(
                          title: 'Speaker approval',
                          subtitle: 'Approve people before they take the mic',
                          value: _requireApproval,
                          activeColor: selectedType.color,
                          icon: Icons.verified_user_rounded,
                          onChanged: (value) {
                            setState(() => _requireApproval = value);
                          },
                        ),
                        const SizedBox(height: 10),
                        _buildToggleTile(
                          title: 'Clear audio',
                          subtitle:
                              'Prefer higher voice quality for live rooms',
                          value: _hdVoice,
                          activeColor: selectedType.color,
                          icon: Icons.graphic_eq_rounded,
                          onChanged: (value) {
                            setState(() => _hdVoice = value);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroCard(_RoomOption selectedType) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            selectedType.color.withValues(alpha: 0.28),
            const Color(0xFF171723),
            const Color(0xFF0F0F16),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white10),
        boxShadow: [
          BoxShadow(
            color: selectedType.color.withValues(alpha: 0.18),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(selectedType.icon, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${selectedType.label} room',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      selectedType.subtitle,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildHeroPill(
                const Icon(
                  Icons.bolt_rounded,
                  color: Color(0xFF63E6BE),
                  size: 16,
                ),
                'Live sync ready',
              ),
              _buildHeroPill(
                const Icon(
                  Icons.groups_rounded,
                  color: Colors.white,
                  size: 16,
                ),
                '$_maxParticipants spots',
              ),
              _buildHeroPill(
                Icon(
                  Icons.explore_rounded,
                  color: selectedType.color,
                  size: 16,
                ),
                _selectedCategoryOption.label,
              ),
              _buildHeroPill(
                const CurrencyIcon.coins(size: 16),
                _entryFee == 0 ? 'Free entry' : '$_entryFee coins',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroPill(Widget icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF12121A),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    String? Function(String?)? validator,
    int maxLines = 1,
    bool obscureText = false,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      obscureText: obscureText,
      style: const TextStyle(color: Colors.white),
      validator: validator,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.white10),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.primaryBlue),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.errorRed),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.errorRed),
        ),
      ),
    );
  }

  Widget _buildOptionGrid({
    required List<_RoomOption> options,
    required String selectedValue,
    required ValueChanged<String> onSelected,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        final columns = constraints.maxWidth > 500 ? 3 : 2;
        final tileWidth =
            (constraints.maxWidth - ((columns - 1) * spacing)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: options.map((option) {
            final selected = selectedValue == option.value;
            return SizedBox(
              width: tileWidth,
              child: GestureDetector(
                onTap: () => onSelected(option.value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: selected
                        ? option.color.withValues(alpha: 0.18)
                        : Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected ? option.color : Colors.white10,
                      width: selected ? 1.4 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              option.icon,
                              size: 18,
                              color: selected ? option.color : Colors.white70,
                            ),
                          ),
                          const Spacer(),
                          if (selected)
                            Icon(
                              Icons.check_circle_rounded,
                              color: option.color,
                              size: 18,
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        option.label,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        option.subtitle,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildSliderRow({
    required String label,
    required String valueText,
    required String helper,
    required Widget icon,
    required Widget slider,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              icon,
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  valueText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            helper,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          slider,
        ],
      ),
    );
  }

  Widget _buildToggleTile({
    required String title,
    required String subtitle,
    required bool value,
    required Color activeColor,
    required IconData icon,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: activeColor.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: activeColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: activeColor,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.errorRed.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.errorRed.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.errorRed,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _submitError ?? '',
              style: const TextStyle(color: Colors.white, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0B10),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Rooms appear live in the lobby right after creation.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleCreate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _selectedTypeOption.color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Create Room',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomOption {
  final String value;
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _RoomOption(
    this.value,
    this.label,
    this.subtitle,
    this.icon,
    this.color,
  );
}
