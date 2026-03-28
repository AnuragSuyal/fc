import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/gift_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/gift_service.dart';
import '../../utils/constants.dart';
import '../../utils/haptics_util.dart';
import '../../utils/media_url.dart';
import '../currency_icon.dart';

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
    with TickerProviderStateMixin {
  late TabController _tabController;
  Map<String, List<GiftModel>> _catalog = {};
  bool _isLoading = true;
  String? _errorMessage;
  GiftModel? _selectedGift;
  final TextEditingController _messageController = TextEditingController();
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadCatalog();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _messageController.dispose();
    super.dispose();
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
    if (_selectedGift == null) return;

    setState(() => _isSending = true);

    try {
      final result = await GiftService.sendGift(
        toUserId: widget.toUserId,
        giftId: _selectedGift!.id,
        roomId: widget.roomId,
        message: _messageController.text,
      );

      final sentSuccessfully =
          result['success'] == true || result['transactionId'] != null;

      if (sentSuccessfully) {
        if (!mounted) return;

        // Update auth provider balance
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

        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gift sent to ${widget.toUsername}!'),
            backgroundColor: AppColors.successGreen,
          ),
        );
        return;
      }

      if (!mounted) return;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to send gift right now.'),
          backgroundColor: AppColors.errorRed,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      HapticsUtil.error();
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Failed to send gift: ${e.toString().replaceFirst('Exception: ', '')}'),
          backgroundColor: AppColors.errorRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Send Gift',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'To: ${widget.toUsername}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Row(
                    children: [
                      const CurrencyIcon.coins(size: 16),
                      const SizedBox(width: 4),
                      Text(
                        '${user?.coins ?? 0}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      const CurrencyIcon.gems(size: 16),
                      const SizedBox(width: 4),
                      Text(
                        '${user?.gems ?? 0}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Tabs
          TabBar(
            controller: _tabController,
            labelColor: AppColors.primaryBlue,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AppColors.primaryBlue,
            tabs: const [
              Tab(text: 'Simple'),
              Tab(text: 'Premium'),
              Tab(text: 'Luxury'),
              Tab(text: 'Limited'),
            ],
          ),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(child: Text(_errorMessage!))
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildGiftGrid(_catalog['simple'] ?? []),
                          _buildGiftGrid(_catalog['premium'] ?? []),
                          _buildGiftGrid(_catalog['luxury'] ?? []),
                          _buildGiftGrid(_catalog['legendary'] ?? []),
                        ],
                      ),
          ),

          // Footer
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_selectedGift != null) ...[
                  Row(
                    children: [
                      Text(
                        'Selected: ${_selectedGift!.name}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          if (_selectedGift!.coinsPrice > 0) ...[
                            const CurrencyIcon.coins(size: 14),
                            const SizedBox(width: 4),
                            Text('${_selectedGift!.coinsPrice}'),
                            const SizedBox(width: 8),
                          ],
                          if (_selectedGift!.gemsPrice > 0) ...[
                            const CurrencyIcon.gems(size: 14),
                            const SizedBox(width: 4),
                            Text('${_selectedGift!.gemsPrice}'),
                          ],
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Add a message (optional)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Receiver gains about ${_giftXpReward(_selectedGift!)} XP',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isSending ? null : _sendGift,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isSending
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : const Text('Send Gift'),
                    ),
                  ),
                ] else
                  const Text('Select a gift to send'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGiftGrid(List<GiftModel> gifts) {
    if (gifts.isEmpty) {
      return const Center(child: Text('No gifts available in this category'));
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.8,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemCount: gifts.length,
      itemBuilder: (context, index) {
        final gift = gifts[index];
        final isSelected = _selectedGift?.id == gift.id;

        return GestureDetector(
          onTap: () {
            setState(() => _selectedGift = gift);
          },
          child: Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primaryBlue.withValues(alpha: 0.1)
                  : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? AppColors.primaryBlue : Colors.transparent,
                width: 2,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _GiftIconPreview(
                  icon: gift.icon,
                  size: 48,
                ),
                const SizedBox(height: 8),
                Text(
                  gift.name,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (gift.coinsPrice > 0) ...[
                      const CurrencyIcon.coins(size: 12),
                      const SizedBox(width: 2),
                      Text(
                        '${gift.coinsPrice}',
                        style: const TextStyle(fontSize: 10),
                      ),
                    ] else if (gift.gemsPrice > 0) ...[
                      const CurrencyIcon.gems(size: 12),
                      const SizedBox(width: 2),
                      Text(
                        '${gift.gemsPrice}',
                        style: const TextStyle(fontSize: 10),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
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
}

class _GiftIconPreview extends StatelessWidget {
  final String icon;
  final double size;

  const _GiftIconPreview({
    required this.icon,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedUrl = resolveMediaUrl(icon);
    if (resolvedUrl == null) {
      return Text(
        icon,
        style: TextStyle(fontSize: size * 0.8),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.network(
        resolvedUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Icon(
          Icons.card_giftcard_rounded,
          size: size * 0.68,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}
