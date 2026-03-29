import 'package:flutter/material.dart';

import '../../models/color_clash_card_model.dart';
import '../../models/color_clash_match_snapshot.dart';
import '../../utils/constants.dart';
import 'color_clash_visuals.dart';

class ColorClashBoardWidget extends StatelessWidget {
  const ColorClashBoardWidget({
    super.key,
    required this.discardTop,
    required this.drawPileCount,
    required this.discardCount,
    required this.currentHue,
    required this.direction,
    this.pendingEffect,
    this.lastActionSummary,
    this.roundResult,
    this.turnEndsAt,
    this.isSubmitting = false,
    this.isSpectator = false,
  });

  final ColorClashCardModel? discardTop;
  final int drawPileCount;
  final int discardCount;
  final String? currentHue;
  final int direction;
  final ColorClashPendingEffectModel? pendingEffect;
  final String? lastActionSummary;
  final ColorClashRoundResultModel? roundResult;
  final DateTime? turnEndsAt;
  final bool isSubmitting;
  final bool isSpectator;

  @override
  Widget build(BuildContext context) {
    final hueTone = colorClashHueColor(currentHue);
    final remaining =
        turnEndsAt?.difference(DateTime.now()).inSeconds.clamp(0, 999);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryBlue,
            hueTone.withValues(alpha: 0.82),
            AppColors.secondaryBlue,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.2),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _BoardPill(
                label: colorClashHueTitle(currentHue),
                icon: Icons.blur_circular_rounded,
              ),
              const SizedBox(width: 8),
              _BoardPill(
                label: direction >= 0 ? 'Clockwise' : 'Reverse',
                icon: direction >= 0 ? Icons.redo_rounded : Icons.undo_rounded,
              ),
              const Spacer(),
              if (remaining != null)
                _BoardPill(
                  label: '$remaining s',
                  icon: Icons.timer_outlined,
                  tone: remaining <= 5
                      ? AppColors.errorRed
                      : AppColors.warningOrange,
                ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _PileCard(
                  title: 'Draw',
                  subtitle: '$drawPileCount left',
                  icon: Icons.layers_rounded,
                  tone: AppColors.secondaryBlue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DiscardCard(
                  card: discardTop,
                  discardCount: discardCount,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (pendingEffect != null)
            _StateBanner(
              tone: AppColors.warningOrange,
              icon: Icons.bolt_rounded,
              text: pendingEffect!.summaryLabel,
            ),
          if ((lastActionSummary ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            _StateBanner(
              tone: Colors.white,
              icon: isSubmitting ? Icons.sync_rounded : Icons.auto_awesome,
              text: lastActionSummary!,
              darkText: true,
            ),
          ],
          if (roundResult != null) ...[
            const SizedBox(height: 12),
            _RoundResultBanner(
              result: roundResult!,
              isSpectator: isSpectator,
            ),
          ],
        ],
      ),
    );
  }
}

class _PileCard extends StatelessWidget {
  const _PileCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.tone,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        children: [
          Container(
            width: 62,
            height: 86,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.82),
                ),
          ),
        ],
      ),
    );
  }
}

class _DiscardCard extends StatelessWidget {
  const _DiscardCard({
    required this.card,
    required this.discardCount,
  });

  final ColorClashCardModel? card;
  final int discardCount;

  @override
  Widget build(BuildContext context) {
    final tone = colorClashCardTone(card);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        children: [
          Container(
            width: 62,
            height: 86,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border:
                  Border.all(color: tone.withValues(alpha: 0.5), width: 1.4),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (card?.isNumberCard == true)
                  Text(
                    '${card?.value ?? ''}',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: tone,
                          fontWeight: FontWeight.w900,
                        ),
                  )
                else
                  Icon(
                    colorClashCardIcon(card?.kind ?? ''),
                    color: tone,
                    size: 28,
                  ),
                const SizedBox(height: 6),
                Text(
                  card?.shortLabel ?? 'None',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: tone,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Discard',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            '$discardCount in stack',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.82),
                ),
          ),
        ],
      ),
    );
  }
}

class _BoardPill extends StatelessWidget {
  const _BoardPill({
    required this.label,
    required this.icon,
    this.tone = Colors.white,
  });

  final String label;
  final IconData icon;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color:
            Colors.white.withValues(alpha: tone == Colors.white ? 0.14 : 0.92),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: tone == Colors.white ? Colors.white : tone,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: tone == Colors.white ? Colors.white : tone,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _StateBanner extends StatelessWidget {
  const _StateBanner({
    required this.tone,
    required this.icon,
    required this.text,
    this.darkText = false,
  });

  final Color tone;
  final IconData icon;
  final String text;
  final bool darkText;

  @override
  Widget build(BuildContext context) {
    final textColor = darkText ? AppColors.textPrimary : Colors.white;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: darkText
            ? tone.withValues(alpha: 0.92)
            : tone.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, color: textColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundResultBanner extends StatelessWidget {
  const _RoundResultBanner({
    required this.result,
    required this.isSpectator,
  });

  final ColorClashRoundResultModel result;
  final bool isSpectator;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            result.endReason == 'completed'
                ? 'Round finished'
                : result.endReason,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 8),
          ...result.placements.take(3).map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '#${entry.placement} • Seat ${entry.seatIndex + 1} • ${entry.handCount} cards left',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ),
              ),
          if (isSpectator)
            Text(
              'Spectator view stays public-only while results resolve.',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
        ],
      ),
    );
  }
}
