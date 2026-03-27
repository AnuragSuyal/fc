import 'package:flutter/material.dart';

class RoomBackgroundPreset {
  final String id;
  final String label;
  final String subtitle;
  final List<Color> colors;

  const RoomBackgroundPreset({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.colors,
  });
}

class RoomModePreset {
  final String type;
  final String label;
  final String subtitle;
  final IconData icon;
  final Color accent;

  const RoomModePreset({
    required this.type,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.accent,
  });
}

const roomBackgroundPresets = <RoomBackgroundPreset>[
  RoomBackgroundPreset(
    id: 'default',
    label: 'Velvet Night',
    subtitle: 'Dark luxe glow',
    colors: [
      Color(0xFF050608),
      Color(0xFF111317),
      Color(0xFF2C3138),
    ],
  ),
  RoomBackgroundPreset(
    id: 'space',
    label: 'Abyss Blue',
    subtitle: 'Deep studio teal',
    colors: [
      Color(0xFF051521),
      Color(0xFF0B2B3B),
      Color(0xFF123E55),
    ],
  ),
  RoomBackgroundPreset(
    id: 'ocean',
    label: 'Amethyst Drift',
    subtitle: 'Purple lounge glow',
    colors: [
      Color(0xFF17081F),
      Color(0xFF321253),
      Color(0xFF5B2B85),
    ],
  ),
  RoomBackgroundPreset(
    id: 'galaxy',
    label: 'Midnight Ink',
    subtitle: 'Ultra dark navy',
    colors: [
      Color(0xFF010418),
      Color(0xFF040B2C),
      Color(0xFF0A1848),
    ],
  ),
  RoomBackgroundPreset(
    id: 'sunrise',
    label: 'Silver Mist',
    subtitle: 'Soft steel light',
    colors: [
      Color(0xFF97A6B4),
      Color(0xFFBAC7D2),
      Color(0xFFD7E0E8),
    ],
  ),
];

const roomModePresets = <RoomModePreset>[
  RoomModePreset(
    type: 'voice',
    label: 'Normal',
    subtitle: 'Free interaction for all guests',
    icon: Icons.graphic_eq_rounded,
    accent: Color(0xFF52A1FF),
  ),
  RoomModePreset(
    type: 'chat',
    label: 'Acquaint',
    subtitle: 'Text-first social room',
    icon: Icons.forum_rounded,
    accent: Color(0xFFFF528D),
  ),
  RoomModePreset(
    type: 'auction',
    label: 'Auction',
    subtitle: 'Live bidding flow',
    icon: Icons.gavel_rounded,
    accent: Color(0xFF8C52FF),
  ),
  RoomModePreset(
    type: 'video',
    label: 'Stream',
    subtitle: 'Video-led room mode',
    icon: Icons.live_tv_rounded,
    accent: Color(0xFF31C8F5),
  ),
  RoomModePreset(
    type: 'game',
    label: 'Arena',
    subtitle: 'Games and party prompts',
    icon: Icons.sports_esports_rounded,
    accent: Color(0xFF00D19B),
  ),
  RoomModePreset(
    type: 'music',
    label: 'Music',
    subtitle: 'Shared listening mode',
    icon: Icons.music_note_rounded,
    accent: Color(0xFFFFB703),
  ),
];

RoomBackgroundPreset roomBackgroundPresetFor(String background) {
  final normalized = background.trim().toLowerCase();
  const aliases = <String, String>{
    '': 'default',
    'velvet': 'default',
    'velvet_night': 'default',
    'midnight': 'galaxy',
    'rainbow': 'sunrise',
    'castle': 'default',
    'christmas': 'space',
    'halloween': 'default',
    'fire': 'default',
    'clouds': 'sunrise',
    'universe': 'galaxy',
    'racetrack': 'default',
    'cinema': 'default',
    'pulse': 'ocean',
    'arcade': 'space',
  };

  final resolved = aliases[normalized] ?? normalized;
  return roomBackgroundPresets.firstWhere(
    (preset) => preset.id == resolved,
    orElse: () => roomBackgroundPresets.first,
  );
}

RoomModePreset roomModePresetFor(String type) {
  final normalized = type.trim().toLowerCase();
  return roomModePresets.firstWhere(
    (preset) => preset.type == normalized,
    orElse: () => roomModePresets.first,
  );
}
