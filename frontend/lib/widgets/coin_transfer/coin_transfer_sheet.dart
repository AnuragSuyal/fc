import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/coin_transfer_model.dart';

typedef CoinTransferPreviewLoader = Future<CoinTransferPreview> Function(
  int amount,
);
typedef CoinTransferSubmitter = Future<CoinTransferSendResult> Function(
  int amount,
);

Future<CoinTransferSendResult?> showCoinTransferComposerSheet({
  required BuildContext context,
  required CoinTransferEligibility eligibility,
  required String receiverName,
  required CoinTransferPreviewLoader onPreview,
  required CoinTransferSubmitter onSubmit,
}) {
  return showModalBottomSheet<CoinTransferSendResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => CoinTransferComposerSheet(
      eligibility: eligibility,
      receiverName: receiverName,
      onPreview: onPreview,
      onSubmit: onSubmit,
    ),
  );
}

class CoinTransferComposerSheet extends StatefulWidget {
  final CoinTransferEligibility eligibility;
  final String receiverName;
  final CoinTransferPreviewLoader onPreview;
  final CoinTransferSubmitter onSubmit;

  const CoinTransferComposerSheet({
    super.key,
    required this.eligibility,
    required this.receiverName,
    required this.onPreview,
    required this.onSubmit,
  });

  @override
  State<CoinTransferComposerSheet> createState() =>
      _CoinTransferComposerSheetState();
}

class _CoinTransferComposerSheetState extends State<CoinTransferComposerSheet> {
  late final TextEditingController _amountController;
  Timer? _previewDebounce;
  int _amount = 0;
  bool _isCustomAmount = false;
  bool _isLoadingPreview = false;
  bool _isSubmitting = false;
  String _inlineError = '';
  CoinTransferValidation? _validation;
  CoinTransferBreakdown? _breakdown;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController();
    final minAmount = widget.eligibility.limits.minTransferAmount;
    _setAmount(minAmount, useCustomAmount: false, triggerPreview: true);
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    _amountController.dispose();
    super.dispose();
  }

  List<int> get _quickAmounts {
    final values = <int>{
      widget.eligibility.limits.minTransferAmount,
      250,
      500,
      1000,
    }.toList()
      ..sort();
    return values;
  }

  bool get _canSubmit {
    if (_isSubmitting || _isLoadingPreview) {
      return false;
    }
    if (_amount < widget.eligibility.limits.minTransferAmount) {
      return false;
    }
    return _validation?.canSend == true;
  }

  String get _receiverDisplayName {
    final trimmed = widget.receiverName.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
    return 'your friend';
  }

  void _setAmount(
    int amount, {
    required bool useCustomAmount,
    bool triggerPreview = false,
  }) {
    setState(() {
      _amount = amount;
      _isCustomAmount = useCustomAmount;
      if (_isCustomAmount) {
        _amountController.text = amount > 0 ? '$amount' : '';
      } else {
        _amountController.clear();
      }
      _inlineError = '';
      _breakdown = CoinTransferBreakdown.calculate(
        amount: amount > 0 ? amount : 0,
        feePercentages: widget.eligibility.limits.feePercentages,
      );
    });

    if (triggerPreview) {
      _schedulePreview();
    }
  }

  void _schedulePreview() {
    _previewDebounce?.cancel();
    if (_amount <= 0) {
      setState(() {
        _validation = null;
      });
      return;
    }

    _previewDebounce = Timer(const Duration(milliseconds: 220), () async {
      if (!mounted) return;
      setState(() {
        _isLoadingPreview = true;
        _inlineError = '';
      });

      try {
        final preview = await widget.onPreview(_amount);
        if (!mounted) return;
        setState(() {
          _validation = preview.validation;
          _breakdown = preview.breakdown;
          _isLoadingPreview = false;
        });
      } catch (error) {
        if (!mounted) return;
        setState(() {
          _validation = CoinTransferValidation(
            canSend: false,
            reasons: const <CoinTransferReason>[],
          );
          _inlineError =
              'We could not refresh the transfer preview. Check your connection and try again.';
          _isLoadingPreview = false;
        });
      }
    });
  }

  Future<void> _handleSubmit() async {
    if (!_canSubmit) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _inlineError = '';
    });

    try {
      final result = await widget.onSubmit(_amount);
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _inlineError = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final theme = Theme.of(context);
    final breakdown = _breakdown ??
        CoinTransferBreakdown.calculate(
          amount: _amount > 0 ? _amount : 0,
          feePercentages: widget.eligibility.limits.feePercentages,
        );
    final reasons = _validation?.reasons ?? const <CoinTransferReason>[];
    final previewError = _inlineError.isNotEmpty
        ? _inlineError
        : (reasons.isNotEmpty ? reasons.first.message : '');

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: mediaQuery.viewInsets.bottom + 16,
        ),
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14),
                  blurRadius: 30,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.toll_rounded,
                          color: Color(0xFF1D4ED8),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Send Coins',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Transfer coins to $_receiverDisplayName in this private chat.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: const Color(0xFF64748B),
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFF8FAFC),
                          Color(0xFFEFF6FF),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFDCE7F6)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Available balance',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: const Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${widget.eligibility.currentBalance} coins',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '$_receiverDisplayName receives ${widget.eligibility.limits.feePercentages.receiverPercentage}%. Friend Circle keeps ${widget.eligibility.limits.feePercentages.platformPercentage}% as the platform fee.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF475569),
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Choose amount',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final value in _quickAmounts)
                        _AmountChip(
                          amount: value,
                          selected: !_isCustomAmount && _amount == value,
                          onTap: () => _setAmount(
                            value,
                            useCustomAmount: false,
                            triggerPreview: true,
                          ),
                        ),
                      _CustomAmountChip(
                        selected: _isCustomAmount,
                        onTap: () => _setAmount(
                          _amount > 0 ? _amount : 0,
                          useCustomAmount: true,
                          triggerPreview: false,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _amountController,
                    enabled: _isCustomAmount && !_isSubmitting,
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      if (!_isCustomAmount) return;
                      final parsed = int.tryParse(value.trim()) ?? 0;
                      setState(() {
                        _amount = parsed;
                        _inlineError = '';
                        _breakdown = CoinTransferBreakdown.calculate(
                          amount: parsed > 0 ? parsed : 0,
                          feePercentages:
                              widget.eligibility.limits.feePercentages,
                        );
                      });
                      _schedulePreview();
                    },
                    decoration: InputDecoration(
                      labelText: 'Custom amount',
                      hintText:
                          'Minimum ${widget.eligibility.limits.minTransferAmount}',
                      prefixIcon: const Icon(Icons.currency_exchange_rounded),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(color: Color(0xFF93C5FD)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _PreviewRow(
                          label: 'You spend',
                          value: '${breakdown.senderSpend}',
                          valueColor: Colors.white,
                        ),
                        const SizedBox(height: 10),
                        _PreviewRow(
                          label: 'Friend receives',
                          value: '${breakdown.receiverAmount}',
                          valueColor: const Color(0xFF86EFAC),
                        ),
                        const SizedBox(height: 10),
                        _PreviewRow(
                          label: 'Friend Circle fee',
                          value: '${breakdown.platformFee}',
                          valueColor: const Color(0xFFFDE68A),
                        ),
                      ],
                    ),
                  ),
                  if (_isLoadingPreview) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(minHeight: 3),
                  ],
                  if (previewError.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFFED7AA)),
                      ),
                      child: Text(
                        previewError,
                        style: const TextStyle(
                          color: Color(0xFF9A3412),
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isSubmitting
                              ? null
                              : () => Navigator.of(context).maybePop(),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _canSubmit ? _handleSubmit : null,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            backgroundColor: const Color(0xFF111827),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: _isSubmitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Send Coins'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AmountChip extends StatelessWidget {
  final int amount;
  final bool selected;
  final VoidCallback onTap;

  const _AmountChip({
    required this.amount,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text('$amount'),
      selected: selected,
      onSelected: (_) => onTap(),
      labelStyle: TextStyle(
        color: selected ? Colors.white : const Color(0xFF111827),
        fontWeight: FontWeight.w700,
      ),
      selectedColor: const Color(0xFF1D4ED8),
      backgroundColor: const Color(0xFFF8FAFC),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
    );
  }
}

class _CustomAmountChip extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;

  const _CustomAmountChip({
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: const Text('Custom'),
      selected: selected,
      onSelected: (_) => onTap(),
      labelStyle: TextStyle(
        color: selected ? Colors.white : const Color(0xFF111827),
        fontWeight: FontWeight.w700,
      ),
      selectedColor: const Color(0xFF111827),
      backgroundColor: const Color(0xFFF8FAFC),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _PreviewRow({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
      ],
    );
  }
}
