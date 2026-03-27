import 'package:flutter/material.dart';
import '../../models/room_model.dart';
import '../user_avatar.dart';
import '../../services/room_service.dart';

class UserProfileBottomSheet extends StatelessWidget {
  final Participant participant;
  final RoomModel room;
  final bool isMe;
  final bool canModerate;
  final bool isHost;
  final bool canManageRoles;
  final bool canManageSpeakerState;
  final bool canSendGifts;
  final VoidCallback onViewProfile;
  final VoidCallback onSendGift;
  final VoidCallback onLeaveSeat;
  final VoidCallback onRefreshRoom;

  const UserProfileBottomSheet({
    super.key,
    required this.participant,
    required this.room,
    required this.isMe,
    required this.canModerate,
    required this.isHost,
    required this.canManageRoles,
    required this.canManageSpeakerState,
    required this.canSendGifts,
    required this.onViewProfile,
    required this.onSendGift,
    required this.onLeaveSeat,
    required this.onRefreshRoom,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: 24),
      decoration: const BoxDecoration(
        color: Color(0xFF111115),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 48,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.more_vert_rounded,
                            color: Colors.white54),
                        onPressed: (canModerate ||
                                canManageRoles ||
                                canManageSpeakerState)
                            ? () {
                                _showModerationMenu(context);
                              }
                            : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.share_outlined,
                            color: Colors.white54),
                        onPressed: () {},
                      ),
                    ],
                  ),
                ),
              ),
              _buildAvatarSection(),
              const SizedBox(height: 16),
              Text(
                participant.username,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'ID: ${participant.userId.length > 8 ? participant.userId.substring(0, 8) : participant.userId}',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (participant.vipLevel > 0)
                    _buildPill('TOP DONOR', Colors.white24),
                  if (participant.role == 'host') ...[
                    if (participant.vipLevel > 0) const SizedBox(width: 8),
                    _buildPill('VERIFIED ARTIST',
                        const Color(0xFFFF528D).withValues(alpha: 0.2),
                        textColor: const Color(0xFFFF528D)),
                  ],
                ],
              ),
              const SizedBox(height: 32),
              _buildStatsRow(),
              const SizedBox(height: 32),
              _buildHonorMedals(),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    _buildInfoRow('Region', 'United States Virgin Islands'),
                    const SizedBox(height: 16),
                    _buildInfoRow(
                        'Announcement', 'No one loves me like I do. ✨'),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.card_giftcard_rounded,
                            color: Color(0xFFFFB347)),
                        onPressed: canSendGifts ? onSendGift : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onViewProfile,
                        icon: const Icon(Icons.chat_bubble_rounded,
                            color: Colors.white),
                        label: const Text('Chat',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Colors.white.withValues(alpha: 0.05),
                          side: const BorderSide(color: Colors.white10),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: isMe ? onLeaveSeat : () {},
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              isMe ? Colors.redAccent : const Color(0xFFFF528D),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24)),
                        ),
                        child: Text(
                          isMe ? 'Leave Seat' : 'Follow',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarSection() {
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 110,
          height: 110,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFFFF7A45), Color(0xFFFFCC00)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Center(
            child: Container(
              width: 104,
              height: 104,
              decoration: const BoxDecoration(
                color: Color(0xFF1A1A1A),
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: UserAvatar(
                  username: participant.username,
                  imageUrl: participant.avatar,
                  radius: 50,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -10,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF52A1FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF111115), width: 2),
            ),
            child: Text(
              'Lv.${participant.level}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPill(String text, Color bgColor,
      {Color textColor = Colors.white54}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: textColor.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildStatColumn('12.4K', 'Fans'),
          Container(width: 1, height: 30, color: Colors.white10),
          _buildStatColumn('482', 'Following'),
          Container(width: 1, height: 30, color: Colors.white10),
          _buildStatColumn('88', 'Medals'),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildHonorMedals() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Honor Medals',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Text(
                'View All',
                style: TextStyle(
                  color: Color(0xFFFF528D),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMedalItem('🏆', 'Champion', const Color(0xFF5D2E8C)),
              _buildMedalItem('🔥', 'Active', const Color(0xFF8C522E)),
              _buildMedalItem('💎', 'Gems', const Color(0xFF2E5B8C)),
              _buildMedalItem('🍀', 'Lucky', const Color(0xFF2E8C4A)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMedalItem(String emoji, String label, Color bgColor) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: bgColor.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: bgColor),
          ),
          child: Center(
            child: Text(emoji, style: const TextStyle(fontSize: 28)),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 14,
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  void _showModerationMenu(BuildContext context) {
    if (!canModerate && !canManageRoles && !canManageSpeakerState) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canModerate)
              ListTile(
                leading: Icon(participant.isMuted ? Icons.mic : Icons.mic_off,
                    color: Colors.orange),
                title: Text(participant.isMuted ? 'Unmute User' : 'Mute User',
                    style: const TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    await RoomService.muteParticipant(
                        room.id, participant.userId,
                        muted: !participant.isMuted);
                    onRefreshRoom();
                  } catch (e) {
                    debugPrint('Failed to update mute state: $e');
                  }
                },
              ),
            if (canManageSpeakerState)
              ListTile(
                leading: Icon(
                    participant.seatIndex >= 0
                        ? Icons.arrow_downward
                        : Icons.arrow_upward,
                    color: Colors.purpleAccent),
                title: Text(
                    participant.seatIndex >= 0
                        ? 'Move To Audience'
                        : 'Approve Mic Request',
                    style: const TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    if (participant.seatIndex >= 0) {
                      await RoomService.demoteParticipant(
                          room.id, participant.userId);
                    } else {
                      await RoomService.promoteParticipant(
                          room.id, participant.userId);
                    }
                    onRefreshRoom();
                  } catch (e) {
                    debugPrint('Failed to update speaker state: $e');
                  }
                },
              ),
            if (isHost && canManageRoles)
              ListTile(
                leading: Icon(
                    participant.role == 'cohost'
                        ? Icons.person_remove
                        : Icons.person_add,
                    color: Colors.cyanAccent),
                title: Text(
                    participant.role == 'cohost'
                        ? 'Remove Co-host'
                        : 'Make Co-host',
                    style: const TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    if (participant.role == 'cohost') {
                      await RoomService.removeCoHost(
                          room.id, participant.userId);
                    } else {
                      await RoomService.assignCoHost(
                          room.id, participant.userId);
                    }
                    onRefreshRoom();
                  } catch (e) {
                    debugPrint('Failed to update co-host role: $e');
                  }
                },
              ),
            if (canModerate)
              ListTile(
                leading: const Icon(Icons.person_off, color: Colors.redAccent),
                title: const Text('Kick From Room',
                    style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    await RoomService.kickParticipant(
                        room.id, participant.userId);
                    onRefreshRoom();
                  } catch (e) {
                    debugPrint('Failed to kick participant: $e');
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}
