import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/gift_catalog_constants.dart';
import '../../models/gift_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/gift_service.dart';
import '../../utils/constants.dart';
import '../../widgets/currency_icon.dart';
import '../../widgets/gift_card.dart';
import '../../widgets/gift_image.dart';
import '../../widgets/rounded_scaffold.dart';
import 'send_gift_screen.dart';

class GiftShopScreen extends StatefulWidget {
  final String? initialRecipientId;

  const GiftShopScreen({
    super.key,
    this.initialRecipientId,
  });

  @override
  State<GiftShopScreen> createState() => _GiftShopScreenState();
}

class _GiftShopScreenState extends State<GiftShopScreen> {
  Map<String, List<GiftModel>> _categorizedGifts = {};
  String _selectedCategory = 'simple';
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadGifts();
  }

  Future<void> _loadGifts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final categorizedGifts = await GiftService.getGiftCatalog();
      if (!mounted) return;

      setState(() {
        _categorizedGifts = categorizedGifts;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;
    final currentGifts = _categorizedGifts[_selectedCategory] ?? [];

    return RoundedScaffold(
      title: 'Gift Shop',
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 16, top: 4, bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.surfaceGrey,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CurrencyIcon.coins(size: 14),
              const SizedBox(width: 4),
              Text(
                '${user?.coins ?? 0}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 10),
              const CurrencyIcon.gems(size: 14),
              const SizedBox(width: 4),
              Text(
                '${user?.gems ?? 0}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.red.shade300,
                      ),
                      const SizedBox(height: 16),
                      const Text('Failed to load gifts'),
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _loadGifts,
                        child: const Text('Try Again'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: giftCategoryTabs.map((category) {
                            final isSelected =
                                _selectedCategory == category.key;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(category.label),
                                selected: isSelected,
                                onSelected: (selected) {
                                  if (selected) {
                                    setState(
                                      () => _selectedCategory = category.key,
                                    );
                                  }
                                },
                                selectedColor: AppColors.primaryBlue,
                                labelStyle: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : AppColors.textPrimary,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.w600,
                                ),
                                backgroundColor: AppColors.surfaceGrey,
                                side: BorderSide.none,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                showCheckmark: false,
                              ),
                            );
                          }).toList(growable: false),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (currentGifts.isEmpty)
                        Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.card_giftcard_rounded,
                                size: 64,
                                color: Colors.grey.shade300,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'No gifts in this category',
                                style:
                                    TextStyle(color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        )
                      else
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 0.85,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: currentGifts.length,
                          itemBuilder: (context, index) {
                            final gift = currentGifts[index];
                            return GiftCard(
                              gift: gift,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => SendGiftScreen(
                                      gift: gift,
                                      initialRecipientId:
                                          widget.initialRecipientId,
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      const SizedBox(height: 32),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'RECENT ACTIVITY',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.surfaceGrey,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: const [
                            _GiftActivityItem(
                              text: 'Alice sent a Heart Duo to Bob',
                              time: '2m ago',
                              assetPath: 'assets/gifts/simple_heart_duo.png',
                            ),
                            Divider(height: 1, color: Colors.grey),
                            _GiftActivityItem(
                              text: 'Charlie sent a Royal Crown to Max',
                              time: '15m ago',
                              assetPath: 'assets/gifts/premium_royal_crown.png',
                            ),
                            Divider(height: 1, color: Colors.grey),
                            _GiftActivityItem(
                              text: 'You received a Celebration Cake from Sarah',
                              time: '1h ago',
                              assetPath:
                                  'assets/gifts/limited_celebration_cake.png',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _GiftActivityItem extends StatelessWidget {
  const _GiftActivityItem({
    required this.text,
    required this.time,
    required this.assetPath,
  });

  final String text;
  final String time;
  final String assetPath;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: GiftImage(
            source: assetPath,
            width: 24,
            height: 24,
            fallback: const Icon(
              Icons.card_giftcard_rounded,
              size: 18,
            ),
          ),
        ),
      ),
      title: Text(
        text,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14,
        ),
      ),
      trailing: Text(
        time,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
        ),
      ),
    );
  }
}
