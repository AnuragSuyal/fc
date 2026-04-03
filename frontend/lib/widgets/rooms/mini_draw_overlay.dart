import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/mini_draw_model.dart';
import '../../providers/mini_draw_session_controller.dart';

class MiniDrawOverlay extends StatefulWidget {
  const MiniDrawOverlay({
    super.key,
    required this.controller,
    required this.visible,
    required this.onClose,
  });

  final MiniDrawSessionController controller;
  final bool visible;
  final VoidCallback onClose;

  @override
  State<MiniDrawOverlay> createState() => _MiniDrawOverlayState();
}

class _MiniDrawOverlayState extends State<MiniDrawOverlay> {
  static const List<int> _colorPresets = <int>[
    0xFFFFFFFF,
    0xFFFF6B6B,
    0xFFFFA94D,
    0xFFFFD43B,
    0xFF63E6BE,
    0xFF4DABF7,
    0xFF9775FA,
    0xFFFF8FAB,
    0xFF111827,
  ];

  static const List<double> _brushPresets = <double>[2.5, 5, 9];

  Offset? _panelOffset;
  bool _collapsed = false;

  @override
  void initState() {
    super.initState();
    if (widget.visible && widget.controller.summary.isUnlocked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _ensureSnapshotForOpenPanel();
      });
    }
  }

  @override
  void didUpdateWidget(covariant MiniDrawOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.visible && widget.visible) {
      _ensureSnapshotForOpenPanel();
    }
  }

  void _ensureSnapshotForOpenPanel() {
    if (!widget.controller.summary.isUnlocked) return;
    final needsSnapshot = !widget.controller.hasLoadedSnapshot ||
        widget.controller.summary.version !=
            widget.controller.loadedSnapshotVersion;
    if (needsSnapshot) {
      widget.controller.ensureSnapshotLoaded(
        force: !widget.controller.hasLoadedSnapshot,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final topInset = media.padding.top + 72;
    final bottomInset = media.padding.bottom + 108;

    return IgnorePointer(
      ignoring: !widget.visible,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final expandedWidth = math.min(constraints.maxWidth - 20, 344.0);
          final expandedHeight = math.min(
            math.max(250.0, constraints.maxHeight * 0.4),
            constraints.maxHeight - topInset - bottomInset,
          );
          final collapsedWidth = math.min(228.0, constraints.maxWidth - 20);
          final collapsedHeight = 60.0;
          final panelWidth = _collapsed ? collapsedWidth : expandedWidth;
          final panelHeight = _collapsed ? collapsedHeight : expandedHeight;

          _panelOffset ??= Offset(
            constraints.maxWidth - panelWidth - 14,
            topInset,
          );
          _panelOffset = _clampOffset(
            _panelOffset!,
            Size(panelWidth, panelHeight),
            constraints.biggest,
            topInset: topInset,
            bottomInset: bottomInset,
          );

          return Stack(
            children: [
              Positioned(
                left: _panelOffset!.dx,
                top: _panelOffset!.dy,
                child: AnimatedScale(
                  scale: widget.visible ? 1 : 0.92,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    opacity: widget.visible ? 1 : 0,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      width: panelWidth,
                      height: panelHeight,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF171A22),
                            Color(0xFF0E1016),
                          ],
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.34),
                            blurRadius: 30,
                            offset: const Offset(0, 18),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: _collapsed
                            ? _buildCollapsedPanel()
                            : _buildExpandedPanel(),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCollapsedPanel() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _collapsed = false),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              _buildIconBadge(
                const AssetImage('assets/images/mini_draw_board.png'),
                size: 34,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AnimatedBuilder(
                  animation: widget.controller,
                  builder: (context, _) {
                    final summary = widget.controller.summary;
                    final statusLabel = !summary.isUnlocked
                        ? 'Locked'
                        : !summary.enabled
                            ? 'Paused'
                            : widget.controller.isReadOnly
                                ? 'View only'
                                : 'Live';
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Mini Draw',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$statusLabel - v${summary.version}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.62),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              IconButton(
                onPressed: widget.onClose,
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedPanel() {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final summary = controller.summary;

        return Column(
          children: [
            _buildHeader(summary),
            if (controller.errorMessage != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: _buildErrorBanner(controller.errorMessage!),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: !summary.isUnlocked
                    ? _buildUnlockState(controller)
                    : Column(
                        children: [
                          if (controller.canManage) ...[
                            _buildManagerControls(controller),
                            const SizedBox(height: 10),
                          ],
                          Expanded(
                            child: _buildCanvasCard(controller),
                          ),
                          const SizedBox(height: 10),
                          _buildToolRow(controller),
                        ],
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(MiniDrawSessionSummary summary) {
    final statusLabel = !summary.isUnlocked
        ? 'Premium'
        : !summary.enabled
            ? 'Paused'
            : widget.controller.isReadOnly
                ? 'View only'
                : 'Collaborative';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (details) {
        setState(() {
          _panelOffset = (_panelOffset ?? Offset.zero) + details.delta;
        });
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 10, 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.06),
              Colors.white.withValues(alpha: 0.01),
            ],
          ),
          border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
          ),
        ),
        child: Row(
          children: [
            _buildIconBadge(
              const AssetImage('assets/images/mini_draw_board.png'),
              size: 38,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Mini Draw',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$statusLabel - ${summary.strokeCount} strokes',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.62),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => setState(() => _collapsed = true),
              icon: const Icon(Icons.minimize_rounded, color: Colors.white70),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              onPressed: widget.onClose,
              icon: const Icon(Icons.close_rounded, color: Colors.white70),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnlockState(MiniDrawSessionController controller) {
    final summary = controller.summary;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: const Color(0xFF0C111B),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                colors: [Color(0xFF6DE1FF), Color(0xFF7B61FF)],
              ),
            ),
            child: Center(
              child: Image.asset(
                'assets/images/mini_draw_board.png',
                width: 34,
                height: 34,
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Unlock collaborative sketch mode',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            controller.canUnlock
                ? 'Pay ${summary.unlockCostCoins} coins once for this room session. Everyone can then draw based on the room policy you choose.'
                : 'The host can unlock Mini Draw for ${summary.unlockCostCoins} coins. Once active, the room can sketch together here.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: Colors.white.withValues(alpha: 0.04),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Row(
              children: [
                const Icon(Icons.workspace_premium_rounded,
                    color: Color(0xFFFFD43B), size: 18),
                const SizedBox(width: 8),
                Text(
                  '${summary.unlockCostCoins} coins for this session',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: controller.canUnlock && !controller.isUnlocking
                  ? controller.unlockFeature
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF64D2FF),
                foregroundColor: const Color(0xFF071018),
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.08),
                disabledForegroundColor: Colors.white54,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: controller.isUnlocking
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : Text(
                      controller.canUnlock
                          ? 'Unlock Draw for ${summary.unlockCostCoins} coins'
                          : 'Waiting for host unlock',
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManagerControls(MiniDrawSessionController controller) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white.withValues(alpha: 0.03),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Room access',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Switch.adaptive(
                value: controller.summary.enabled,
                onChanged: controller.isSavingSettings
                    ? null
                    : controller.setFeatureEnabled,
                activeThumbColor: const Color(0xFF63E6BE),
                activeTrackColor:
                    const Color(0xFF63E6BE).withValues(alpha: 0.42),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: MiniDrawAccessPolicy.values.map((policy) {
              final isSelected = controller.summary.accessPolicy == policy;
              return ChoiceChip(
                label: Text(_accessPolicyLabel(policy)),
                selected: isSelected,
                onSelected: controller.isSavingSettings
                    ? null
                    : (_) => controller.setAccessPolicy(policy),
                selectedColor: const Color(0xFF64D2FF).withValues(alpha: 0.24),
                backgroundColor: Colors.white.withValues(alpha: 0.04),
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
              );
            }).toList(growable: false),
          ),
        ],
      ),
    );
  }

  Widget _buildCanvasCard(MiniDrawSessionController controller) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF111827),
            Color(0xFF0B1220),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              border: Border(
                bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
              ),
            ),
            child: Row(
              children: [
                _buildStatusPill(
                  controller.isReadOnly
                      ? 'Read only'
                      : controller.canDraw
                          ? 'Live sync'
                          : controller.summary.enabled
                              ? 'Watch only'
                              : 'Paused',
                  color: controller.canDraw
                      ? const Color(0xFF63E6BE)
                      : controller.summary.enabled
                          ? const Color(0xFFFFD43B)
                          : const Color(0xFFFF8787),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'v${controller.summary.version}',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RepaintBoundary(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final canvasSize = constraints.biggest;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: controller.canDraw
                        ? (details) => controller.beginStroke(
                              _normalizePoint(
                                details.localPosition,
                                canvasSize,
                              ),
                            )
                        : null,
                    onPanUpdate: controller.canDraw
                        ? (details) => controller.appendStrokePoint(
                              _normalizePoint(
                                details.localPosition,
                                canvasSize,
                              ),
                            )
                        : null,
                    onPanEnd: controller.canDraw
                        ? (_) => controller.endStroke()
                        : null,
                    onPanCancel: controller.canDraw
                        ? controller.cancelLocalStroke
                        : null,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        const CustomPaint(
                          painter: _MiniDrawGridPainter(),
                        ),
                        ValueListenableBuilder<int>(
                          valueListenable: controller.canvasRevision,
                          builder: (_, __, ___) => CustomPaint(
                            painter: _MiniDrawBoardPainter(
                              strokes: controller.renderedStrokes,
                            ),
                          ),
                        ),
                        if (controller.isLoadingSnapshot)
                          Container(
                            color: Colors.black.withValues(alpha: 0.24),
                            child: const Center(
                              child:
                                  CircularProgressIndicator(strokeWidth: 2.4),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolRow(MiniDrawSessionController controller) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white.withValues(alpha: 0.03),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _buildToolButton(
                selected: controller.selectedTool == MiniDrawToolType.pen,
                enabled: controller.canDraw,
                imagePath: 'assets/images/mini_draw_pencil.png',
                tooltip: 'Pen',
                onTap: () => controller.selectTool(MiniDrawToolType.pen),
              ),
              const SizedBox(width: 8),
              _buildToolButton(
                selected: controller.selectedTool == MiniDrawToolType.eraser,
                enabled: controller.canDraw,
                imagePath: 'assets/images/mini_draw_eraser.png',
                tooltip: 'Eraser',
                onTap: () => controller.selectTool(MiniDrawToolType.eraser),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _colorPresets.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final colorValue = _colorPresets[index];
                      final selected = controller.selectedColorValue ==
                              colorValue &&
                          controller.selectedTool != MiniDrawToolType.eraser;
                      return GestureDetector(
                        onTap: controller.canDraw
                            ? () => controller.selectColorValue(colorValue)
                            : null,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(colorValue),
                            border: Border.all(
                              color: selected
                                  ? const Color(0xFF64D2FF)
                                  : Colors.white.withValues(alpha: 0.12),
                              width: selected ? 2.6 : 1,
                            ),
                            boxShadow: [
                              if (selected)
                                BoxShadow(
                                  color: const Color(0xFF64D2FF)
                                      .withValues(alpha: 0.36),
                                  blurRadius: 12,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              ..._brushPresets.map(
                (size) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _buildBrushButton(
                    size: size,
                    selected:
                        (controller.selectedBrushSize - size).abs() < 0.001,
                    enabled: controller.canDraw,
                    onTap: () => controller.selectBrushSize(size),
                  ),
                ),
              ),
              const Spacer(),
              _buildActionIcon(
                icon: Icons.undo_rounded,
                enabled: controller.canUndoRedo && !controller.isApplyingAction,
                onTap: controller.undo,
              ),
              const SizedBox(width: 6),
              _buildActionIcon(
                icon: Icons.redo_rounded,
                enabled: controller.canUndoRedo && !controller.isApplyingAction,
                onTap: controller.redo,
              ),
              const SizedBox(width: 6),
              _buildToolButton(
                selected: false,
                enabled: controller.canClear && !controller.isApplyingAction,
                imagePath: 'assets/images/mini_draw_clear.png',
                tooltip: 'Clear',
                onTap: () => _confirmClearCanvas(controller),
                iconGlow: const Color(0xFFFF8787),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToolButton({
    required bool selected,
    required bool enabled,
    required String imagePath,
    required String tooltip,
    required VoidCallback onTap,
    Color iconGlow = const Color(0xFF64D2FF),
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: selected
                ? const Color(0xFF64D2FF).withValues(alpha: 0.14)
                : Colors.white.withValues(alpha: 0.04),
            border: Border.all(
              color: selected
                  ? const Color(0xFF64D2FF)
                  : Colors.white.withValues(alpha: 0.08),
            ),
            boxShadow: [
              if (selected)
                BoxShadow(
                  color: iconGlow.withValues(alpha: 0.24),
                  blurRadius: 12,
                ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Opacity(
              opacity: enabled ? 1 : 0.38,
              child: Image.asset(imagePath, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrushButton({
    required double size,
    required bool selected,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: selected
              ? const Color(0xFF64D2FF).withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.04),
          border: Border.all(
            color: selected
                ? const Color(0xFF64D2FF)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: size.clamp(4.0, 12.0).toDouble(),
              height: size.clamp(4.0, 12.0).toDouble(),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: enabled ? 0.95 : 0.36),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              size == _brushPresets.first
                  ? 'Thin'
                  : size == _brushPresets.last
                      ? 'Bold'
                      : 'Mid',
              style: TextStyle(
                color: Colors.white.withValues(alpha: enabled ? 0.9 : 0.38),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionIcon({
    required IconData icon,
    required bool enabled,
    required Future<void> Function() onTap,
  }) {
    return InkWell(
      onTap: enabled ? () => onTap() : null,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.white.withValues(alpha: 0.04),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Icon(
          icon,
          size: 20,
          color: Colors.white.withValues(alpha: enabled ? 0.92 : 0.34),
        ),
      ),
    );
  }

  Widget _buildStatusPill(String label, {required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFF3B1117),
        border:
            Border.all(color: const Color(0xFFFF6B6B).withValues(alpha: 0.32)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: Color(0xFFFF8787), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          GestureDetector(
            onTap: widget.controller.clearError,
            child: const Icon(Icons.close_rounded,
                color: Colors.white70, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildIconBadge(
    AssetImage image, {
    double size = 36,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size / 3),
        gradient: const LinearGradient(
          colors: [Color(0xFF64D2FF), Color(0xFF7B61FF)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Image(image: image, fit: BoxFit.contain),
      ),
    );
  }

  String _accessPolicyLabel(MiniDrawAccessPolicy policy) {
    switch (policy) {
      case MiniDrawAccessPolicy.allParticipants:
        return 'Everyone can draw';
      case MiniDrawAccessPolicy.hostAdmin:
        return 'Host and admins';
      case MiniDrawAccessPolicy.viewOnly:
        return 'View only';
    }
  }

  MiniDrawPoint _normalizePoint(Offset offset, Size size) {
    final x = size.width <= 0
        ? 0.0
        : (offset.dx / size.width).clamp(0.0, 1.0).toDouble();
    final y = size.height <= 0
        ? 0.0
        : (offset.dy / size.height).clamp(0.0, 1.0).toDouble();
    return MiniDrawPoint(x: x, y: y);
  }

  Offset _clampOffset(
    Offset offset,
    Size panelSize,
    Size bounds, {
    required double topInset,
    required double bottomInset,
  }) {
    final maxX = math.max(10.0, bounds.width - panelSize.width - 10);
    final maxY = math.max(
      topInset,
      bounds.height - panelSize.height - bottomInset,
    );
    return Offset(
      offset.dx.clamp(10.0, maxX),
      offset.dy.clamp(topInset, maxY),
    );
  }

  Future<void> _confirmClearCanvas(
    MiniDrawSessionController controller,
  ) async {
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF121722),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Clear canvas?',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          'This removes the shared drawing board for everyone in the room.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.74),
            fontSize: 13,
            height: 1.4,
          ),
        ),
        actions: [
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
              backgroundColor: const Color(0xFFFF6B6B),
              foregroundColor: Colors.white,
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (shouldClear == true) {
      await controller.clearCanvas();
    }
  }
}

class _MiniDrawGridPainter extends CustomPainter {
  const _MiniDrawGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..strokeWidth = 1;
    const spacing = 22.0;

    for (double x = spacing; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = spacing; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MiniDrawGridPainter oldDelegate) => false;
}

class _MiniDrawBoardPainter extends CustomPainter {
  const _MiniDrawBoardPainter({
    required this.strokes,
  });

  final List<MiniDrawStroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());

    for (final stroke in strokes) {
      if (stroke.points.isEmpty || !stroke.isVisible) continue;
      final paint = Paint()
        ..color = stroke.toolType == MiniDrawToolType.eraser
            ? const Color(0x00000000)
            : Color(stroke.colorValue)
        ..strokeWidth = stroke.thickness
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..blendMode = stroke.toolType == MiniDrawToolType.eraser
            ? BlendMode.clear
            : BlendMode.srcOver;

      final path = Path();
      final firstPoint = stroke.points.first.toOffset(size);
      if (stroke.points.length == 1) {
        final pointPaint = Paint()
          ..color = stroke.toolType == MiniDrawToolType.eraser
              ? const Color(0x00000000)
              : Color(stroke.colorValue)
          ..style = PaintingStyle.fill
          ..blendMode = stroke.toolType == MiniDrawToolType.eraser
              ? BlendMode.clear
              : BlendMode.srcOver;
        canvas.drawCircle(firstPoint, stroke.thickness / 2, pointPaint);
        continue;
      }

      path.moveTo(firstPoint.dx, firstPoint.dy);
      for (int index = 1; index < stroke.points.length; index++) {
        final current = stroke.points[index].toOffset(size);
        final previous = stroke.points[index - 1].toOffset(size);
        final midpoint = Offset(
          (previous.dx + current.dx) / 2,
          (previous.dy + current.dy) / 2,
        );
        path.quadraticBezierTo(
          previous.dx,
          previous.dy,
          midpoint.dx,
          midpoint.dy,
        );
      }
      final lastPoint = stroke.points.last.toOffset(size);
      path.lineTo(lastPoint.dx, lastPoint.dy);
      canvas.drawPath(path, paint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MiniDrawBoardPainter oldDelegate) {
    return oldDelegate.strokes != strokes;
  }
}
