import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/group_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/friend_service.dart';
import '../../services/group_service.dart';
import '../../services/notification_sound_service.dart';
import '../../services/room_service.dart';
import '../../services/socket_service.dart';
import '../../services/upload_service.dart';
import '../../utils/constants.dart';
import '../../utils/media_url.dart';
import '../../widgets/user_avatar.dart';
import '../rooms/room_detail_screen.dart';

class GroupsScreen extends StatefulWidget {
  final bool embedded;

  const GroupsScreen({
    super.key,
    this.embedded = false,
  });

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  final List<StreamSubscription> _subs = [];
  final Map<String, int> _activityCounts = <String, int>{};

  List<GroupModel> _myGroups = [];
  List<GroupModel> _invites = [];
  List<GroupModel> _discoverGroups = [];
  List<GroupModel> _leaderboard = [];

  bool _isLoading = true;
  String? _error;
  Timer? _refreshDebounce;

  @override
  void initState() {
    super.initState();
    _loadData();
    _bindRealtime();
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final results = await Future.wait<dynamic>([
        GroupService.getMyGroups(),
        GroupService.getMyInvites(),
        GroupService.getDiscoverGroups(),
        GroupService.getLeaderboard(),
      ]);

      if (!mounted) return;
      setState(() {
        _myGroups = results[0] as List<GroupModel>;
        _invites = results[1] as List<GroupModel>;
        _discoverGroups = results[2] as List<GroupModel>;
        _leaderboard = results[3] as List<GroupModel>;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _bindRealtime() {
    _subs.add(SocketService.groupMessageStream.listen(_handleGroupMessage));
    _subs.add(SocketService.groupUpdateStream.listen(_handleGroupUpdate));
    _subs.add(SocketService.resyncStream.listen((_) => _scheduleRefresh()));
  }

  void _handleGroupMessage(Map<String, dynamic> event) {
    final groupId = event['groupId']?.toString();
    if (groupId == null || groupId.isEmpty) return;

    final index = _myGroups.indexWhere((group) => group.id == groupId);
    if (index == -1) return;

    final reordered = [..._myGroups];
    final group = reordered.removeAt(index);
    reordered.insert(0, group);

    if (!mounted) return;
    setState(() {
      _myGroups = reordered;
      _activityCounts[groupId] = (_activityCounts[groupId] ?? 0) + 1;
    });
  }

  void _handleGroupUpdate(Map<String, dynamic> event) {
    final action = event['action']?.toString() ?? '';
    final actorId = event['actorId']?.toString();
    final currentUserId = context.read<AuthProvider>().user?.id;

    if ((action == 'invited' || action == 'join_request_approved') &&
        actorId != null &&
        actorId != currentUserId) {
      unawaited(NotificationSoundService.playFriendRequest());
    } else if (action == 'member_joined' ||
        action == 'member_removed' ||
        action == 'role_updated' ||
        action == 'group_updated') {
      unawaited(NotificationSoundService.playFriendUpdate());
    }

    _scheduleRefresh();
  }

  void _scheduleRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(
      const Duration(milliseconds: 350),
      () => _loadData(silent: true),
    );
  }

  Future<void> _openGroup(GroupModel group) async {
    _activityCounts.remove(group.id);
    await Navigator.pushNamed(
      context,
      '/groups/detail',
      arguments: group.id,
    );
    if (!mounted) return;
    _scheduleRefresh();
  }

  Future<void> _openVoiceLounge(GroupModel group) async {
    final roomId = group.linkedVoiceRoom?.id;
    if (roomId == null || roomId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voice lounge is not ready yet.')),
      );
      return;
    }

    final room = await RoomService.getRoomById(roomId);
    if (!mounted) return;
    if (room == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the voice lounge.')),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RoomDetailScreen(room: room)),
    );
    if (!mounted) return;
    _scheduleRefresh();
  }

  Future<void> _acceptInvite(GroupModel group) async {
    try {
      await GroupService.acceptInvite(group.id);
      if (!mounted) return;
      await _loadData(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('You joined ${group.name}'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _rejectInvite(GroupModel group) async {
    final success = await GroupService.rejectInvite(group.id);
    if (!mounted || !success) return;
    await _loadData(silent: true);
  }

  Future<void> _joinGroup(GroupModel group) async {
    try {
      final response = await GroupService.joinGroup(group.id);
      if (!mounted) return;
      await _loadData(silent: true);
      if (!mounted) return;
      final requested = response['pendingApproval'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            requested
                ? 'Request sent to ${group.name}'
                : 'Joined ${group.name}',
          ),
          backgroundColor:
              requested ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _showCreateGroupSheet() async {
    final friendsPayload = await FriendService.getFriends();
    if (!mounted) return;

    final friends = <Map<String, dynamic>>[
      ...((friendsPayload['online'] as List?) ?? const []),
      ...((friendsPayload['offline'] as List?) ?? const []),
    ].whereType<Map>().map((user) => Map<String, dynamic>.from(user)).toList();

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CreateGroupSheet(friends: friends),
    );

    if (result == null || !mounted) return;

    try {
      final created = await GroupService.createGroup(
        name: result['name']?.toString() ?? '',
        description: result['description']?.toString(),
        motto: result['motto']?.toString(),
        avatar: result['avatar']?.toString(),
        isPublic: result['isPublic'] == true,
        approvalRequired: result['approvalRequired'] == true,
        maxMembers: (result['maxMembers'] as num?)?.toInt() ?? 20,
        type: result['type']?.toString() ?? 'small',
        vibe: result['vibe']?.toString() ?? 'Orbit',
        invitedFriendIds: (result['invitedFriendIds'] as List? ?? const [])
            .map((item) => item.toString())
            .toList(growable: false),
      );

      if (!mounted || created == null) return;
      await _loadData(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Created ${created.name}'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = RefreshIndicator(
      color: AppColors.primaryBlue,
      onRefresh: _loadData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          18,
          widget.embedded ? 18 : 16,
          18,
          widget.embedded ? 120 : 28,
        ),
        children: [
          _buildHero(),
          if (_error != null) ...[
            const SizedBox(height: 14),
            _buildErrorCard(),
          ],
          const SizedBox(height: 18),
          if (_invites.isNotEmpty) ...[
            _buildSectionTitle(
                'Invites waiting', '${_invites.length} circle invitations'),
            const SizedBox(height: 10),
            ..._invites.map(
              (group) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildInviteCard(group),
              ),
            ),
            const SizedBox(height: 8),
          ],
          _buildSectionTitle(
            'Your circles',
            _myGroups.isEmpty
                ? 'Build one with your people'
                : '${_myGroups.length} live circle${_myGroups.length == 1 ? '' : 's'}',
          ),
          const SizedBox(height: 10),
          if (_isLoading && _myGroups.isEmpty)
            const Center(
                child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: CircularProgressIndicator(),
            ))
          else if (_myGroups.isEmpty)
            _buildEmptyCard(
              title: 'No circles yet',
              subtitle:
                  'Create a private crew for chat, gifting, voice hangouts, and owner-led admin control.',
              actionLabel: 'Create circle',
              onPressed: _showCreateGroupSheet,
            )
          else
            ..._myGroups.map(
              (group) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _buildMyGroupCard(group),
              ),
            ),
          const SizedBox(height: 8),
          _buildSectionTitle(
            'Discover',
            _discoverGroups.isEmpty
                ? 'No new public circles right now'
                : 'Fresh public circles to join',
          ),
          const SizedBox(height: 10),
          if (_discoverGroups.isEmpty)
            _buildMiniCard(
                'Public circles will appear here when new crews open up.')
          else
            ..._discoverGroups.take(8).map(
                  (group) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildDiscoverTile(group),
                  ),
                ),
          const SizedBox(height: 8),
          _buildSectionTitle('Leaderboard', 'Top crews by energy and XP'),
          const SizedBox(height: 10),
          if (_leaderboard.isEmpty)
            _buildMiniCard('Leaderboard data is warming up.')
          else
            ..._leaderboard.take(5).toList().asMap().entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildLeaderboardTile(entry.key + 1, entry.value),
                  ),
                ),
        ],
      ),
    );

    if (widget.embedded) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Groups'),
      ),
      body: body,
    );
  }

  Widget _buildHero() {
    final liveLounges =
        _myGroups.where((group) => group.linkedVoiceRoom != null).length;
    final onlineMembers = _myGroups.fold<int>(
      0,
      (sum, group) => sum + group.onlineMembers,
    );

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0F172A),
            Color(0xFF1D4ED8),
            Color(0xFF14B8A6),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1D4ED8).withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Orbit Groups',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Build fun crews with owner powers, appointed admins, live voice lounges, gifts, and fast group chat.',
                      style: TextStyle(
                        color: Color(0xFFE2E8F0),
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _showCreateGroupSheet,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF0F172A),
                ),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Create'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildHeroChip(
                  Icons.groups_2_rounded, '${_myGroups.length}', 'Circles'),
              _buildHeroChip(Icons.mark_email_unread_rounded,
                  '${_invites.length}', 'Invites'),
              _buildHeroChip(
                  Icons.graphic_eq_rounded, '$liveLounges', 'Lounges'),
              _buildHeroChip(Icons.circle_rounded, '$onlineMembers', 'Online'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroChip(IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Text(
            '$value $label',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w900,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _buildInviteCard(GroupModel group) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(
                imageUrl: resolveMediaUrl(group.avatar),
                username: group.name,
                radius: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Invited by ${group.leaderName}',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Text(
                '${group.memberCount} members',
                style: const TextStyle(
                  color: Color(0xFFB45309),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            group.motto.isNotEmpty ? group.motto : group.description,
            style: const TextStyle(color: Color(0xFF92400E), height: 1.4),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _rejectInvite(group),
                  child: const Text('Later'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => _acceptInvite(group),
                  child: const Text('Join now'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMyGroupCard(GroupModel group) {
    final liveCount = _activityCounts[group.id] ?? 0;

    return InkWell(
      borderRadius: BorderRadius.circular(26),
      onTap: () => _openGroup(group),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.05),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                UserAvatar(
                  imageUrl: resolveMediaUrl(group.avatar),
                  username: group.name,
                  radius: 26,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${group.viewerRole.toUpperCase()}  •  ${group.onlineMembers} online now',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                if (liveCount > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$liveCount new',
                      style: const TextStyle(
                        color: Color(0xFF2563EB),
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              group.motto.isNotEmpty ? group.motto : group.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _smallPill('${group.memberCount}/${group.maxMembers} members'),
                _smallPill(group.vibe),
                if (group.hasTreasure) _smallPill('Treasure live'),
                if (group.linkedVoiceRoom != null) _smallPill('Voice lounge'),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: group.linkedVoiceRoom != null
                        ? () => _openVoiceLounge(group)
                        : null,
                    icon: const Icon(Icons.graphic_eq_rounded),
                    label: const Text('Voice'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _openGroup(group),
                    icon: const Icon(Icons.chat_bubble_rounded),
                    label: Text(group.hasTreasure ? 'Open' : 'Chat'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscoverTile(GroupModel group) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          UserAvatar(
            imageUrl: resolveMediaUrl(group.avatar),
            username: group.name,
            radius: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${group.memberCount} members • ${group.approvalRequired ? 'Approval on' : 'Open join'} • ${group.vibe}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: () => _joinGroup(group),
            child: Text(group.approvalRequired ? 'Request' : 'Join'),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaderboardTile(int rank, GroupModel group) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: rank == 1
                ? const Color(0xFFF59E0B)
                : rank == 2
                    ? const Color(0xFF94A3B8)
                    : rank == 3
                        ? const Color(0xFFC08457)
                        : const Color(0xFFE2E8F0),
            child: Text(
              '#$rank',
              style: TextStyle(
                color: rank <= 3 ? Colors.white : const Color(0xFF0F172A),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${group.stats['totalXp'] ?? 0} XP • ${group.memberCount} members',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _openGroup(group),
            child: const Text('Open'),
          ),
        ],
      ),
    );
  }

  Widget _smallPill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF475569),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildEmptyCard({
    required String title,
    required String subtitle,
    required String actionLabel,
    required VoidCallback onPressed,
  }) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.groups_2_rounded,
              color: Color(0xFF2563EB), size: 30),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 18,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: onPressed,
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniCard(String text) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        text,
        style: const TextStyle(color: AppColors.textSecondary, height: 1.45),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Text(
        _error ?? 'Something went wrong.',
        style: const TextStyle(
          color: Color(0xFFB91C1C),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CreateGroupSheet extends StatefulWidget {
  final List<Map<String, dynamic>> friends;

  const _CreateGroupSheet({
    required this.friends,
  });

  @override
  State<_CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<_CreateGroupSheet> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _mottoController = TextEditingController();
  final Set<String> _selectedFriends = <String>{};

  String? _avatarUrl;
  bool _isUploadingPhoto = false;
  bool _isPublic = false;
  bool _approvalRequired = false;
  int _maxMembers = 20;
  String _type = 'small';
  String _vibe = 'Orbit';

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _mottoController.dispose();
    super.dispose();
  }

  Future<void> _pickGroupPhoto() async {
    if (_isUploadingPhoto) return;

    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1440,
      maxHeight: 1440,
      imageQuality: 86,
    );
    if (picked == null || !mounted) return;

    setState(() => _isUploadingPhoto = true);
    try {
      final upload = await UploadService.uploadImage(picked);
      final url = upload['url']?.toString();
      if (url == null || url.isEmpty) {
        throw Exception('Group photo upload failed');
      }

      if (!mounted) return;
      setState(() => _avatarUrl = url);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Group photo added.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 18, 20, bottomInset + 20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 54,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Create Circle',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              const Text(
                'Invite friends now, keep owner control, and launch a live voice lounge automatically.',
                style: TextStyle(color: AppColors.textSecondary, height: 1.45),
              ),
              const SizedBox(height: 18),
              Center(
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: _pickGroupPhoto,
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          UserAvatar(
                            imageUrl: _avatarUrl,
                            username: _nameController.text.trim().isEmpty
                                ? 'Circle'
                                : _nameController.text.trim(),
                            radius: 34,
                          ),
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2563EB),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: _isUploadingPhoto
                                ? const Padding(
                                    padding: EdgeInsets.all(6),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor:
                                          AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Icon(
                                    Icons.add_a_photo_rounded,
                                    color: Colors.white,
                                    size: 15,
                                  ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: _isUploadingPhoto ? null : _pickGroupPhoto,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text(
                        _avatarUrl?.isNotEmpty == true
                            ? 'Change group photo'
                            : 'Add group photo',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _nameController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Circle name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _mottoController,
                decoration: const InputDecoration(labelText: 'Motto'),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                children: ['Orbit', 'Arcade', 'Midnight', 'Squad', 'Pulse']
                    .map(
                      (vibe) => ChoiceChip(
                        label: Text(vibe),
                        selected: _vibe == vibe,
                        onSelected: (_) => setState(() => _vibe = vibe),
                      ),
                    )
                    .toList(),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isPublic,
                onChanged: (value) => setState(() => _isPublic = value),
                title: const Text('Public circle'),
                subtitle: const Text('Let others discover and request to join'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _approvalRequired,
                onChanged: (value) => setState(() => _approvalRequired = value),
                title: const Text('Approval required'),
                subtitle: const Text('Owner and admins approve new members'),
              ),
              Wrap(
                spacing: 8,
                children: ['small', 'large', 'epic']
                    .map(
                      (type) => ChoiceChip(
                        label: Text(type.toUpperCase()),
                        selected: _type == type,
                        onSelected: (_) => setState(() => _type = type),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [12, 20, 35, 50]
                    .map(
                      (size) => ChoiceChip(
                        label: Text('$size max'),
                        selected: _maxMembers == size,
                        onSelected: (_) => setState(() => _maxMembers = size),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 18),
              const Text(
                'Add friends',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 8),
              ...widget.friends.take(12).map((friend) {
                final id = friend['_id']?.toString() ?? '';
                final selected = _selectedFriends.contains(id);
                return CheckboxListTile(
                  value: selected,
                  onChanged: (_) {
                    setState(() {
                      if (selected) {
                        _selectedFriends.remove(id);
                      } else {
                        _selectedFriends.add(id);
                      }
                    });
                  },
                  title: Text(friend['username']?.toString() ?? 'Friend'),
                  secondary: UserAvatar(
                    imageUrl: resolveMediaUrl(friend['avatar']?.toString()),
                    username: friend['username']?.toString() ?? 'F',
                    radius: 18,
                  ),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.trailing,
                );
              }),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isUploadingPhoto
                      ? null
                      : () {
                    final name = _nameController.text.trim();
                    if (name.isEmpty) return;
                    Navigator.pop(context, {
                      'name': name,
                      'description': _descriptionController.text.trim(),
                      'motto': _mottoController.text.trim(),
                      'avatar': _avatarUrl,
                      'isPublic': _isPublic,
                      'approvalRequired': _approvalRequired,
                      'maxMembers': _maxMembers,
                      'type': _type,
                      'vibe': _vibe,
                      'invitedFriendIds':
                          _selectedFriends.toList(growable: false),
                    });
                  },
                  child: const Text('Create circle'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
