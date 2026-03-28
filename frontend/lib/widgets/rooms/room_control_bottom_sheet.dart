import 'package:flutter/material.dart';
import '../../models/room_model.dart';

class RoomControlBottomSheet extends StatelessWidget {
  final RoomModel room;
  final bool canOpenRoomSettings;
  final bool canChangeRoomMode;
  final bool canEditAnnouncement;
  final VoidCallback onExit;
  final VoidCallback onSettings;
  final VoidCallback onInvite;
  final VoidCallback onGiftSound;
  final VoidCallback onRallyFans;
  final VoidCallback onShare;
  final VoidCallback onReport;
  final VoidCallback onAnnouncement;
  final VoidCallback onVideoSetup;
  final VoidCallback onMusicSetup;
  final Function(String) onModeChanged;

  const RoomControlBottomSheet({
    super.key,
    required this.room,
    required this.canOpenRoomSettings,
    required this.canChangeRoomMode,
    required this.canEditAnnouncement,
    required this.onExit,
    required this.onSettings,
    required this.onInvite,
    required this.onGiftSound,
    required this.onRallyFans,
    required this.onShare,
    required this.onReport,
    required this.onAnnouncement,
    required this.onVideoSetup,
    required this.onMusicSetup,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: 32),
      decoration: const BoxDecoration(
        color: Color(0xFF0B0B0B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'VIBE SELECTION',
                    style: TextStyle(
                      color: const Color(0xFFFF7A45),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const Text(
                    'Transform the space',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildVibeSelection(),
            ),
            const SizedBox(height: 32),
            _buildConnectSection(),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildBottomActions(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVibeSelection() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: _buildPrimaryVibe(
            label: 'Lounge',
            icon: Icons.auto_awesome_rounded,
            color: const Color(0xFFFF7A45),
            isActive: room.type == 'voice',
            isEnabled: canChangeRoomMode,
            onTap: () => _handleModeChange('voice'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 5,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildSecondaryVibe(
                      label: 'Social',
                      icon: Icons.diversity_3_rounded,
                      color: const Color(0xFFFF528D),
                      isActive: room.type == 'chat',
                      isEnabled: canChangeRoomMode,
                      onTap: () => _handleModeChange('chat'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSecondaryVibe(
                      label: 'Trade',
                      icon: Icons.widgets_rounded,
                      color: const Color(0xFF8C52FF),
                      isActive: room.type == 'auction',
                      isEnabled: canChangeRoomMode,
                      onTap: () => _handleModeChange('auction'),
                      isLive: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildSecondaryVibe(
                      label: 'Stream',
                      icon: Icons.wifi_tethering_rounded,
                      color: const Color(0xFF52A1FF),
                      isActive: room.type == 'video',
                      isEnabled: canChangeRoomMode,
                      onTap: () => _handleModeChange('video'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSecondaryVibe(
                      label: 'Arena',
                      icon: Icons.sports_esports_rounded,
                      color: const Color(0xFF00D19B),
                      isActive: room.type == 'game',
                      isEnabled: canChangeRoomMode,
                      onTap: () => _handleModeChange('game'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _handleModeChange(String type) {
    if (!canChangeRoomMode) return;
    onModeChanged(type);
  }

  Widget _buildPrimaryVibe({
    required String label,
    required IconData icon,
    required Color color,
    required bool isActive,
    required bool isEnabled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: isEnabled ? onTap : null,
      child: Container(
        height:
            184, // Approximate height for the primary box to match 2 side boxes
        decoration: BoxDecoration(
          color: isActive
              ? color.withValues(alpha: 0.1)
              : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isActive ? color : Colors.white10,
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: isEnabled ? color : Colors.white.withValues(alpha: 0.14),
                shape: BoxShape.circle,
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.5),
                          blurRadius: 20,
                          spreadRadius: 2,
                        )
                      ]
                    : [],
              ),
              child: Icon(icon, color: Colors.white, size: 32),
            ),
            const SizedBox(height: 16),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (isActive) ...[
              const SizedBox(height: 4),
              Text(
                'PRIMARY',
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSecondaryVibe({
    required String label,
    required IconData icon,
    required Color color,
    required bool isActive,
    required bool isEnabled,
    required VoidCallback onTap,
    bool isLive = false,
  }) {
    return GestureDetector(
      onTap: isEnabled ? onTap : null,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 86,
            decoration: BoxDecoration(
              color: isActive
                  ? color.withValues(alpha: 0.1)
                  : Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isActive ? color : Colors.white10,
                width: isActive ? 1.5 : 1,
              ),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    color:
                        isEnabled ? color : Colors.white.withValues(alpha: 0.4),
                    size: 28,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isLive)
            Positioned(
              top: -8,
              right: -8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF7A45),
                  borderRadius: BorderRadius.circular(8),
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
        ],
      ),
    );
  }

  Widget _buildConnectSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                    height: 1, color: Colors.white.withValues(alpha: 0.1)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'CONNECT',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              Expanded(
                child: Container(
                    height: 1, color: Colors.white.withValues(alpha: 0.1)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildConnectAction(
                    'Rally', Icons.campaign_rounded, onRallyFans),
                _buildConnectAction(
                    'Sounds', Icons.music_note_rounded, onGiftSound),
                _buildConnectAction(
                    'Invite', Icons.person_add_alt_1_rounded, onInvite),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectAction(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: Colors.white70, size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActions() {
    return Row(
      children: [
        if (canOpenRoomSettings) ...[
          Expanded(
            child: GestureDetector(
              onTap: onSettings,
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.settings_rounded, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Room Settings',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: GestureDetector(
            onTap: onReport,
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.shield_outlined, color: Colors.white70, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Report',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: onExit,
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              shape: BoxShape.circle,
              border: Border.all(
                  color: const Color(0xFFFF4949).withValues(alpha: 0.3)),
            ),
            child: const Icon(
              Icons.power_settings_new_rounded,
              color: Color(0xFFFF4949),
              size: 24,
            ),
          ),
        ),
      ],
    );
  }
}
