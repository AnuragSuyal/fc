import 'package:flutter/material.dart';

import '../models/room_model.dart';
import '../screens/rooms/room_detail_screen.dart';
import '../theme/app_theme.dart';
import '../utils/constants.dart';
import 'currency_icon.dart';
import 'user_avatar.dart';

class RoomCard extends StatelessWidget {
  final RoomModel room;
  final VoidCallback? onJoin;

  const RoomCard({
    super.key,
    required this.room,
    this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mood = context.mood;
    final typeColor = _getTypeColor(room.type);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => RoomDetailScreen(room: room),
            ),
          );
        },
        borderRadius: BorderRadius.circular(30),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white,
                mood.surfaceSoft,
              ],
            ),
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildRoomCover(typeColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          room.name,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            UserAvatar(
                              username: room.hostName,
                              radius: 10,
                              fontSize: 10,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              room.hostName,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'UID ${room.roomId}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (room.isPrivate)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accentYellow.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.lock_rounded,
                            size: 12,
                            color: AppColors.textPrimary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Private',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 12),

              if (room.description.isNotEmpty) ...[
                Text(
                  room.description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
              ],

              if (room.tags.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: room.tags.map((tag) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: mood.outlineSoft),
                      ),
                      child: Text(
                        '#$tag',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
              ],

              // Stats row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.successGreen.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.successGreen,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${room.onlineCount} online',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: AppColors.successGreen,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accentSky.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: 14,
                          color: AppColors.textPrimary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${room.participantCount}/${room.maxParticipants}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (room.entryFee > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accentYellow.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        children: [
                          const CurrencyIcon.coins(size: 14),
                          const SizedBox(width: 4),
                          Text(
                            '${room.entryFee}',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: AppColors.warningOrange,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(width: 8),
                  if (room.hdVoice)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accentBerry.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.audio_file,
                            size: 14,
                            color: AppColors.accentBerry,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'HD',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: AppColors.accentBerry,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoomCover(Color typeColor) {
    final coverImage = _normalizeImageUrl(room.coverImage);

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            typeColor.withValues(alpha: 0.2),
            typeColor.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: ColoredBox(
            color: Colors.white.withValues(alpha: 0.9),
            child: Builder(
              builder: (context) {
                if (coverImage != null) {
                  return Image.network(
                    coverImage,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _buildInitialCover(typeColor),
                  );
                }
                return _buildInitialCover(typeColor);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInitialCover(Color typeColor) {
    final label = room.hostName.trim().isNotEmpty
        ? room.hostName.trim()
        : room.name.trim();
    final initial = label.isEmpty ? 'R' : label[0].toUpperCase();

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            typeColor.withValues(alpha: 0.16),
            typeColor.withValues(alpha: 0.06),
          ],
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }

  String? _normalizeImageUrl(String? value) {
    final rawValue = value?.trim();
    if (rawValue == null ||
        rawValue.isEmpty ||
        rawValue.toLowerCase() == 'null') {
      return null;
    }

    if (rawValue.startsWith('http://') || rawValue.startsWith('https://')) {
      return AppConfig.normalizeBackendUrl(rawValue);
    }

    final normalizedPath = rawValue.startsWith('/') ? rawValue : '/$rawValue';
    return '${AppConfig.socketUrl}$normalizedPath';
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'voice':
        return AppColors.primaryBlue;
      case 'music':
        return AppColors.accentBerry;
      case 'video':
        return AppColors.primaryBlue;
      case 'chat':
        return AppColors.secondaryBlue;
      case 'auction':
        return AppColors.warningOrange;
      default:
        return AppColors.textSecondary;
    }
  }
}
