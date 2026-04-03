import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/shop_models.dart';
import '../../providers/auth_provider.dart';
import '../../services/shop_service.dart';
import '../../services/socket_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/shop_appearance_resolver.dart';
import '../../utils/shop_item_asset_registry.dart';
import '../../widgets/rounded_scaffold.dart';
import '../../widgets/shop/shop_balance_header.dart';
import '../../widgets/shop/shop_inventory_item_card.dart';
import '../../widgets/shop/shop_item_artwork.dart';
import '../../widgets/shop/shop_item_card.dart';

enum _InventoryFilter { all, equipped, active, favorites, expired }

class ShopHubScreen extends StatefulWidget {
  final int initialTab;

  const ShopHubScreen({
    super.key,
    this.initialTab = 0,
  });

  @override
  State<ShopHubScreen> createState() => _ShopHubScreenState();
}

class _ShopHubScreenState extends State<ShopHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _shopSearchController = TextEditingController();
  final TextEditingController _inventorySearchController =
      TextEditingController();

  StreamSubscription<Map<String, dynamic>>? _inventorySubscription;
  StreamSubscription<Map<String, dynamic>>? _resyncSubscription;
  Timer? _refreshTimer;

  ShopHomeData? _home;
  ShopInventoryData? _inventory;
  bool _loadingHome = true;
  bool _loadingInventory = true;
  String _selectedCategory = 'all';
  _InventoryFilter _inventoryFilter = _InventoryFilter.all;

  final Set<String> _purchaseBusyIds = <String>{};
  final Set<String> _actionBusyIds = <String>{};
  final Set<String> _wishlistBusyIds = <String>{};
  final Set<String> _favoriteBusyIds = <String>{};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 1),
    );
    _inventorySubscription = SocketService.inventoryStream.listen((_) {
      _scheduleRefresh();
    });
    _resyncSubscription = SocketService.resyncStream.listen((_) {
      _scheduleRefresh();
    });
    unawaited(_loadAll());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _inventorySubscription?.cancel();
    _resyncSubscription?.cancel();
    _tabController.dispose();
    _shopSearchController.dispose();
    _inventorySearchController.dispose();
    super.dispose();
  }

  Future<void> _loadAll({bool silent = false}) async {
    await Future.wait<void>([
      _loadHome(silent: silent),
      _loadInventory(silent: silent),
    ]);
  }

  Future<void> _loadHome({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() => _loadingHome = true);
    }
    try {
      final home = await ShopService.getHome();
      if (!mounted) return;
      setState(() {
        _home = home;
        _loadingHome = false;
      });
      _syncAuthFromShopHome(home);
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingHome = false);
      _showError(error);
    }
  }

  Future<void> _loadInventory({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() => _loadingInventory = true);
    }
    try {
      final inventory = await ShopService.getInventory();
      if (!mounted) return;
      setState(() {
        _inventory = inventory;
        _loadingInventory = false;
      });
      context
          .read<AuthProvider>()
          .mergeProfilePatch({'shopProfile': inventory.shopProfile.toJson()});
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingInventory = false);
      _showError(error);
    }
  }

  void _syncAuthFromShopHome(ShopHomeData home) {
    context.read<AuthProvider>().mergeProfilePatch({
      ...home.balance,
      'shopProfile': home.shopProfile.toJson(),
    });
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      unawaited(_loadAll(silent: true));
    });
  }

  Future<void> _handlePurchase(ShopCatalogItem item) async {
    if (_purchaseBusyIds.contains(item.itemId)) return;

    final balanceCoins = _currentCoins;
    if (balanceCoins < item.effectivePriceCoins) {
      await _showInsufficientCoinsSheet(item);
      return;
    }

    final confirmed = await _showPurchaseConfirmSheet(item);
    if (confirmed != true || !mounted) return;

    setState(() => _purchaseBusyIds.add(item.itemId));
    try {
      final response = await ShopService.purchaseItem(item.itemId);
      if (!mounted) return;
      _applyMutationPayload(response);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added ${item.itemName} to your inventory.'),
        ),
      );
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _purchaseBusyIds.remove(item.itemId));
      }
    }
  }

  Future<void> _handleEquipToggle(ShopCatalogItem item) async {
    if (_actionBusyIds.contains(item.itemId)) return;
    setState(() => _actionBusyIds.add(item.itemId));
    try {
      final response = item.equipped
          ? await ShopService.unequipItem(item.itemId)
          : await ShopService.equipItem(item.itemId);
      if (!mounted) return;
      _applyShopProfileOnly(response['shopProfile']);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            item.equipped
                ? '${item.itemName} unequipped.'
                : '${item.itemName} equipped.',
          ),
        ),
      );
      _scheduleRefresh();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _actionBusyIds.remove(item.itemId));
      }
    }
  }

  Future<void> _handleUseItem(ShopCatalogItem item) async {
    if (_actionBusyIds.contains(item.itemId)) return;
    setState(() => _actionBusyIds.add(item.itemId));
    try {
      final response = await ShopService.useItem(item.itemId);
      if (!mounted) return;
      _applyMutationPayload(response);
      final reward = response['reward'] is Map
          ? Map<String, dynamic>.from(response['reward'] as Map)
          : null;
      final message = reward != null
          ? 'Opened ${item.itemName} and received ${reward['itemName']}.'
          : item.itemType == 'capsule'
              ? '${item.itemName} opened.'
              : '${item.itemName} activated.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _actionBusyIds.remove(item.itemId));
      }
    }
  }

  Future<void> _toggleWishlist(ShopCatalogItem item) async {
    if (_wishlistBusyIds.contains(item.itemId)) return;
    setState(() => _wishlistBusyIds.add(item.itemId));
    try {
      final response = await ShopService.toggleWishlist(item.itemId);
      if (!mounted) return;
      final wishlisted = response['wishlisted'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wishlisted
                ? '${item.itemName} added to wishlist.'
                : '${item.itemName} removed from wishlist.',
          ),
        ),
      );
      await _loadHome(silent: true);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _wishlistBusyIds.remove(item.itemId));
      }
    }
  }

  Future<void> _toggleFavorite(ShopInventoryEntry entry) async {
    if (_favoriteBusyIds.contains(entry.itemId)) return;
    setState(() => _favoriteBusyIds.add(entry.itemId));
    try {
      await ShopService.setInventoryFavorite(
        entry.itemId,
        favorited: !entry.favorited,
      );
      if (!mounted) return;
      await _loadInventory(silent: true);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _favoriteBusyIds.remove(entry.itemId));
      }
    }
  }

  Future<void> _openItemPreview(
    ShopCatalogItem item, {
    ShopInventoryEntry? entry,
  }) async {
    unawaited(ShopService.viewItem(item.itemId));

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _ShopItemPreviewSheet(
          item: item,
          entry: entry,
          currentCoins: _currentCoins,
          onPurchase: () async {
            Navigator.pop(context);
            await _handlePurchase(item);
          },
          onEquipToggle: item.isEquippable && item.owned
              ? () async {
                  Navigator.pop(context);
                  await _handleEquipToggle(item);
                }
              : null,
          onUse: item.activationRequired && item.owned
              ? () async {
                  Navigator.pop(context);
                  await _handleUseItem(item);
                }
              : null,
          onWishlistToggle: () async {
            Navigator.pop(context);
            await _toggleWishlist(item);
          },
          onFavoriteToggle: entry != null
              ? () async {
                  Navigator.pop(context);
                  await _toggleFavorite(entry);
                }
              : null,
        );
      },
    );
  }

  void _applyMutationPayload(Map<String, dynamic> payload) {
    final balancePatch = payload['balance'];
    final shopProfilePatch = payload['shopProfile'];

    if (balancePatch is Map) {
      context.read<AuthProvider>().mergeProfilePatch({
        ...Map<String, dynamic>.from(balancePatch),
        if (shopProfilePatch != null) 'shopProfile': shopProfilePatch,
      });
    } else if (shopProfilePatch != null) {
      _applyShopProfileOnly(shopProfilePatch);
    }

    final inventoryData = payload['inventory'];
    if (inventoryData is Map<String, dynamic>) {
      setState(() {
        _inventory = ShopInventoryData.fromJson(inventoryData);
      });
    } else if (inventoryData is Map) {
      setState(() {
        _inventory = ShopInventoryData.fromJson(
          Map<String, dynamic>.from(inventoryData),
        );
      });
    }

    _scheduleRefresh();
  }

  void _applyShopProfileOnly(dynamic shopProfilePatch) {
    final patch = shopProfilePatch is Map<String, dynamic>
        ? shopProfilePatch
        : shopProfilePatch is Map
            ? Map<String, dynamic>.from(shopProfilePatch)
            : null;
    if (patch == null) return;
    context.read<AuthProvider>().mergeProfilePatch({'shopProfile': patch});
  }

  int get _currentCoins {
    final authUser = context.read<AuthProvider>().user;
    if (authUser != null) {
      return authUser.coins;
    }
    return _toInt(_home?.balance['coins']);
  }

  List<ShopCatalogItem> get _filteredCatalog {
    final home = _home;
    if (home == null) return const [];
    final query = _shopSearchController.text.trim().toLowerCase();
    return home.catalog.where((item) {
      final categoryMatches =
          _selectedCategory == 'all' || item.itemCategory == _selectedCategory;
      if (!categoryMatches) return false;
      if (query.isEmpty) return true;
      return item.itemName.toLowerCase().contains(query) ||
          item.itemDescription.toLowerCase().contains(query) ||
          item.tags.any((tag) => tag.toLowerCase().contains(query));
    }).toList(growable: false);
  }

  List<ShopInventoryEntry> get _filteredInventoryEntries {
    final inventory = _inventory;
    if (inventory == null) return const [];
    final query = _inventorySearchController.text.trim().toLowerCase();
    final items = inventory.items.where((entry) {
      final item = entry.item;
      final matchesQuery = query.isEmpty ||
          (item?.itemName.toLowerCase().contains(query) ?? false) ||
          (item?.itemCategory.toLowerCase().contains(query) ?? false) ||
          entry.itemId.toLowerCase().contains(query);
      if (!matchesQuery) return false;

      switch (_inventoryFilter) {
        case _InventoryFilter.equipped:
          return entry.isEquipped;
        case _InventoryFilter.active:
          return entry.isActive;
        case _InventoryFilter.favorites:
          return entry.favorited;
        case _InventoryFilter.expired:
          return entry.isExpired;
        case _InventoryFilter.all:
          return true;
      }
    }).toList(growable: false);

    items.sort((left, right) {
      final leftScore = (left.isEquipped ? 40 : 0) +
          (left.isActive ? 20 : 0) +
          (left.favorited ? 10 : 0) +
          (left.isExpired ? -10 : 0);
      final rightScore = (right.isEquipped ? 40 : 0) +
          (right.isActive ? 20 : 0) +
          (right.favorited ? 10 : 0) +
          (right.isExpired ? -10 : 0);
      return rightScore.compareTo(leftScore);
    });
    return items;
  }

  @override
  Widget build(BuildContext context) {
    return RoundedScaffold(
      title: 'Shop & Inventory',
      actions: [
        IconButton(
          onPressed: () => _tabController.animateTo(0),
          icon: const Icon(Icons.storefront_rounded),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: () => _tabController.animateTo(1),
          icon: const Icon(Icons.inventory_2_rounded),
        ),
      ],
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: context.mood.surfaceSoft,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: context.mood.outlineSoft),
              ),
              child: TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'Shop'),
                  Tab(text: 'Inventory'),
                ],
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                RefreshIndicator(
                  onRefresh: _loadAll,
                  child: _buildShopTab(),
                ),
                RefreshIndicator(
                  onRefresh: _loadAll,
                  child: _buildInventoryTab(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShopTab() {
    if (_loadingHome && _home == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final home = _home;
    if (home == null) {
      return const _EmptyPanel(
        title: 'Shop is unavailable right now',
        subtitle: 'Pull to refresh and try again.',
        icon: Icons.storefront_rounded,
      );
    }

    final query = _shopSearchController.text.trim();
    final filtered = _filteredCatalog;
    final showResults = query.isNotEmpty || _selectedCategory != 'all';

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
      children: [
        ShopBalanceHeader(
          balance: home.balance,
          inventorySummary: home.inventorySummary,
          shopProfile: home.shopProfile,
          firstPurchaseReward: home.firstPurchaseReward,
        ),
        const SizedBox(height: 18),
        _SearchField(
          controller: _shopSearchController,
          hintText: 'Search cosmetics, bundles, boosters, and collectibles',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: home.categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final category = home.categories[index];
              final selected = category.id == _selectedCategory;
              return ChoiceChip(
                label: Text(category.name),
                selected: selected,
                onSelected: (_) {
                  setState(() => _selectedCategory = category.id);
                },
              );
            },
          ),
        ),
        const SizedBox(height: 18),
        if (showResults) ...[
          _SectionHeader(
            title: query.isNotEmpty
                ? 'Search Results'
                : '${_selectedCategoryLabel(home)} Picks',
            subtitle:
                '${filtered.length} item${filtered.length == 1 ? '' : 's'} matched',
          ),
          const SizedBox(height: 12),
          if (filtered.isEmpty)
            const _EmptyPanel(
              title: 'Nothing matched yet',
              subtitle: 'Try another search or browse a different category.',
              icon: Icons.search_off_rounded,
            )
          else
            _buildCatalogGrid(filtered),
        ] else ...[
          if (home.sections.collectionProgress.isNotEmpty) ...[
            const _SectionHeader(
              title: 'Collection Progress',
              subtitle: 'Complete themed sets for stronger account identity.',
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: home.sections.collectionProgress.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) => _CollectionProgressCard(
                  progress: home.sections.collectionProgress[index],
                ),
              ),
            ),
            const SizedBox(height: 22),
          ],
          _buildShelf(
            title: 'Featured',
            subtitle:
                'Premium picks designed to make your profile and room card pop.',
            items: home.sections.featured,
          ),
          _buildShelf(
            title: 'Daily Deals',
            subtitle: _dealSubtitle(home.sections.dailyDeals),
            items: home.sections.dailyDeals,
          ),
          _buildShelf(
            title: 'New Arrivals',
            subtitle: 'Fresh catalog additions for impulse upgrades.',
            items: home.sections.newArrivals,
          ),
          _buildShelf(
            title: 'Most Popular',
            subtitle: 'The cosmetics and boosts players keep coming back for.',
            items: home.sections.popular,
          ),
          _buildShelf(
            title: 'Limited Edition',
            subtitle:
                'Availability windows, limited stock, and collectible prestige.',
            items: home.sections.limited,
          ),
          _buildShelf(
            title: 'Best Value Bundles',
            subtitle: 'Get multiple cosmetics and boosters in one purchase.',
            items: home.sections.bundles,
          ),
          _buildShelf(
            title: 'Mystery Capsules',
            subtitle: 'Open curated drops with backend-controlled rewards.',
            items: home.sections.mysteryCapsules,
          ),
          _buildShelf(
            title: 'Impulse Buys',
            subtitle: 'Low-cost pickup items for quick excitement.',
            items: home.sections.lowCostImpulse,
          ),
          _buildShelf(
            title: 'Aspirational Shelf',
            subtitle: 'Mythic and legendary identity pieces worth saving for.',
            items: home.sections.aspiration,
          ),
          _buildShelf(
            title: 'Because You Bought Style',
            subtitle:
                'Set-based recommendations built from what you already own.',
            items: home.sections.recommended,
          ),
          _buildShelf(
            title: 'Recently Viewed',
            subtitle:
                'Your recent browsed items stay here for quick return visits.',
            items: home.sections.recentlyViewed,
          ),
          _buildShelf(
            title: 'Wishlist',
            subtitle: 'Track future purchases and discounted targets.',
            items: home.sections.wishlist,
          ),
          if (home.sections.weekendSpecials.isNotEmpty)
            _buildShelf(
              title: 'Weekend Specials',
              subtitle: 'Rotating spotlight items for short windows.',
              items: home.sections.weekendSpecials,
            ),
        ],
      ],
    );
  }

  Widget _buildInventoryTab() {
    if (_loadingInventory && _inventory == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final inventory = _inventory;
    if (inventory == null) {
      return const _EmptyPanel(
        title: 'Inventory unavailable',
        subtitle: 'Pull to refresh and try again.',
        icon: Icons.inventory_2_rounded,
      );
    }

    final filtered = _filteredInventoryEntries;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
      children: [
        _InventorySummaryHeader(summary: inventory.summary),
        const SizedBox(height: 18),
        _SearchField(
          controller: _inventorySearchController,
          hintText: 'Search your inventory',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _InventoryFilter.values
              .map(
                (filter) => ChoiceChip(
                  label: Text(_inventoryFilterLabel(filter)),
                  selected: _inventoryFilter == filter,
                  onSelected: (_) {
                    setState(() => _inventoryFilter = filter);
                  },
                ),
              )
              .toList(growable: false),
        ),
        if (inventory.collections.isNotEmpty) ...[
          const SizedBox(height: 18),
          SizedBox(
            height: 110,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: inventory.collections.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) => _CollectionProgressCard(
                progress: inventory.collections[index],
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),
        if (filtered.isEmpty)
          const _EmptyPanel(
            title: 'Your inventory is quiet right now',
            subtitle:
                'Purchased items, bundle grants, capsules, and boosts will appear here instantly.',
            icon: Icons.inventory_2_rounded,
          )
        else
          ...filtered.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ShopInventoryItemCard(
                entry: entry,
                favoriteBusy: _favoriteBusyIds.contains(entry.itemId),
                onToggleFavorite: () => _toggleFavorite(entry),
                onTap: entry.item == null
                    ? null
                    : () => _openItemPreview(entry.item!, entry: entry),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCatalogGrid(List<ShopCatalogItem> items) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.66,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        return ShopItemCard(
          item: item,
          wishlistBusy: _wishlistBusyIds.contains(item.itemId),
          onToggleWishlist: () => _toggleWishlist(item),
          onTap: () => _openItemPreview(item),
        );
      },
    );
  }

  Widget _buildShelf({
    required String title,
    required String subtitle,
    required List<ShopCatalogItem> items,
  }) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: title,
            subtitle: subtitle,
            decoration: ShopItemAssetRegistry.resolveSectionDecoration(title),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 286,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final item = items[index];
                return ShopItemCard(
                  item: item,
                  wishlistBusy: _wishlistBusyIds.contains(item.itemId),
                  onToggleWishlist: () => _toggleWishlist(item),
                  onTap: () => _openItemPreview(item),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _selectedCategoryLabel(ShopHomeData home) {
    for (final category in home.categories) {
      if (category.id == _selectedCategory) {
        return category.name;
      }
    }
    return 'Shop';
  }

  String _dealSubtitle(List<ShopCatalogItem> deals) {
    if (deals.isEmpty) {
      return 'Deals refresh daily.';
    }
    final upcoming = deals
        .map((item) => item.offerEndsAt)
        .whereType<DateTime>()
        .fold<DateTime?>(null, (previous, next) {
      if (previous == null || next.isBefore(previous)) {
        return next;
      }
      return previous;
    });
    if (upcoming == null) {
      return 'Deals refresh daily.';
    }
    return 'Refreshes in ${_relativeDuration(upcoming.difference(DateTime.now()))}.';
  }

  Future<bool?> _showPurchaseConfirmSheet(ShopCatalogItem item) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _ActionSheet(
          icon: Icons.shopping_bag_rounded,
          title: 'Buy ${item.itemName}?',
          subtitle:
              'Spend ${item.effectivePriceCoins} coins and grant the item instantly to your account-bound inventory.',
          actionLabel: 'Confirm Purchase',
          actionColor: const Color(0xFFF59E0B),
          onAction: () => Navigator.pop(context, true),
        );
      },
    );
  }

  Future<void> _showInsufficientCoinsSheet(ShopCatalogItem item) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _ActionSheet(
          icon: Icons.error_outline_rounded,
          title: 'Not enough coins',
          subtitle:
              'You need ${item.effectivePriceCoins - _currentCoins} more coins to buy ${item.itemName}.',
          actionLabel: 'Open Wallet',
          actionColor: const Color(0xFFE11D48),
          onAction: () {
            Navigator.pop(context);
            Navigator.pushNamed(context, '/wallet');
          },
        );
      },
    );
  }

  void _showError(Object error) {
    if (!mounted) return;
    final message = error.toString().replaceFirst('Exception: ', '').trim();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(message.isEmpty ? 'Something went wrong.' : message)),
    );
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _relativeDuration(Duration duration) {
    if (duration.inDays >= 1) return '${duration.inDays}d';
    if (duration.inHours >= 1) return '${duration.inHours}h';
    if (duration.inMinutes >= 1) return '${duration.inMinutes}m';
    final seconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
    return '${seconds}s';
  }

  static String _inventoryFilterLabel(_InventoryFilter filter) {
    switch (filter) {
      case _InventoryFilter.equipped:
        return 'Equipped';
      case _InventoryFilter.active:
        return 'Active';
      case _InventoryFilter.favorites:
        return 'Favorites';
      case _InventoryFilter.expired:
        return 'Expired';
      case _InventoryFilter.all:
        return 'All';
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final ShopSectionDecoration? decoration;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
    this.decoration,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 4),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        if (decoration != null) ...[
          const SizedBox(width: 12),
          Image.asset(
            decoration!.assetPath,
            height: decoration!.banner ? 46 : 28,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ],
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;

  const _SearchField({
    required this.controller,
    required this.hintText,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: controller.text.trim().isEmpty
            ? null
            : IconButton(
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
                icon: const Icon(Icons.close_rounded),
              ),
      ),
    );
  }
}

class _CollectionProgressCard extends StatelessWidget {
  final ShopCollectionProgress progress;

  const _CollectionProgressCard({
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final accent =
        progress.complete ? const Color(0xFF22C55E) : const Color(0xFF8B5CF6);
    return Container(
      width: 196,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            progress.name,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            progress.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Spacer(),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (progress.progressPercent / 100).clamp(0, 1),
              minHeight: 8,
              backgroundColor: accent.withValues(alpha: 0.14),
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${progress.ownedItems}/${progress.totalItems} owned',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _InventorySummaryHeader extends StatelessWidget {
  final ShopInventorySummary summary;

  const _InventorySummaryHeader({
    required this.summary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: context.mood.outlineSoft),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _InventoryMetric(label: 'Owned', value: '${summary.ownedEntries}'),
          _InventoryMetric(
            label: 'Equipped',
            value: '${summary.equippedEntries}',
          ),
          _InventoryMetric(label: 'Active', value: '${summary.activeEntries}'),
          _InventoryMetric(
            label: 'Favorites',
            value: '${summary.favoriteEntries}',
          ),
          _InventoryMetric(
              label: 'Expired', value: '${summary.expiredEntries}'),
        ],
      ),
    );
  }
}

class _InventoryMetric extends StatelessWidget {
  final String label;
  final String value;

  const _InventoryMetric({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 102,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.mood.surfaceSoft,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _EmptyPanel({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: context.mood.outlineSoft),
      ),
      child: Column(
        children: [
          Icon(icon, size: 38),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ActionSheet extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final Color actionColor;
  final VoidCallback onAction;

  const _ActionSheet({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.actionColor,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: actionColor.withValues(alpha: 0.14),
                  child: Icon(icon, color: actionColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: onAction,
                    style: FilledButton.styleFrom(
                      backgroundColor: actionColor,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(actionLabel),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ShopItemPreviewSheet extends StatelessWidget {
  final ShopCatalogItem item;
  final ShopInventoryEntry? entry;
  final int currentCoins;
  final Future<void> Function()? onPurchase;
  final Future<void> Function()? onEquipToggle;
  final Future<void> Function()? onUse;
  final Future<void> Function()? onWishlistToggle;
  final Future<void> Function()? onFavoriteToggle;

  const _ShopItemPreviewSheet({
    required this.item,
    required this.entry,
    required this.currentCoins,
    this.onPurchase,
    this.onEquipToggle,
    this.onUse,
    this.onWishlistToggle,
    this.onFavoriteToggle,
  });

  @override
  Widget build(BuildContext context) {
    final colors = resolvePreviewColors(
      item.previewStyle,
      itemId: item.itemId,
      rarity: item.rarity,
    );
    final badgeAsset = ShopItemAssetRegistry.resolveBadgeAssetPath(item);
    final previewProfile = UserShopProfile(
      equipped: item.equipSlot.isNotEmpty
          ? <String, String>{item.equipSlot: item.itemId}
          : const {},
    );
    final canAfford = currentCoins >= item.effectivePriceCoins;

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(32),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.mood.outlineSoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      colors.first.withValues(alpha: 0.98),
                      colors.length > 1
                          ? colors[1].withValues(alpha: 0.84)
                          : colors.first.withValues(alpha: 0.76),
                      const Color(0xFF0D1119),
                    ],
                    stops: const [0, 0.52, 1],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (badgeAsset != null) ...[
                                ShopImageBadge(
                                  assetPath: badgeAsset,
                                  height: 28,
                                ),
                                const SizedBox(height: 10),
                              ],
                              Text(
                                item.itemName,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item.rarity.toUpperCase(),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(
                                      color:
                                          Colors.white.withValues(alpha: 0.82),
                                    ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        ShopItemArtwork(
                          itemId: item.itemId,
                          previewStyle: item.previewStyle,
                          rarity: item.rarity,
                          width: 112,
                          height: 96,
                          borderRadius: BorderRadius.circular(24),
                          iconSize: 34,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(2.5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(colors: colors),
                            ),
                            child: CircleAvatar(
                              radius: 22,
                              backgroundColor: Colors.white,
                              child: Text(
                                'FC',
                                style: TextStyle(
                                  color: resolveDisplayNameColor(
                                    previewProfile,
                                    fallback: colors.first,
                                  ),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.08),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Friend Circle',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            color: resolveDisplayNameColor(
                                              previewProfile,
                                              fallback: Colors.white,
                                            ),
                                            fontWeight: FontWeight.w900,
                                          ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: resolveNameplateColors(
                                                previewProfile) ??
                                            <Color>[
                                              colors.first,
                                              colors.length > 1
                                                  ? colors[1]
                                                  : colors.first,
                                            ],
                                      ),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      item.itemSubcategory.replaceAll('_', ' '),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(
                item.itemDescription,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _PreviewChip(
                    label: item.itemCategory.replaceAll('_', ' '),
                    color: const Color(0xFF8B5CF6),
                  ),
                  _PreviewChip(
                    label: item.itemSubcategory.replaceAll('_', ' '),
                    color: const Color(0xFF38BDF8),
                  ),
                  _PreviewChip(
                    label: item.owned
                        ? (item.equipped ? 'Equipped' : 'Owned')
                        : '${item.effectivePriceCoins} coins',
                    color: item.owned
                        ? const Color(0xFF22C55E)
                        : const Color(0xFFF59E0B),
                  ),
                  if (entry != null && entry!.quantity > 1)
                    _PreviewChip(
                      label: 'x${entry!.quantity}',
                      color: const Color(0xFFFB7185),
                    ),
                ],
              ),
              if (item.bundleContents.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  'Bundle contents',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 10),
                ...item.bundleContents.map(
                  (bundleEntry) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: ShopItemArtwork(
                      itemId: bundleEntry['itemId']?.toString() ?? '',
                      previewStyle: const {},
                      rarity: 'common',
                      width: 54,
                      height: 44,
                      borderRadius: BorderRadius.circular(14),
                      iconSize: 20,
                    ),
                    title: Text(bundleEntry['itemId']?.toString() ?? 'Item'),
                    trailing: Text('x${bundleEntry['quantity'] ?? 1}'),
                  ),
                ),
              ],
              if (item.dropTablePreview.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  'Possible capsule rewards',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 10),
                ...item.dropTablePreview.map(
                  (reward) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: ShopItemArtwork(
                      itemId: reward.itemId,
                      previewStyle: const {},
                      rarity: reward.rarity,
                      width: 54,
                      height: 44,
                      borderRadius: BorderRadius.circular(14),
                      iconSize: 20,
                    ),
                    title: Text(reward.itemName),
                    subtitle: Text('${reward.chancePercent}% chance'),
                    trailing: Text('x${reward.quantity}'),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              Row(
                children: [
                  if (onWishlistToggle != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => onWishlistToggle!(),
                        icon: Icon(
                          item.wishlisted
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                        ),
                        label:
                            Text(item.wishlisted ? 'Wishlisted' : 'Wishlist'),
                      ),
                    ),
                  if (onWishlistToggle != null && onFavoriteToggle != null)
                    const SizedBox(width: 12),
                  if (onFavoriteToggle != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => onFavoriteToggle!(),
                        icon: Icon(
                          entry?.favorited == true
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                        ),
                        label: Text(
                          entry?.favorited == true ? 'Favorite' : 'Save',
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (!item.owned)
                FilledButton(
                  onPressed: canAfford && onPurchase != null
                      ? () => onPurchase!()
                      : null,
                  child: Text(
                    canAfford
                        ? 'Buy for ${item.effectivePriceCoins} coins'
                        : 'Need ${item.effectivePriceCoins - currentCoins} more coins',
                  ),
                )
              else if (item.isEquippable)
                FilledButton(
                  onPressed:
                      onEquipToggle == null ? null : () => onEquipToggle!(),
                  child: Text(item.equipped ? 'Unequip' : 'Equip now'),
                )
              else if (item.activationRequired)
                FilledButton(
                  onPressed: onUse == null ? null : () => onUse!(),
                  child:
                      Text(item.itemType == 'capsule' ? 'Open now' : 'Use now'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewChip extends StatelessWidget {
  final String label;
  final Color color;

  const _PreviewChip({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}
