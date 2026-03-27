import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../utils/haptics_util.dart';
import 'reaction_artwork.dart';

class ReactionQuickPanel extends StatefulWidget {
  final void Function(String) onSelectEmoji;
  final bool compact;
  final VoidCallback? onOpenFullPicker;

  const ReactionQuickPanel({
    super.key,
    required this.onSelectEmoji,
    this.compact = false,
    this.onOpenFullPicker,
  });

  @override
  State<ReactionQuickPanel> createState() => _ReactionQuickPanelState();
}

class _ReactionQuickPanelState extends State<ReactionQuickPanel> {
  static const List<_ReactionCategory> _categories = [
    _ReactionCategory(
      title: 'Quick',
      items: [
        _ReactionItem('\u{1F926}\u200D\u2642\uFE0F', 'Facepalm'),
        _ReactionItem('\u{1F610}', 'Dark line'),
        _ReactionItem('\u{1F60F}', 'Smirk'),
        _ReactionItem('\u{1F64C}', 'Raise hands'),
        _ReactionItem('\u{1F44B}', 'Wave'),
        _ReactionItem('\u{1FAF6}', 'Like you'),
      ],
    ),
    _ReactionCategory(
      title: 'Mood',
      items: [
        _ReactionItem('\u{1F62D}', 'Tears run'),
        _ReactionItem('\u{1F621}', 'Angry'),
        _ReactionItem('\u{1F622}', 'Cried'),
        _ReactionItem('\u{1F634}', 'Sleepy'),
        _ReactionItem('\u{1F62E}', 'Oops'),
        _ReactionItem('\u{2764}\uFE0F', 'Heart'),
      ],
    ),
    _ReactionCategory(
      title: 'Voice',
      items: [
        _ReactionItem('🎤', 'Mic'),
        _ReactionItem('💬', 'Chat'),
        _ReactionItem('📣', 'Shout'),
        _ReactionItem('🔴', 'Live'),
        _ReactionItem('📡', 'On Air'),
        _ReactionItem('👂', 'Listen'),
        _ReactionItem('👏', 'Clap'),
        _ReactionItem('🎵', 'Music'),
      ],
    ),
    _ReactionCategory(
      title: 'Fun',
      items: [
        _ReactionItem('👻', 'Ghost'),
        _ReactionItem('👽', 'Alien'),
        _ReactionItem('🤖', 'Robot'),
        _ReactionItem('🕺', 'Swing'),
        _ReactionItem('🙋', 'Wave up'),
        _ReactionItem('🙇', "I'm wrong"),
        _ReactionItem('😘', 'Kiss'),
        _ReactionItem('🚀', 'Rocket'),
      ],
    ),
    _ReactionCategory(
      title: 'Room',
      items: [
        _ReactionItem('🎮', 'Game'),
        _ReactionItem('🤫', 'Shh'),
        _ReactionItem('⭐', 'Star'),
        _ReactionItem('💩', 'Poop'),
        _ReactionItem('💤', 'AFK'),
        _ReactionItem('👋', 'Farewell'),
        _ReactionItem('😄', 'Grin'),
        _ReactionItem('😃', 'Chill'),
      ],
    ),
  ];

  int _selectedCategoryIndex = 0;

  void _emitReaction(String emoji) {
    HapticsUtil.lightImpact();
    widget.onSelectEmoji(emoji);
    if (!widget.compact && mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedCategory = _categories[_selectedCategoryIndex];
    final quickItems = _categories.first.items;
    final isMoodCategory = selectedCategory.title == 'Mood';

    if (widget.compact) {
      return Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: const Color(0xFF15141C),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                for (var i = 0; i < quickItems.length; i++) ...[
                  Expanded(
                    child: _CompactReactionTile(
                      emoji: quickItems[i].emoji,
                      onTap: () => _emitReaction(quickItems[i].emoji),
                    ),
                  ),
                  if (i != quickItems.length - 1) const SizedBox(width: 8),
                ],
              ],
            ),
            if (widget.onOpenFullPicker != null) ...[
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: widget.onOpenFullPicker,
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: const Text('Reaction pack'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white70,
                  minimumSize: const Size.fromHeight(34),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return FractionallySizedBox(
      heightFactor: 0.68,
      child: Container(
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 18),
        decoration: const BoxDecoration(
          color: Color(0xFF1C1B22),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Reaction Pack',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF11B9E8).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'All set',
                        style: TextStyle(
                          color: Color(0xFF63DDFF),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 18),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Tap a reaction to drop it straight into the room.',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 40,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: _categories.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final category = _categories[index];
                    final selected = index == _selectedCategoryIndex;
                    return GestureDetector(
                      onTap: () {
                        if (_selectedCategoryIndex == index) return;
                        setState(() {
                          _selectedCategoryIndex = index;
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFF11B9E8).withValues(alpha: 0.22)
                              : Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: selected
                                ? const Color(0xFF3DD9FF)
                                : Colors.white10,
                          ),
                        ),
                        child: Text(
                          category.title,
                          style: TextStyle(
                            color: selected
                                ? const Color(0xFF74E4FF)
                                : Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: GridView.builder(
                    key: ValueKey(selectedCategory.title),
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
                    physics: const AlwaysScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: isMoodCategory ? 3 : 4,
                      crossAxisSpacing: isMoodCategory ? 16 : 12,
                      mainAxisSpacing: 16,
                      childAspectRatio: 1,
                    ),
                    itemCount: selectedCategory.items.length,
                    itemBuilder: (context, index) {
                      final item = selectedCategory.items[index];
                      return _FullReactionTile(
                        emoji: item.emoji,
                        label: item.label,
                        onTap: () => _emitReaction(item.emoji),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReactionCategory {
  final String title;
  final List<_ReactionItem> items;

  const _ReactionCategory({
    required this.title,
    required this.items,
  });
}

class _ReactionItem {
  final String emoji;
  final String label;

  const _ReactionItem(this.emoji, this.label);
}

class _CompactReactionTile extends StatelessWidget {
  final String emoji;
  final VoidCallback onTap;

  const _CompactReactionTile({
    required this.emoji,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        height: 48,
        child: Center(
          child: ReactionArtwork(
            emoji: emoji,
            size: 28,
            fallbackTextStyle: const TextStyle(
              fontSize: 28,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _FullReactionTile extends StatelessWidget {
  final String emoji;
  final String label;
  final VoidCallback onTap;

  const _FullReactionTile({
    required this.emoji,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasArtwork = reactionArtworkAsset(emoji) != null;

    return GestureDetector(
      onTap: onTap,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final boxSize = math.min(constraints.maxWidth, constraints.maxHeight);
          final artworkSize = hasArtwork
              ? (boxSize * 0.82).clamp(44.0, 78.0)
              : (boxSize * 0.46).clamp(28.0, 38.0);

          return Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white10),
            ),
            alignment: Alignment.center,
            padding: const EdgeInsets.all(8),
            child: ReactionArtwork(
              emoji: emoji,
              size: artworkSize,
              fallbackTextStyle: TextStyle(
                fontSize: artworkSize,
                height: 1,
              ),
            ),
          );
        },
      ),
    );
  }
}
