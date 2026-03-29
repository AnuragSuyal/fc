import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../utils/constants.dart';
import '../../widgets/user_avatar.dart';

class ColorClashSeatWidget extends StatelessWidget {
  const ColorClashSeatWidget({
    super.key,
    required this.name,
    required this.cardCount,
    required this.seatIndex,
    this.avatarUrl,
    this.isCurrentTurn = false,
    this.isFinalCard = false,
    this.isWinner = false,
    this.isDisconnected = false,
    this.isSpeaking = false,
    this.isMuted = false,
    this.hasShield = false,
    this.timeoutStrikes = 0,
    this.placement,
    this.isLocalSeat = false,
    this.onTap,
  });

  final String name;
  final int cardCount;
  final int seatIndex;
  final String? avatarUrl;
  final bool isCurrentTurn;
  final bool isFinalCard;
  final bool isWinner;
  final bool isDisconnected;
  final bool isSpeaking;
  final bool isMuted;
  final bool hasShield;
  final int timeoutStrikes;
  final int? placement;
  final bool isLocalSeat;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final borderTone = isWinner
        ? AppColors.warningOrange
        : isCurrentTurn
            ? AppColors.primaryBlue
            : isFinalCard
                ? AppColors.errorRed
                : context.mood.outlineSoft;
    final speakingGlow =
        isSpeaking ? AppColors.successGreen : Colors.transparent;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: isLocalSeat ? 1 : 0.96),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: borderTone,
              width: isCurrentTurn || isWinner ? 1.8 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: borderTone.withValues(
                  alpha: isCurrentTurn || isWinner ? 0.16 : 0.06,
                ),
                blurRadius: 16,
                offset: const Offset(0, 10),
              ),
              if (isSpeaking)
                BoxShadow(
                  color: speakingGlow.withValues(alpha: 0.18),
                  blurRadius: 22,
                  spreadRadius: 1.5,
                ),
            ],
          ),
          child: Row(
            children: [
              Stack(
                children: [
                  UserAvatar(
                    imageUrl: avatarUrl,
                    username: name,
                    radius: 22,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: isDisconnected
                            ? AppColors.errorRed
                            : AppColors.successGreen,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            isLocalSeat ? '$name (You)' : name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (placement != null)
                          _SeatBadge(
                            label: '#$placement',
                            tone: AppColors.warningOrange,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _SeatBadge(label: 'Seat ${seatIndex + 1}'),
                        _SeatBadge(label: '$cardCount cards'),
                        if (hasShield)
                          const _SeatBadge(
                            label: 'Shield',
                            tone: AppColors.successGreen,
                          ),
                        if (isSpeaking)
                          const _SeatBadge(
                            label: 'Speaking',
                            tone: AppColors.successGreen,
                          ),
                        if (isMuted)
                          const _SeatBadge(
                            label: 'Muted',
                            tone: AppColors.textSecondary,
                          ),
                        if (isFinalCard)
                          const _SeatBadge(
                            label: 'Last card',
                            tone: AppColors.errorRed,
                          ),
                        if (isCurrentTurn)
                          const _SeatBadge(
                            label: 'On turn',
                            tone: AppColors.primaryBlue,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: (isSpeaking
                              ? AppColors.successGreen
                              : AppColors.primaryBlue)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isMuted ? Icons.mic_off_rounded : Icons.mic_none_rounded,
                      size: 18,
                      color: (isSpeaking
                              ? AppColors.successGreen
                              : AppColors.primaryBlue)
                          .withValues(alpha: 0.88),
                    ),
                  ),
                  if (timeoutStrikes > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${timeoutStrikes}x',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppColors.errorRed,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeatBadge extends StatelessWidget {
  const _SeatBadge({
    required this.label,
    this.tone = AppColors.accentBerry,
  });

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: tone,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
