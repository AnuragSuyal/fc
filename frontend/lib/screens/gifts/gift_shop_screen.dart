import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/gift_service.dart';
import '../../models/gift_model.dart';
import '../../utils/constants.dart';
import '../../widgets/gift_card.dart';
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

  final List<Map<String, dynamic>> _categories = [
    {'id': 'simple', 'name': 'Simple', 'icon': 'â¤ï¸', 'color': Colors.grey},
    {'id': 'premium', 'name': 'Premium', 'icon': 'ðŸ‘‘', 'color': Colors.blue},
    {'id': 'luxury', 'name': 'Luxury', 'icon': 'ðŸ’Ž', 'color': Colors.purple},
    {
      'id': 'legendary',
      'name': 'Legendary',
      'icon': 'âœ¨',
      'color': Colors.amber
    },
  ];

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
        // Balance display
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
              const Icon(Icons.monetization_on, size: 14, color: Colors.amber),
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
              const Icon(Icons.diamond, size: 14, color: Color(0xFFAA66FF)),
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
                      Icon(Icons.error_outline,
                          size: 64, color: Colors.red.shade300),
                      const SizedBox(height: 16),
                      const Text('Failed to load gifts'),
                      const SizedBox(height: 8),
                      Text(_error!,
                          style: TextStyle(color: Colors.grey.shade600)),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _loadGifts,
                        child: const Text('Try Again'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  // â† THIS FIXES THE OVERFLOW
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Category tabs
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _categories.map((category) {
                            final isSelected =
                                _selectedCategory == category['id'];
                            return Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: ChoiceChip(
                                label: Row(
                                  children: [
                                    Text(category['icon'],
                                        style: const TextStyle(fontSize: 14)),
                                    const SizedBox(width: 4),
                                    Text(category['name']),
                                  ],
                                ),
                                selected: isSelected,
                                onSelected: (bool selected) {
                                  if (selected) {
                                    setState(() =>
                                        _selectedCategory = category['id']);
                                  }
                                },
                                selectedColor: AppColors.primaryBlue,
                                labelStyle: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : AppColors.textPrimary,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                                backgroundColor: AppColors.surfaceGrey,
                                side: BorderSide.none,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20)),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                showCheckmark: false,
                              ),
                            );
                          }).toList(),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Gift grid
                      if (currentGifts.isEmpty)
                        Center(
                          child: Column(
                            children: [
                              Icon(Icons.card_giftcard,
                                  size: 64, color: Colors.grey.shade300),
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
                        padding: EdgeInsets.symmetric(vertical: 8.0),
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
                          children: [
                            _buildActivityItem(
                                'Alice sent a Rose to Bob', '2m ago', 'ðŸŒ¹'),
                            const Divider(height: 1, color: Colors.grey),
                            _buildActivityItem('Charlie sent a Crown to Max',
                                '15m ago', 'ðŸ‘‘'),
                            const Divider(height: 1, color: Colors.grey),
                            _buildActivityItem(
                                'You received a Heart from Sarah',
                                '1h ago',
                                'â¤ï¸'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildActivityItem(String text, String time, String icon) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(child: Text(icon, style: const TextStyle(fontSize: 20))),
      ),
      title: Text(text,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
      trailing: Text(time,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
    );
  }
}
