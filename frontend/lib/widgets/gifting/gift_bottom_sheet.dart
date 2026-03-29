import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/gift_catalog_constants.dart';
import '../../models/gift_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/gift_service.dart';
import '../../utils/haptics_util.dart';
import '../currency_icon.dart';
import 'gift_sheet_components.dart';
import 'gift_sheet_theme.dart';

Future<bool?> showGiftBottomSheet({
  required BuildContext context,
  required String toUserId,
  required String toUsername,
  String? roomId,
}) {
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: GiftSheetTokens.overlay,
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (context, _, __) => GiftBottomSheet(
      toUserId: toUserId,
      toUsername: toUsername,
      roomId: roomId,
    ),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.08),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class GiftBottomSheet extends StatefulWidget {
  final String toUserId;
  final String toUsername;
  final String? roomId;

  const GiftBottomSheet({
    super.key,
    required this.toUserId,
    required this.toUsername,
    this.roomId,
  });

  @override
  State<GiftBottomSheet> createState() => _GiftBottomSheetState();
}

class _GiftBottomSheetState extends State<GiftBottomSheet>
    with SingleTickerProviderStateMixin {
  static const List<GiftCategoryTab> _categories = giftCategoryTabs;

  late final TabController _tabController;
  Map<String, List<GiftModel>> _catalog = {};
  bool _isLoading = true;
  String? _errorMessage;
  GiftModel? _selectedGift;
  final TextEditingController _messageController = TextEditingController();
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _categories.length, vsync: this)
      ..addListener(_handleTabChanged);
    _loadCatalog();
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_handleTabChanged)
      ..dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _loadCatalog() async {
    try {
      final catalog = await GiftService.getGiftCatalog();
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _sendGift() async {
    if (_selectedGift == null || !_canSendSelectedGift) return;

    setState(() => _isSending = true);

    try {
      final result = await GiftService.sendGift(
        toUserId: widget.toUserId,
        giftId: _selectedGift!.id,
        roomId: widget.roomId,
        message: _messageController.text.trim(),
      );

      final sentSuccessfully =
          result['success'] == true || result['transactionId'] != null;

      if (sentSuccessfully) {
        if (!mounted) return;

        if (result['newBalance'] != null) {
          final authProvider =
              Provider.of<AuthProvider>(context, listen: false);
          authProvider.updateProfile(
            coins: result['newBalance']['coins'],
            gems: result['newBalance']['gems'],
            xp: result['newBalance']['xp'],
            level: result['newBalance']['level'],
            vipLevel: result['newBalance']['vipLevel'],
          );
        }

        HapticsUtil.giftReceived();
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gift sent to ${widget.toUsername}!'),
            backgroundColor: const Color(0xFF102B1E),
          ),
        );
        return;
      }

      if (!mounted) return;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to send gift right now.'),
          backgroundColor: Color(0xFF3F1218),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      HapticsUtil.error();
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to send gift: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
          backgroundColor: const Color(0xFF3F1218),
        ),
      );
    }
  }

  void _selectGift(GiftModel gift) {
    HapticsUtil.selectionClick();
    setState(() => _selectedGift = gift);
  }

  void _selectCategory(int index) {
    HapticsUtil.lightImpact();
    _tabController.animateTo(index);
  }

  int _giftXpReward(GiftModel gift) {
    final recipientEffects = gift.effects['recipient'];
    final senderEffects = gift.effects['sender'];
    final rawXp = recipientEffects is Map
        ? recipientEffects['xp']
        : senderEffects is Map
            ? senderEffects['xp']
            : null;

    if (rawXp is int) return rawXp;
    if (rawXp is num) return rawXp.toInt();

    final derived = (gift.coinsPrice / 20).floor() + (gift.gemsPrice * 2);
    return derived > 0 ? derived : 1;
  }

  bool get _canSendSelectedGift {
    final user = context.read<AuthProvider>().user;
    final gift = _selectedGift;
    if (user == null || gift == null) return false;
    return gift.canAfford(user.coins, user.gems);
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;
    final viewInsets = MediaQuery.of(context).viewInsets;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final height = MediaQuery.of(context).size.height;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(false),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  color: GiftSheetTokens.backdropTint,
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: AnimatedPadding(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.only(bottom: viewInsets.bottom),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(12, 24, 12, 12 + safeBottom),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                      child: Container(
                        constraints: BoxConstraints(
                          maxHeight: height * 0.84,
                          minHeight: height * 0.56,
                        ),
                        decoration: GiftSheetTokens.glassPanel(radius: 32),
                        child: Column(
                          children: [
                            const SizedBox(height: 10),
                            Container(
                              width: 54,
                              height: 5,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(18, 14, 18, 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Send Gift',
                                          style: TextStyle(
                                            color: GiftSheetTokens.primaryText,
                                            fontSize: 24,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.2,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'To: ${widget.toUsername}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color:
                                                GiftSheetTokens.secondaryText,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          GiftBalancePill(
                                            amount: user?.coins ?? 0,
                                            icon: const CurrencyIcon.coins(
                                              size: 14,
                                            ),
                                            gradient:
                                                GiftSheetTokens.goldGradient,
                                            glowColor: GiftSheetTokens.gold,
                                          ),
                                          const SizedBox(width: 8),
                                          GiftBalancePill(
                                            amount: user?.gems ?? 0,
                                            icon: const CurrencyIcon.gems(
                                              size: 14,
                                            ),
                                            gradient:
                                                GiftSheetTokens.cyanGradient,
                                            glowColor: GiftSheetTokens.cyan,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          borderRadius:
                                              BorderRadius.circular(999),
                                          onTap: () =>
                                              Navigator.of(context).pop(false),
                                          child: Ink(
                                            width: 38,
                                            height: 38,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: Colors.white
                                                  .withValues(alpha: 0.06),
                                              border: Border.all(
                                                color: GiftSheetTokens.border,
                                              ),
                                            ),
                                            child: const Icon(
                                              Icons.close_rounded,
                                              color:
                                                  GiftSheetTokens.primaryText,
                                              size: 18,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(18, 0, 18, 12),
                              child: _buildCategoryBar(),
                            ),
                            Expanded(
                              child: _buildBody(user?.coins ?? 0, user?.gems ?? 0),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(18, 8, 18, 18),
                              child: _buildFooter(user?.coins ?? 0, user?.gems ?? 0),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryBar() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: GiftSheetTokens.innerGlass(
        radius: 24,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(_categories.length, (index) {
            final category = _categories[index];
            final selected = _tabController.index == index;
            return Padding(
              padding: EdgeInsets.only(right: index == _categories.length - 1 ? 0 : 8),
              child: GiftCategoryChip(
                label: category.label,
                selected: selected,
                onTap: () => _selectCategory(index),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildBody(int userCoins, int userGems) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: GiftSheetTokens.gold,
          strokeWidth: 2.6,
        ),
      );
    }

    if (_errorMessage != null) {
      return _buildEmptyState(
        title: 'Unable to load gifts',
        subtitle: _errorMessage!,
        actionLabel: 'Try again',
        onAction: () {
          setState(() {
            _isLoading = true;
            _errorMessage = null;
          });
          _loadCatalog();
        },
      );
    }

    return TabBarView(
      controller: _tabController,
      children: _categories.map((category) {
        final gifts = _catalog[category.key] ?? const <GiftModel>[];
        return _buildGiftGrid(
          gifts,
          userCoins: userCoins,
          userGems: userGems,
        );
      }).toList(),
    );
  }

  Widget _buildGiftGrid(
    List<GiftModel> gifts, {
    required int userCoins,
    required int userGems,
  }) {
    if (gifts.isEmpty) {
      return _buildEmptyState(
        title: 'No gifts here yet',
        subtitle: 'This collection will light up soon.',
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 170,
        childAspectRatio: 0.66,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
      ),
      itemCount: gifts.length,
      itemBuilder: (context, index) {
        final gift = gifts[index];
        return GiftCatalogTile(
          gift: gift,
          selected: _selectedGift?.id == gift.id,
          affordable: gift.canAfford(userCoins, userGems),
          onTap: () => _selectGift(gift),
        );
      },
    );
  }

  Widget _buildFooter(int userCoins, int userGems) {
    final selectedGift = _selectedGift;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: selectedGift == null
          ? Container(
              key: const ValueKey('gift-hint'),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
              decoration: GiftSheetTokens.innerGlass(radius: 26),
              child: const Row(
                children: [
                  Icon(
                    Icons.card_giftcard_rounded,
                    color: GiftSheetTokens.secondaryText,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Select a gift to send',
                      style: TextStyle(
                        color: GiftSheetTokens.secondaryText,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : _SelectedGiftFooter(
              key: ValueKey(selectedGift.id),
              gift: selectedGift,
              username: widget.toUsername,
              messageController: _messageController,
              canAfford: selectedGift.canAfford(userCoins, userGems),
              isSending: _isSending,
              xpReward: _giftXpReward(selectedGift),
              onSend: _sendGift,
            ),
    );
  }

  Widget _buildEmptyState({
    required String title,
    required String subtitle,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: GiftSheetTokens.innerGlass(radius: 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06),
                  border: Border.all(color: GiftSheetTokens.border),
                ),
                child: const Icon(
                  Icons.redeem_rounded,
                  color: GiftSheetTokens.secondaryText,
                  size: 30,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: GiftSheetTokens.primaryText,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: GiftSheetTokens.secondaryText,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 18),
                TextButton(
                  onPressed: onAction,
                  child: Text(actionLabel),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedGiftFooter extends StatelessWidget {
  const _SelectedGiftFooter({
    super.key,
    required this.gift,
    required this.username,
    required this.messageController,
    required this.canAfford,
    required this.isSending,
    required this.xpReward,
    required this.onSend,
  });

  final GiftModel gift;
  final String username;
  final TextEditingController messageController;
  final bool canAfford;
  final bool isSending;
  final int xpReward;
  final VoidCallback onSend;

  bool get _usesCoins => gift.coinsPrice > 0;
  int get _price => _usesCoins ? gift.coinsPrice : gift.gemsPrice;

  @override
  Widget build(BuildContext context) {
    final accent = _usesCoins ? GiftSheetTokens.gold : GiftSheetTokens.cyan;

    return Container(
      key: const ValueKey('gift-selected'),
      padding: const EdgeInsets.all(16),
      decoration: GiftSheetTokens.innerGlass(
        radius: 28,
        selected: true,
        tint: accent,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    colors: [
                      accent.withValues(alpha: 0.24),
                      Colors.white.withValues(alpha: 0.06),
                    ],
                  ),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.3),
                  ),
                ),
                child: GiftVisualBadge(
                  gift: gift,
                  accent: accent,
                  selected: true,
                  size: 44,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      gift.name,
                      style: const TextStyle(
                        color: GiftSheetTokens.primaryText,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Sending to $username',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: GiftSheetTokens.secondaryText,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  if (_usesCoins)
                    const CurrencyIcon.coins(size: 14)
                  else
                    const CurrencyIcon.gems(size: 14),
                  const SizedBox(width: 4),
                  Text(
                    '$_price',
                    style: TextStyle(
                      color: accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: messageController,
            maxLength: 80,
            style: const TextStyle(
              color: GiftSheetTokens.primaryText,
              fontSize: 14,
            ),
            decoration: InputDecoration(
              counterStyle: const TextStyle(
                color: GiftSheetTokens.mutedText,
                fontSize: 11,
              ),
              hintText: 'Add a premium note (optional)',
              hintStyle: const TextStyle(
                color: GiftSheetTokens.mutedText,
                fontSize: 13,
              ),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: const BorderSide(color: GiftSheetTokens.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(
                  color: accent.withValues(alpha: 0.45),
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                'Receiver gains about $xpReward XP',
                style: const TextStyle(
                  color: GiftSheetTokens.secondaryText,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (!canAfford)
                const Text(
                  'Insufficient balance',
                  style: TextStyle(
                    color: GiftSheetTokens.danger,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: canAfford
                    ? GiftSheetTokens.actionGradient
                    : LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0.1),
                          Colors.white.withValues(alpha: 0.06),
                        ],
                      ),
                boxShadow: canAfford
                    ? [
                        BoxShadow(
                          color: GiftSheetTokens.gold.withValues(alpha: 0.18),
                          blurRadius: 24,
                          spreadRadius: 1,
                        ),
                      ]
                    : const [],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: canAfford && !isSending ? onSend : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isSending)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Color(0xFF0A0A0E),
                            ),
                          )
                        else
                          const Icon(
                            Icons.auto_awesome_rounded,
                            color: Color(0xFF0A0A0E),
                            size: 18,
                          ),
                        const SizedBox(width: 10),
                        Text(
                          isSending ? 'Sending...' : 'Send Gift',
                          style: TextStyle(
                            color: canAfford
                                ? const Color(0xFF0A0A0E)
                                : GiftSheetTokens.secondaryText,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
