import 'package:flutter/material.dart';

import '../../models/room_model.dart';
import '../../utils/constants.dart';
import '../user_avatar.dart';

class RoomInfoBottomSheet extends StatefulWidget {
  final RoomModel room;
  final bool isJoined;
  final bool isFollowing;
  final bool showFollowButton;
  final VoidCallback onShare;
  final VoidCallback onPrimaryAction;
  final Future<void> Function()? onFollowToggle;
  final VoidCallback? onViewAll;

  const RoomInfoBottomSheet({
    super.key,
    required this.room,
    required this.isJoined,
    required this.isFollowing,
    this.showFollowButton = true,
    required this.onShare,
    required this.onPrimaryAction,
    this.onFollowToggle,
    this.onViewAll,
  });

  @override
  State<RoomInfoBottomSheet> createState() => _RoomInfoBottomSheetState();
}

class _RoomInfoBottomSheetState extends State<RoomInfoBottomSheet> {
  bool _isTogglingFollow = false;

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final vipMembers = room.participants
        .where(
          (participant) =>
              participant.role == 'host' ||
              participant.role == 'cohost' ||
              participant.role == 'moderator',
        )
        .toList();

    final displayMembers = [...vipMembers];
    if (displayMembers.length < 4) {
      final others = room.participants
          .where(
            (participant) =>
                participant.role != 'host' &&
                participant.role != 'cohost' &&
                participant.role != 'moderator',
          )
          .take(4 - displayMembers.length);
      displayMembers.addAll(others);
    }

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF15141D),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildRoomArtwork(room),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          room.name,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF7A45)
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFFF7A45)
                                      .withValues(alpha: 0.3),
                                ),
                              ),
                              child: Text(
                                '${room.type.toUpperCase()} ROOM',
                                style: const TextStyle(
                                  color: Color(0xFFFF7A45),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Text(
                                'ID: ${room.roomId}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                    ),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.black87,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'ACTIVE MEMBERS',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                  GestureDetector(
                    onTap: widget.onViewAll,
                    behavior: HitTestBehavior.opaque,
                    child: Text(
                      'VIEW ALL',
                      style: TextStyle(
                        color: widget.onViewAll != null
                            ? const Color(0xFFFF7A45)
                            : Colors.white38,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (displayMembers.isNotEmpty)
                SizedBox(
                  height: 108,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: displayMembers.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 24),
                    itemBuilder: (context, index) {
                      final member = displayMembers[index];
                      return SizedBox(
                        width: 80,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _getRoleColor(member.role),
                                  width: 2,
                                ),
                              ),
                              child: UserAvatar(
                                username: member.username,
                                imageUrl: member.avatar,
                                radius: 26,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              member.username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (member.role == 'host' ||
                                member.role == 'cohost' ||
                                member.role == 'moderator') ...[
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _getRoleColor(member.role)
                                      .withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  member.role == 'host'
                                      ? 'OWNER'
                                      : member.role == 'cohost'
                                          ? 'MANAGER'
                                          : 'ADMIN',
                                  style: TextStyle(
                                    color: _getRoleColor(member.role),
                                    fontSize: 8,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      title: 'Online',
                      value: '${room.onlineCount}',
                      trailing: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF00D19B),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      title: 'Members',
                      value: '${room.participantCount}',
                      trailing: const Icon(
                        Icons.groups_rounded,
                        color: Color(0xFF52A1FF),
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildListRow(
                Icons.favorite_rounded,
                'Aura Points',
                '${room.exp}',
                const Color(0xFFFF7A45),
              ),
              _buildListRow(
                Icons.location_on_rounded,
                'Global Sync',
                room.region.isEmpty ? 'Unknown Region' : room.region,
                const Color(0xFF00D19B),
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(
                          Icons.campaign_rounded,
                          color: Color(0xFFFF7A45),
                          size: 16,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'CHANNEL NOTE',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      room.announcement.isEmpty
                          ? '"No notes are available for this channel yet."'
                          : '"${room.announcement}"',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.showFollowButton) ...[
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed:
                        _isTogglingFollow || widget.onFollowToggle == null
                            ? null
                            : _handleFollowToggle,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF7A45),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          const Color(0xFFFF7A45).withValues(alpha: 0.45),
                      disabledForegroundColor: Colors.white70,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: _isTogglingFollow
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            widget.isFollowing
                                ? 'Unfollow Room'
                                : 'Follow Room',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleFollowToggle() async {
    final onFollowToggle = widget.onFollowToggle;
    if (onFollowToggle == null || _isTogglingFollow) return;

    setState(() => _isTogglingFollow = true);
    try {
      await onFollowToggle();
    } finally {
      if (mounted) {
        setState(() => _isTogglingFollow = false);
      }
    }
  }

  Widget _buildRoomArtwork(RoomModel room) {
    final artworkUrl = _resolveRoomArtworkUrl(room);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        UserAvatar(
          username: room.name.isNotEmpty ? room.name : room.hostName,
          imageUrl: artworkUrl,
          radius: 36,
        ),
        if (room.onlineCount > 0)
          Positioned(
            bottom: -6,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF00D19B),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'LIVE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  String? _resolveRoomArtworkUrl(RoomModel room) {
    final coverImage = _normalizeRoomHeaderImage(room.coverImage);
    if (coverImage != null) {
      return coverImage;
    }

    return _resolveHostAvatarForHeader(room);
  }

  String? _resolveHostAvatarForHeader(RoomModel room) {
    for (final participant in room.participants) {
      if (participant.userId != room.hostId) {
        continue;
      }

      final avatar = participant.avatar.trim();
      if (avatar.isNotEmpty && avatar != 'null') {
        return avatar;
      }
    }

    final hostAvatar = room.hostAvatar.trim();
    if (hostAvatar.isNotEmpty && hostAvatar != 'null') {
      return hostAvatar;
    }

    return null;
  }

  String? _normalizeRoomHeaderImage(String? imageUrl) {
    final rawUrl = imageUrl?.trim();
    if (rawUrl == null || rawUrl.isEmpty || rawUrl == 'null') {
      return null;
    }

    final normalized = AppConfig.normalizeBackendUrl(rawUrl);
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasAuthority) {
      return null;
    }

    return normalized;
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required Widget trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              trailing,
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListRow(
    IconData icon,
    String label,
    String value,
    Color iconColor,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Color _getRoleColor(String role) {
    switch (role) {
      case 'host':
        return const Color(0xFFFF7A45);
      case 'cohost':
      case 'moderator':
        return const Color(0xFF00D19B);
      default:
        return Colors.transparent;
    }
  }
}
