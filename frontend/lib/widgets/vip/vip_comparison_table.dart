import 'package:flutter/material.dart';

import '../../models/vip_model.dart';

class VipComparisonTable extends StatelessWidget {
  final List<VipComparisonRow> rows;
  final List<VipTierModel> tiers;
  final String highlightedTierId;

  const VipComparisonTable({
    super.key,
    required this.rows,
    required this.tiers,
    required this.highlightedTierId,
  });

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty || tiers.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Compare Tiers',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.12),
              ),
            ),
            child: DataTable(
              headingRowHeight: 52,
              dataRowMinHeight: 46,
              columns: [
                const DataColumn(label: Text('Benefit')),
                ...tiers.map(
                  (tier) => DataColumn(
                    label: Text(
                      tier.shortLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: tier.tierId == highlightedTierId
                            ? _parseColor(tier.ui.accent)
                            : null,
                      ),
                    ),
                  ),
                ),
              ],
              rows: rows
                  .map(
                    (row) => DataRow(
                      cells: [
                        DataCell(Text(row.label)),
                        ...tiers.map(
                          (tier) => DataCell(
                            Text(
                              _displayValue(row, tier.tierId),
                              style: TextStyle(
                                color: tier.tierId == highlightedTierId
                                    ? _parseColor(tier.ui.accent)
                                    : null,
                                fontWeight: tier.tierId == highlightedTierId
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ),
      ],
    );
  }

  String _displayValue(VipComparisonRow row, String tierId) {
    final match = row.values.where((value) => value.tierId == tierId);
    if (match.isEmpty) return '-';
    final value = match.first.value;
    if (value == null) return '-';
    switch (row.type) {
      case 'percent':
        return '${value.toString()}%';
      case 'coins':
        return '${value.toString()} coins';
      case 'level':
        final parsed = int.tryParse(value.toString()) ?? 0;
        return parsed <= 0 ? '-' : 'Lv $parsed';
      default:
        final text = value.toString().replaceAll('_', ' ').trim();
        if (text.isEmpty) return '-';
        return text
            .split(' ')
            .map((word) => word.isEmpty
                ? word
                : '${word[0].toUpperCase()}${word.substring(1)}')
            .join(' ');
    }
  }

  static Color _parseColor(String hex) {
    final value = int.tryParse(hex.replaceFirst('#', ''), radix: 16) ??
        0x8B5CF6;
    return Color(value + 0xFF000000);
  }
}
