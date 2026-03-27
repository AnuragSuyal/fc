import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class RoundedScaffold extends StatelessWidget {
  final String? title;
  final Widget? titleWidget;
  final Widget body;
  final Widget? floatingActionButton;
  final List<Widget>? actions;
  final bool showBackButton;

  const RoundedScaffold({
    super.key,
    this.title,
    this.titleWidget,
    required this.body,
    this.floatingActionButton,
    this.actions,
    this.showBackButton = true,
  }) : assert(title != null || titleWidget != null,
            'Either title or titleWidget must be provided');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mood = context.mood;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Container(
        decoration: BoxDecoration(gradient: mood.shellGradient),
        child: Stack(
          children: [
            Positioned(
              top: -70,
              right: -18,
              child: _GlowBubble(
                color: mood.sun.withValues(alpha: 0.22),
                size: 170,
              ),
            ),
            Positioned(
              top: 84,
              left: -32,
              child: _GlowBubble(
                color: mood.sky.withValues(alpha: 0.18),
                size: 132,
              ),
            ),
            SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                    child: Row(
                      children: [
                        if (showBackButton)
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: mood.outlineSoft),
                            ),
                            child: IconButton(
                              onPressed: () => Navigator.of(context).maybePop(),
                              icon: Icon(
                                Icons.arrow_back_rounded,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ),
                        if (showBackButton) const SizedBox(width: 12),
                        Expanded(
                          child: titleWidget ??
                              Text(
                                title!,
                                style: theme.textTheme.headlineSmall,
                              ),
                        ),
                        if (actions != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: actions!,
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface.withValues(
                          alpha:
                              theme.brightness == Brightness.dark ? 0.94 : 0.9,
                        ),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(34),
                        ),
                        border: Border.all(color: mood.outlineSoft),
                        boxShadow: [
                          BoxShadow(
                            color: mood.shadow,
                            blurRadius: 28,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          const SizedBox(height: 12),
                          Container(
                            width: 54,
                            height: 5,
                            decoration: BoxDecoration(
                              color: mood.outlineSoft,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(34),
                              ),
                              child: body,
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
      floatingActionButton: floatingActionButton,
    );
  }
}

class _GlowBubble extends StatelessWidget {
  const _GlowBubble({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
        ),
      ),
    );
  }
}
