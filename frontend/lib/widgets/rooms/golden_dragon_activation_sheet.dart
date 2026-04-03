import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/golden_dragon_model.dart';
import '../../services/golden_dragon_service.dart';

class GoldenDragonActivationSheet extends StatefulWidget {
  const GoldenDragonActivationSheet({
    super.key,
    required this.roomId,
    required this.roomName,
    this.onActivated,
  });

  final String roomId;
  final String roomName;
  final ValueChanged<GoldenDragonLiveEvent>? onActivated;

  @override
  State<GoldenDragonActivationSheet> createState() =>
      _GoldenDragonActivationSheetState();
}

class _GoldenDragonActivationSheetState
    extends State<GoldenDragonActivationSheet> {
  DragonPacketInventoryResponse? _inventoryResponse;
  bool _isLoading = true;
  bool _isActivating = false;
  String _selectedSku = '';
  String? _busySku;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    unawaited(_loadInventory());
  }

  Future<void> _loadInventory({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final inventory = await GoldenDragonService.getInventory();
      if (!mounted) return;
      final defaultSku = _selectedSku.isNotEmpty
          ? _selectedSku
          : inventory.products.isNotEmpty
              ? inventory.products.first.sku
              : '';
      setState(() {
        _inventoryResponse = inventory;
        _selectedSku = defaultSku;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _normalizeError(
          error,
          fallback: 'Could not load Golden Dragon packets',
        );
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0xFF2A0908),
            Color(0xFF130606),
          ],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
          child: _isLoading
              ? const SizedBox(
                  height: 340,
                  child: Center(child: CircularProgressIndicator()),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _buildHero(theme),
                    if (_errorMessage != null) ...<Widget>[
                      const SizedBox(height: 14),
                      _buildErrorBanner(_errorMessage!),
                    ],
                    const SizedBox(height: 18),
                    Text(
                      'Choose your packet',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 188,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _products.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (context, index) =>
                            _buildProductCard(_products[index]),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _buildSelectionSummary(),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _isActivating ? null : _handlePrimaryAction,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFFCC4D),
                          foregroundColor: const Color(0xFF2B1200),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
                        ),
                        child: _isActivating
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: Color(0xFF2B1200),
                                ),
                              )
                            : Text(
                                _selectedAvailableItem != null
                                    ? 'Release in ${widget.roomName}'
                                    : 'Buy ${_selectedProduct?.priceInr ?? 0} INR packet',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildHero(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFFF66B1D),
            Color(0xFFB61E0E),
            Color(0xFF5A0A0A),
          ],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFFFF7B1B).withValues(alpha: 0.28),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Golden Dragon',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Release a 10-second room rush. Faster tappers pull a bigger share.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.84),
                    height: 1.42,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    color: Colors.black.withValues(alpha: 0.16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: const Text(
                    'Server-timed • Competitive • Premium',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Image.asset(
              'assets/images/golden_dragon_banner.png',
              width: 116,
              height: 116,
              fit: BoxFit.cover,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(GoldenDragonProduct product) {
    final selected = product.sku == _selectedSku;
    final availableCount =
        _inventoryResponse?.summary.availableCounts[product.sku] ?? 0;
    final purchaseBusy = _busySku == product.sku;

    return GestureDetector(
      onTap: () => setState(() => _selectedSku = product.sku),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 144,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: selected
                ? const <Color>[Color(0xFFFFF1C2), Color(0xFFFFC74E)]
                : const <Color>[Color(0xFF230F0D), Color(0xFF160A08)],
          ),
          border: Border.all(
            color: selected
                ? const Color(0xFFFFD875)
                : Colors.white.withValues(alpha: 0.08),
            width: selected ? 1.6 : 1,
          ),
          boxShadow: <BoxShadow>[
            if (selected)
              BoxShadow(
                color: const Color(0xFFFFB224).withValues(alpha: 0.32),
                blurRadius: 24,
                offset: const Offset(0, 14),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.asset(
                  product.artworkAssetPath,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '${product.packetCoinAmount} coins',
              style: TextStyle(
                color: selected ? const Color(0xFF2A1600) : Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '₹${product.priceInr}',
              style: TextStyle(
                color: selected
                    ? const Color(0xFF7C2D12)
                    : Colors.white.withValues(alpha: 0.84),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    availableCount > 0
                        ? '$availableCount ready'
                        : product.badgeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected
                          ? const Color(0xFF92400E)
                          : Colors.white.withValues(alpha: 0.64),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (purchaseBusy)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionSummary() {
    final product = _selectedProduct;
    if (product == null) {
      return const SizedBox.shrink();
    }

    final available = _selectedAvailableItem != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Colors.white.withValues(alpha: 0.05),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            available ? 'Packet ready to release' : 'Buy this packet first',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            available
                ? 'This will start a 10-second Golden Dragon rush in ${widget.roomName}. Your packet is consumed only once.'
                : 'After purchase, this packet stays in your inventory until you activate it in an eligible voice room.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.74),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _infoPill('Coins', '${product.packetCoinAmount}'),
              _infoPill('Window', '10s'),
              _infoPill('Tap cap', '50'),
              _infoPill('Available', '${_availableCountFor(product.sku)}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xFF401515),
        border:
            Border.all(color: const Color(0xFFFF8585).withValues(alpha: 0.4)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
      ),
    );
  }

  Widget _infoPill(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.black.withValues(alpha: 0.14),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  List<GoldenDragonProduct> get _products =>
      _inventoryResponse?.products ?? const <GoldenDragonProduct>[];

  GoldenDragonProduct? get _selectedProduct {
    for (final product in _products) {
      if (product.sku == _selectedSku) {
        return product;
      }
    }
    return _products.isNotEmpty ? _products.first : null;
  }

  DragonPacketInventoryItem? get _selectedAvailableItem {
    final product = _selectedProduct;
    if (product == null) return null;
    for (final item
        in _inventoryResponse?.items ?? const <DragonPacketInventoryItem>[]) {
      if (item.productSku == product.sku && item.isAvailable) {
        return item;
      }
    }
    return null;
  }

  int _availableCountFor(String sku) =>
      _inventoryResponse?.summary.availableCounts[sku] ?? 0;

  Future<void> _handlePrimaryAction() async {
    final product = _selectedProduct;
    if (product == null) return;

    if (_selectedAvailableItem == null) {
      await _purchaseProduct(product);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF170808),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        title: const Text(
          'Release Golden Dragon?',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Text(
          '${product.packetCoinAmount} coins will go live in ${widget.roomName} for 10 seconds. Fastest tappers grab more.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.76),
            height: 1.45,
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFFC64A),
              foregroundColor: const Color(0xFF2B1200),
            ),
            child: const Text('Release'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isActivating = true;
      _errorMessage = null;
    });
    try {
      final result = await GoldenDragonService.activateEvent(
        roomId: widget.roomId,
        purchaseInventoryId: _selectedAvailableItem!.id,
        productSku: product.sku,
      );
      widget.onActivated?.call(result.event);
      if (!mounted) return;
      Navigator.of(context).pop(result.event);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _normalizeError(
          error,
          fallback: 'Could not release Golden Dragon',
        );
      });
    } finally {
      if (mounted) {
        setState(() => _isActivating = false);
      }
    }
  }

  Future<void> _purchaseProduct(GoldenDragonProduct product) async {
    setState(() {
      _busySku = product.sku;
      _errorMessage = null;
    });

    try {
      final result = await GoldenDragonService.purchasePacket(
        productSku: product.sku,
        purchaseSource: 'stripe',
      );
      if (!mounted) return;

      if (result.pendingCheckout && result.checkoutUrl.isNotEmpty) {
        final launched = await launchUrl(
          Uri.parse(result.checkoutUrl),
          mode: LaunchMode.externalApplication,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              launched
                  ? 'Complete the checkout and come back to activate your packet.'
                  : 'Checkout is ready. Open the payment link from your browser to continue.',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Golden Dragon packet added to inventory.'),
          ),
        );
      }
      await _loadInventory(showLoader: false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _normalizeError(
          error,
          fallback: 'Could not purchase this packet',
        );
      });
    } finally {
      if (mounted) {
        setState(() => _busySku = null);
      }
    }
  }

  String _normalizeError(Object error, {required String fallback}) {
    final message = error.toString().replaceFirst('Exception: ', '').trim();
    return message.isEmpty ? fallback : message;
  }
}
