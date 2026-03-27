import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/room_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/room_service.dart';
import '../../services/socket_service.dart';
import '../../services/upload_service.dart';
import '../../utils/constants.dart';
import '../../utils/room_permissions.dart';
import '../../utils/room_presets.dart';
import '../../widgets/user_avatar.dart';

class RoomSettingsScreen extends StatefulWidget {
  final RoomModel room;

  const RoomSettingsScreen({
    super.key,
    required this.room,
  });

  @override
  State<RoomSettingsScreen> createState() => _RoomSettingsScreenState();
}

class _RoomSettingsScreenState extends State<RoomSettingsScreen> {
  static const _categories = [
    {'id': 'all', 'label': 'All'},
    {'id': 'voice', 'label': 'Voice'},
    {'id': 'music', 'label': 'Music'},
    {'id': 'video', 'label': 'Video'},
    {'id': 'chat', 'label': 'Chat'},
    {'id': 'battle', 'label': 'Battle'},
    {'id': 'auction', 'label': 'Auction'},
  ];

  late RoomModel _room;
  StreamSubscription<Map<String, dynamic>>? _updates;
  List<Map<String, dynamic>> _bans = const [];
  List<Map<String, dynamic>> _reports = const [];
  bool _isSaving = false;
  bool _loadingBans = true;
  bool _loadingReports = false;

  String? get _userId => context.read<AuthProvider>().user?.id;
  RoomPermissions get _permissions =>
      RoomPermissions(room: _room, userId: _userId);
  bool get _isHost => _permissions.isOwner;
  bool get _canModerate => _permissions.canManageSafety;
  RoomBackgroundPreset get _backgroundPreset =>
      roomBackgroundPresetFor(_room.background);
  RoomModePreset get _modePreset => roomModePresetFor(_room.type);

  @override
  void initState() {
    super.initState();
    _room = widget.room;
    _loadBans();
    _updates = SocketService.roomUpdateStream.listen((event) {
      final roomId = event['_id']?.toString() ??
          event['id']?.toString() ??
          event['roomId'];
      if (roomId != _room.id || !mounted) return;
      unawaited(_reload(includeBans: true));
    });
  }

  @override
  void dispose() {
    _updates?.cancel();
    super.dispose();
  }

  Future<void> _reload({bool includeBans = false}) async {
    final updated = await RoomService.getRoomById(_room.id);
    if (!mounted || updated == null) return;
    setState(() => _room = updated);
    if (includeBans) {
      await _loadBans();
    }
  }

  Future<void> _loadBans() async {
    if (!_canModerate) {
      if (mounted) setState(() => _loadingBans = false);
      return;
    }
    setState(() => _loadingBans = true);
    final bans = await RoomService.getBans(_room.id);
    if (!mounted) return;
    setState(() {
      _bans = bans;
      _loadingBans = false;
    });
  }

  Future<void> _loadReports() async {
    if (!_permissions.canViewReports) {
      if (mounted) setState(() => _loadingReports = false);
      return;
    }
    setState(() => _loadingReports = true);
    final reports = await RoomService.getReports(_room.id);
    if (!mounted) return;
    setState(() {
      _reports = reports;
      _loadingReports = false;
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _showError(Object error) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error.toString().replaceFirst('Exception: ', '')),
        backgroundColor: AppColors.errorRed,
      ),
    );
  }

  Future<void> _savePatch(
    Map<String, dynamic> patch, {
    String? success,
  }) async {
    await _run(() async {
      try {
        final updated = await RoomService.updateRoom(_room.id, patch);
        if (!mounted) return;
        if (updated == null) {
          throw Exception('Could not update room right now.');
        }
        setState(() => _room = updated);
        if (success != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(success)),
          );
        }
      } catch (error) {
        await _showError(error);
      }
    });
  }

  Future<void> _editTitle() async {
    if (!_isHost) return;
    final controller = TextEditingController(text: _room.name);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF111115),
        title: const Text('Room Title', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 50,
          cursorColor: Colors.black87,
          style: const TextStyle(color: Colors.black87),
          decoration: const InputDecoration(
            counterStyle: TextStyle(color: Colors.white54),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white10)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF7A45)),
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.isEmpty || result == _room.name) return;
    await _savePatch({'name': result}, success: 'Room title updated.');
  }

  Future<void> _editAnnouncement() async {
    if (!_permissions.canEditAnnouncement) return;
    final controller = TextEditingController(text: _room.announcement);
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _sheet(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Room Announcement',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                maxLines: 5,
                maxLength: 500,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Share room rules or updates...',
                  hintStyle:
                      TextStyle(color: Colors.white.withValues(alpha: 0.2)),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF7A45),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () =>
                      Navigator.pop(context, controller.text.trim()),
                  child: const Text('Save Notice',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    controller.dispose();
    if (result == null || result == _room.announcement) return;
    await _run(() async {
      try {
        await RoomService.setAnnouncement(_room.id, result);
        await _reload();
      } catch (error) {
        await _showError(error);
      }
    });
  }

  Future<void> _changeCategory() async {
    if (!_isHost) return;
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _sheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _categories
              .map(
                (item) => ListTile(
                  title: Text(item['label']!,
                      style: const TextStyle(color: Colors.white)),
                  leading: Icon(
                    item['id'] == _room.category
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked,
                    color: item['id'] == _room.category
                        ? const Color(0xFFFF7A45)
                        : Colors.white24,
                  ),
                  onTap: () => Navigator.pop(context, item['id']),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (result == null || result == _room.category) return;
    await _savePatch({'category': result}, success: 'Room category updated.');
  }

  Future<void> _changeBackground() async {
    if (!_isHost) return;

    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _sheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Room Background',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose 1 of 5 live themes. Everyone inside the room sees the change instantly.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.58),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            ...roomBackgroundPresets.map(
              (preset) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _backgroundThemeOption(
                  preset: preset,
                  selected: preset.id == _backgroundPreset.id,
                  onTap: () => Navigator.pop(context, preset.id),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (result == null || result == _room.background) return;
    await _savePatch(
      {
        'theme': {'background': result},
      },
      success: 'Room atmosphere updated.',
    );
  }

  Future<void> _changeMode(String type) async {
    if (!_isHost || type == _room.type) return;
    final preset = roomModePresetFor(type);
    await _savePatch(
      {'type': type},
      success: '${preset.label} mode is live now.',
    );
  }

  Future<void> _copyRoomId() async {
    await Clipboard.setData(ClipboardData(text: _room.roomId));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Room ID copied to clipboard.')),
    );
  }

  Future<void> _togglePrivate(bool value) async {
    if (!_permissions.canManageRoomAccess) return;

    var password = '';
    if (value) {
      final controller = TextEditingController();
      final result = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Private Room Password'),
          content: TextField(
            controller: controller,
            obscureText: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      controller.dispose();

      if (result == null || result.isEmpty) return;
      password = result;
    }

    await _savePatch({
      'settings': {
        'isPrivate': value,
        'password': value ? password : '',
      },
    }, success: value ? 'Private room enabled.' : 'Room is now public.');
  }

  Future<void> _toggleGifting(bool value) async {
    if (!_permissions.canManageGifting) return;
    await _toggleFlag(
      'allowGifts',
      value,
      value ? 'Gifting is now enabled.' : 'Gifting is now disabled.',
    );
  }

  Future<void> _toggleStageLock(bool value) async {
    if (!_permissions.canManageStage) return;
    await _toggleFlag(
      'stageJoinsLocked',
      value,
      value ? 'Stage joins are now locked.' : 'Stage joins are open again.',
    );
  }

  Future<void> _toggleMicApproval(bool value) async {
    if (!_permissions.canManageRoomIdentity) return;
    await _toggleFlag(
      'requireApproval',
      value,
      value
          ? 'Mic approval is now required.'
          : 'Guests can join the stage directly again.',
    );
  }

  Future<void> _changeMaxActiveSpeakers() async {
    if (!_permissions.canManageRoomIdentity) return;

    final result = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _sheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Active Speaker Seats',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Choose how many guest speaker seats stay live at the same time.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: List.generate(8, (index) {
                final seatCount = index + 1;
                final selected = seatCount == _room.maxActiveSpeakers;
                return ChoiceChip(
                  label: Text('$seatCount seats'),
                  selected: selected,
                  onSelected: (_) => Navigator.pop(context, seatCount),
                  selectedColor: const Color(0xFFFF7A45),
                  backgroundColor: const Color(0xFF1A1A22),
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : Colors.white70,
                    fontWeight: FontWeight.w700,
                  ),
                  side: BorderSide(
                    color: selected
                        ? const Color(0xFFFF7A45)
                        : Colors.white.withValues(alpha: 0.06),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );

    if (result == null || result == _room.maxActiveSpeakers) return;
    await _savePatch(
      {
        'settings': {'maxActiveSpeakers': result}
      },
      success: 'Active speaker seat limit updated.',
    );
  }

  Future<void> _toggleFlag(String key, bool value, String success) async {
    await _savePatch({
      'settings': {key: value}
    }, success: success);
  }

  Future<void> _pickCover() async {
    if (!_isHost) return;
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (image == null) return;
    await _run(() async {
      try {
        final upload = await UploadService.uploadImage(image);
        final url = upload['url']?.toString();
        if (url == null || url.isEmpty) {
          throw Exception('Image upload failed.');
        }
        final updated = await RoomService.updateRoom(_room.id, {
          'theme': {'coverImage': url},
        });
        if (!mounted || updated == null) return;
        setState(() => _room = updated);
      } catch (error) {
        await _showError(error);
      }
    });
  }

  // ignore: unused_element
  Future<void> _showMembers() async {
    if (!_canModerate) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _sheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Moderation & Admins',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _room.participants.length,
                separatorBuilder: (_, __) =>
                    const Divider(color: Colors.white10),
                itemBuilder: (context, index) {
                  final participant = _room.participants[index];
                  final isHost = participant.userId == _room.hostId;
                  final isCohost = _room.coHostIds.contains(participant.userId);
                  final isModerator =
                      _room.moderatorIds.contains(participant.userId);
                  final canManageRoles =
                      _permissions.canManageAdminRole(participant);
                  final canModerateParticipant =
                      _permissions.canModerateParticipant(participant);
                  final canManageSpeakerState =
                      _permissions.canManageSpeakerState(participant);
                  final canTransferOwnership =
                      _permissions.canTransferOwnershipTo(participant);
                  final role = isHost
                      ? 'Host'
                      : isCohost
                          ? 'Co-host'
                          : isModerator
                              ? 'Moderator'
                              : participant.role;

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: UserAvatar(
                      imageUrl: participant.avatar,
                      username: participant.username,
                      radius: 22,
                    ),
                    title: Text(participant.username,
                        style: const TextStyle(color: Colors.white)),
                    subtitle: Text(
                      participant.raisedHand ? '$role • Mic request' : role,
                      style: const TextStyle(color: Colors.white54),
                    ),
                    trailing: isHost
                        ? const Text('Owner',
                            style: TextStyle(color: Color(0xFFFF7A45)))
                        : Builder(
                            builder: (context) {
                              final actions = <PopupMenuEntry<String>>[
                                if (canTransferOwnership)
                                  const PopupMenuItem(
                                    value: 'transfer_ownership',
                                    child: Text('Transfer ownership'),
                                  ),
                                if (canManageRoles)
                                  PopupMenuItem(
                                    value: isModerator
                                        ? 'remove_moderator'
                                        : 'add_moderator',
                                    child: Text(isModerator
                                        ? 'Remove moderator'
                                        : 'Make moderator'),
                                  ),
                                if (_isHost && canManageRoles)
                                  PopupMenuItem(
                                    value: isCohost
                                        ? 'remove_cohost'
                                        : 'add_cohost',
                                    child: Text(isCohost
                                        ? 'Remove co-host'
                                        : 'Make co-host'),
                                  ),
                                if (canManageSpeakerState)
                                  PopupMenuItem(
                                    value: participant.seatIndex >= 0
                                        ? 'move_to_audience'
                                        : 'approve_mic',
                                    child: Text(participant.seatIndex >= 0
                                        ? 'Move to audience'
                                        : 'Approve mic request'),
                                  ),
                                if (canModerateParticipant)
                                  PopupMenuItem(
                                    value:
                                        participant.isMuted ? 'unmute' : 'mute',
                                    child: Text(participant.isMuted
                                        ? 'Unmute member'
                                        : 'Mute member'),
                                  ),
                                if (canModerateParticipant)
                                  const PopupMenuItem(
                                    value: 'kick',
                                    child: Text('Kick from room'),
                                  ),
                                if (canModerateParticipant)
                                  const PopupMenuItem(
                                    value: 'ban',
                                    child: Text('Ban from room'),
                                  ),
                              ];

                              if (actions.isEmpty) {
                                return const SizedBox.shrink();
                              }

                              return PopupMenuButton<String>(
                                iconColor: Colors.white54,
                                onSelected: (action) {
                                  Navigator.pop(context);
                                  _handleMemberAction(participant, action);
                                },
                                itemBuilder: (_) => actions,
                              );
                            },
                          ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleMemberAction(
      Participant participant, String action) async {
    await _run(() async {
      try {
        switch (action) {
          case 'transfer_ownership':
            final shouldTransfer = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: const Color(0xFF111115),
                title: const Text(
                  'Transfer Ownership',
                  style: TextStyle(color: Colors.white),
                ),
                content: Text(
                  'Make ${participant.username} the new room owner? You will stay as co-host.',
                  style: const TextStyle(color: Colors.white70),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFF7A45),
                    ),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Transfer'),
                  ),
                ],
              ),
            );
            if (shouldTransfer != true) break;
            final updated = await RoomService.transferOwnership(
              _room.id,
              participant.userId,
            );
            if (updated != null && mounted) setState(() => _room = updated);
            break;
          case 'add_moderator':
            final updated =
                await RoomService.addModerator(_room.id, participant.userId);
            if (updated != null && mounted) setState(() => _room = updated);
            break;
          case 'approve_mic':
            await RoomService.promoteParticipant(_room.id, participant.userId);
            await _reload();
            break;
          case 'move_to_audience':
            await RoomService.demoteParticipant(_room.id, participant.userId);
            await _reload();
            break;
          case 'remove_moderator':
            final updated =
                await RoomService.removeModerator(_room.id, participant.userId);
            if (updated != null && mounted) setState(() => _room = updated);
            break;
          case 'add_cohost':
            await RoomService.assignCoHost(_room.id, participant.userId);
            await _reload();
            break;
          case 'remove_cohost':
            await RoomService.removeCoHost(_room.id, participant.userId);
            await _reload();
            break;
          case 'mute':
            await RoomService.muteParticipant(_room.id, participant.userId,
                muted: true);
            await _reload();
            break;
          case 'unmute':
            await RoomService.muteParticipant(_room.id, participant.userId,
                muted: false);
            await _reload();
            break;
          case 'kick':
            await RoomService.kickParticipant(_room.id, participant.userId);
            await _reload();
            break;
          case 'ban':
            _bans = await RoomService.banParticipant(
                _room.id, participant.userId,
                reason: 'Removed by room management');
            await _reload();
            break;
        }
      } catch (error) {
        await _showError(error);
      }
    });
  }

  // ignore: unused_element
  Future<void> _showBans() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _sheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Banned Users',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
            const SizedBox(height: 16),
            if (_loadingBans)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator(),
              )
            else if (_bans.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('No banned users right now.',
                    style: TextStyle(color: Colors.white54)),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _bans.length,
                  separatorBuilder: (_, __) =>
                      const Divider(color: Colors.white10),
                  itemBuilder: (context, index) {
                    final ban = _bans[index];
                    final user = ban['userId'] is Map
                        ? Map<String, dynamic>.from(ban['userId'] as Map)
                        : const <String, dynamic>{};
                    final id = user['_id']?.toString() ?? '';
                    final username = user['username']?.toString() ?? 'Unknown';
                    final avatar = user['avatar']?.toString();
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: UserAvatar(
                        imageUrl: avatar,
                        username: username,
                        radius: 22,
                      ),
                      title: Text(username,
                          style: const TextStyle(color: Colors.white)),
                      subtitle: Text(
                        ban['reason']?.toString().isNotEmpty == true
                            ? ban['reason'].toString()
                            : 'Banned member',
                        style: const TextStyle(color: Colors.white54),
                      ),
                      trailing: TextButton(
                        onPressed: _isSaving || id.isEmpty
                            ? null
                            : () async {
                                Navigator.pop(context);
                                await _run(() async {
                                  try {
                                    final bans =
                                        await RoomService.unbanParticipant(
                                            _room.id, id);
                                    if (!mounted) return;
                                    setState(() => _bans = bans);
                                  } catch (error) {
                                    await _showError(error);
                                  }
                                });
                              },
                        child: const Text('Unban',
                            style: TextStyle(color: Color(0xFFFF7A45))),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showReports() async {
    if (!_permissions.canViewReports) return;
    if (_reports.isEmpty && !_loadingReports) {
      await _loadReports();
    }

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _sheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Room Reports',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
            const SizedBox(height: 16),
            if (_loadingReports)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator(),
              )
            else if (_reports.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('No moderation reports yet.',
                    style: TextStyle(color: Colors.white54)),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _reports.length,
                  separatorBuilder: (_, __) =>
                      const Divider(color: Colors.white10),
                  itemBuilder: (context, index) {
                    final report = _reports[index];
                    final user = report['userId'] is Map
                        ? Map<String, dynamic>.from(report['userId'] as Map)
                        : const <String, dynamic>{};
                    final username = user['username']?.toString() ?? 'Unknown';
                    final avatar = user['avatar']?.toString();
                    final createdAt = DateTime.tryParse(
                      report['createdAt']?.toString() ?? '',
                    );

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: UserAvatar(
                        imageUrl: avatar,
                        username: username,
                        radius: 22,
                      ),
                      title: Text(username,
                          style: const TextStyle(color: Colors.white)),
                      subtitle: Text(
                        report['reason']?.toString().isNotEmpty == true
                            ? report['reason'].toString()
                            : 'Room report',
                        style: const TextStyle(color: Colors.white54),
                      ),
                      trailing: createdAt == null
                          ? null
                          : Text(
                              '${createdAt.day}/${createdAt.month}',
                              style: const TextStyle(color: Colors.white38),
                            ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sheet({required Widget child}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      decoration: const BoxDecoration(
        color: Color(0xFF111115),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SafeArea(top: false, child: child),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
        ),
      ),
    );
  }

  Widget _group(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111115),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: children,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pop(context, _room);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0B0B),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0B0B0B),
          elevation: 0,
          centerTitle: true,
          title: const Text(
            'Room Settings',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFFFF7A45),
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Color(0xFFFF7A45)),
            onPressed: () => Navigator.pop(context, _room),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.check_rounded,
                  color: Color(0xFFFF7A45), size: 28),
              onPressed: () => Navigator.pop(context, _room),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            _sectionLabel('Room Identity'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 4,
                  child: GestureDetector(
                    onTap:
                        _permissions.canManageRoomIdentity ? _pickCover : null,
                    child: Container(
                      height: 240,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08)),
                        image: _room.coverImage != null &&
                                _room.coverImage!.isNotEmpty
                            ? DecorationImage(
                                image: NetworkImage(_room.coverImage!),
                                fit: BoxFit.cover,
                              )
                            : null,
                        gradient: _room.coverImage == null ||
                                _room.coverImage!.isEmpty
                            ? const LinearGradient(
                                colors: [Color(0xFF1D4ED8), Color(0xFF7C3AED)],
                              )
                            : null,
                      ),
                      child: Stack(
                        children: [
                          Positioned(
                            bottom: 16,
                            left: 16,
                            right: 16,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.1)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.photo_camera_rounded,
                                      color: Colors.white, size: 16),
                                  SizedBox(width: 6),
                                  Text(
                                    'CHANGE COVER',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 5,
                  child: Column(
                    children: [
                      _identityField(
                        label: 'ROOM TITLE',
                        value: _room.name,
                        onTap: _permissions.canManageRoomIdentity
                            ? _editTitle
                            : null,
                      ),
                      const SizedBox(height: 16),
                      _identityField(
                        label: 'ANNOUNCEMENT',
                        value: _room.announcement.isEmpty
                            ? 'Tap to add announcement'
                            : _room.announcement,
                        onTap: _permissions.canEditAnnouncement
                            ? _editAnnouncement
                            : null,
                        maxLines: 4,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            _sectionLabel('Permissions & Safety'),
            _group([
              _switchItem(
                title: 'Ban Text Chatting',
                subtitle: 'Only owner and admins can type',
                icon: Icons.block_rounded,
                iconColor: Colors.redAccent,
                value: _room.banTextChat,
                enabled: _permissions.canManageSafety,
                onChanged: (v) =>
                    _toggleFlag('banTextChat', v, 'Text chat limited.'),
              ),
              _switchItem(
                title: 'Ban Photo Chatting',
                subtitle: 'Stop guests from sharing images in room',
                icon: Icons.no_photography_rounded,
                iconColor: Colors.cyanAccent,
                value: _room.banPhotoChat,
                enabled: _permissions.canManageSafety,
                onChanged: (v) =>
                    _toggleFlag('banPhotoChat', v, 'Photo sharing updated.'),
              ),
              _switchItem(
                title: 'High Quality Mode',
                subtitle: 'Enhanced 320kbps audio stream',
                icon: Icons.high_quality_rounded,
                iconColor: Colors.greenAccent,
                value: _room.hdVoice,
                enabled: _permissions.canManageSafety,
                onChanged: (v) =>
                    _toggleFlag('hdVoice', v, 'Audio quality updated.'),
              ),
              _switchItem(
                title: 'Allow Gifting',
                subtitle: 'Let members send gifts in this room',
                icon: Icons.card_giftcard_rounded,
                iconColor: const Color(0xFFFF6F61),
                value: _room.allowGifts,
                enabled: _permissions.canManageGifting,
                onChanged: _toggleGifting,
              ),
              _switchItem(
                title: 'Lock Stage Joins',
                subtitle: 'Only owner and admins can move people onto stage',
                icon: Icons.lock_person_rounded,
                iconColor: const Color(0xFF52A1FF),
                value: _room.stageJoinsLocked,
                enabled: _permissions.canManageStage,
                onChanged: _toggleStageLock,
              ),
              _switchItem(
                title: 'Require Mic Approval',
                subtitle: 'Guests send a request before becoming a speaker',
                icon: Icons.record_voice_over_rounded,
                iconColor: const Color(0xFFFFB347),
                value: _room.requireApproval,
                enabled: _permissions.canManageRoomIdentity,
                onChanged: _toggleMicApproval,
              ),
              const Divider(color: Colors.white10, height: 1),
              _navItem(
                title: 'Category',
                count: _room.category.toUpperCase(),
                icon: Icons.category_rounded,
                onTap:
                    _permissions.canManageRoomIdentity ? _changeCategory : null,
              ),
              _navItem(
                title: 'Members & Roles',
                count: '${_room.participantCount}',
                icon: Icons.groups_rounded,
                onTap: _permissions.canManageStage ? _showMembers : null,
              ),
              _navItem(
                title: 'Active Speaker Seats',
                count: '${_room.maxActiveSpeakers}',
                icon: Icons.podcasts_rounded,
                onTap: _permissions.canManageRoomIdentity
                    ? _changeMaxActiveSpeakers
                    : null,
              ),
              _switchItem(
                title: 'Private Room',
                subtitle: _room.isPrivate
                    ? 'Password protected live'
                    : 'Open to everyone',
                icon: Icons.lock_rounded,
                iconColor: Colors.amberAccent,
                value: _room.isPrivate,
                enabled: _permissions.canManageRoomAccess,
                onChanged: _togglePrivate,
              ),
              _navItem(
                title: 'Banned Users',
                count: _loadingBans ? 'Loading' : '${_bans.length}',
                icon: Icons.gpp_bad_rounded,
                onTap: _permissions.canManageStage ? _showBans : null,
              ),
              _navItem(
                title: 'Room Reports',
                count: _loadingReports ? 'Loading' : '${_reports.length}',
                icon: Icons.flag_rounded,
                onTap: _permissions.canViewReports ? _showReports : null,
              ),
            ]),
            _sectionLabel('Atmosphere'),
            LayoutBuilder(
              builder: (context, constraints) {
                final backgroundCard = _atmosphereCard(
                  label: 'BACKGROUND',
                  name: _backgroundPreset.label,
                  subtitle: _backgroundPreset.subtitle,
                  icon: Icons.wallpaper_rounded,
                  preview: _buildBackgroundSwatch(_backgroundPreset),
                  onTap: _permissions.canManageRoomIdentity
                      ? _changeBackground
                      : null,
                );

                final roomModeCard = _roomModeCard();

                if (constraints.maxWidth < 560) {
                  return Column(
                    children: [
                      backgroundCard,
                      const SizedBox(height: 12),
                      roomModeCard,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: backgroundCard),
                    const SizedBox(width: 12),
                    Expanded(child: roomModeCard),
                  ],
                );
              },
            ),
            const SizedBox(height: 48),
            Center(
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: _copyRoomId,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111115),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Room ID: ',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 11),
                      ),
                      Text(
                        _room.roomId,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.copy_rounded,
                          color: Color(0xFFFF7A45), size: 14),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            if (_permissions.canEndRoom) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: OutlinedButton(
                  onPressed: _isSaving ? null : _dissolveRoom,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFF4B4B),
                    side: BorderSide(
                        color: const Color(0xFFFF4B4B).withValues(alpha: 0.4)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
                  ),
                  child: const Text('Dissolve Room',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ],
        ),
      ),
    );
  }

  Widget _identityField({
    required String label,
    required String value,
    VoidCallback? onTap,
    int maxLines = 1,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF111115),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFFFF7A45),
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _switchItem({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required bool value,
    bool enabled = true,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: enabled ? onChanged : null,
            activeThumbColor: const Color(0xFFFF7A45),
            activeTrackColor: const Color(0xFFFF7A45).withValues(alpha: 0.3),
            inactiveThumbColor: Colors.grey[700],
            inactiveTrackColor: Colors.white10,
          ),
        ],
      ),
    );
  }

  Widget _navItem({
    required String title,
    required String count,
    required IconData icon,
    VoidCallback? onTap,
    bool showChevron = true,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: Colors.white.withValues(alpha: 0.4), size: 22),
      title: Text(
        title,
        style: const TextStyle(
            color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            count,
            style: TextStyle(
              color: title == 'Membership Fees'
                  ? const Color(0xFF00E5FF)
                  : Colors.white.withValues(alpha: 0.4),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (showChevron && onTap != null) ...[
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.2)),
          ],
        ],
      ),
    );
  }

  Widget _atmosphereCard({
    required String label,
    required String name,
    required String subtitle,
    required IconData icon,
    Widget? preview,
    Color? accent,
    VoidCallback? onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF111115),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                Icon(icon, color: accent ?? const Color(0xFFFF7A45), size: 14),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (preview != null) ...[
                  preview,
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w800),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _roomModeCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111115),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'ROOM MODE',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
              Icon(
                _modePreset.icon,
                color: _modePreset.accent,
                size: 14,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _modePreset.label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            _modePreset.subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: roomModePresets
                  .map(
                    (preset) => _modeTab(
                      preset: preset,
                      isSelected: preset.type == _room.type,
                      onTap: _permissions.canManageRoomIdentity
                          ? () => _changeMode(preset.type)
                          : null,
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeTab({
    required RoomModePreset preset,
    required bool isSelected,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? preset.accent : const Color(0xFF111115),
          borderRadius: BorderRadius.circular(16),
          border: isSelected
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.05)),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: preset.accent.withValues(alpha: 0.32),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              preset.icon,
              size: 15,
              color: isSelected
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.4),
            ),
            const SizedBox(width: 8),
            Text(
              preset.label,
              style: TextStyle(
                color: isSelected
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.4),
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _backgroundThemeOption({
    required RoomBackgroundPreset preset,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF16171C),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? const Color(0xFFFF7A45)
                : Colors.white.withValues(alpha: 0.06),
            width: selected ? 1.4 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: const Color(0xFFFF7A45).withValues(alpha: 0.18),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            _buildBackgroundPreview(preset),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preset.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    preset.subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.48),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.chevron_right_rounded,
              color: selected ? const Color(0xFFFF7A45) : Colors.white30,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackgroundPreview(RoomBackgroundPreset preset) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 88,
        height: 56,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: preset.colors,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (preset.id == 'default') ...[
              Align(
                alignment: Alignment.center,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.07),
                  ),
                ),
              ),
              _previewSparkle(0.22, 0.30),
              _previewSparkle(0.72, 0.22),
              _previewSparkle(0.62, 0.68),
            ],
            if (preset.id == 'space') ...[
              Positioned.fill(
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        color: Colors.white.withValues(alpha: 0.04),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Container(
                        color: Colors.transparent,
                      ),
                    ),
                    Expanded(
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.08),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (preset.id == 'ocean') ...[
              Positioned(
                right: -10,
                top: -6,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
              ),
              Positioned(
                left: -8,
                bottom: -10,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: preset.colors.last.withValues(alpha: 0.16),
                  ),
                ),
              ),
            ],
            if (preset.id == 'galaxy') ...[
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.15),
                      radius: 0.9,
                      colors: [
                        Colors.white.withValues(alpha: 0.08),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              _previewSparkle(0.28, 0.24),
              _previewSparkle(0.78, 0.38),
              _previewSparkle(0.48, 0.66),
            ],
            if (preset.id == 'sunrise') ...[
              Positioned.fill(
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        color: Colors.white.withValues(alpha: 0.26),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        color: Colors.white.withValues(alpha: 0.08),
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

  Widget _previewSparkle(double leftFactor, double topFactor) {
    return Positioned.fill(
      child: Align(
        alignment: Alignment(leftFactor * 2 - 1, topFactor * 2 - 1),
        child: Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.65),
          ),
        ),
      ),
    );
  }

  Widget _buildBackgroundSwatch(
    RoomBackgroundPreset preset, {
    double size = 32,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: preset.colors,
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
    );
  }

  Future<void> _dissolveRoom() async {
    if (!_isHost) return;
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF111115),
        title:
            const Text('Dissolve Room', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will end the room for everyone currently inside. Continue?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF4B4B)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('End Room'),
          ),
        ],
      ),
    );
    if (shouldDelete != true) return;
    await _run(() async {
      try {
        final deleted = await RoomService.deleteRoom(_room.id);
        if (!mounted || !deleted) return;
        Navigator.pop(context);
      } catch (e) {
        _showError(e);
      }
    });
  }
}
