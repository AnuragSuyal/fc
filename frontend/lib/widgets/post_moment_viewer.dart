import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/post_model.dart';
import '../services/post_service.dart';
import '../utils/constants.dart';
import '../utils/media_url.dart';
import 'user_avatar.dart';

Future<PostModel?> showPostMomentViewer(
  BuildContext context, {
  required PostModel post,
  int initialIndex = 0,
}) {
  return showGeneralDialog<PostModel>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Moment viewer',
    barrierColor: Colors.black.withValues(alpha: 0.92),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, __, ___) => _PostMomentViewer(
      post: post,
      initialIndex: initialIndex,
    ),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _PostMomentViewer extends StatefulWidget {
  final PostModel post;
  final int initialIndex;

  const _PostMomentViewer({
    required this.post,
    required this.initialIndex,
  });

  @override
  State<_PostMomentViewer> createState() => _PostMomentViewerState();
}

class _PostMomentViewerState extends State<_PostMomentViewer> {
  late PostModel _post;
  late final PageController _pageController;
  late int _currentIndex;
  bool _isDisposed = false;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _currentIndex = _boundedInitialIndex(widget.initialIndex);
    _pageController = PageController(initialPage: _currentIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshPost();
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _pageController.dispose();
    super.dispose();
  }

  int _boundedInitialIndex(int value) {
    final maxIndex = _post.images.isEmpty ? 0 : _post.images.length - 1;
    if (value < 0) return 0;
    if (value > maxIndex) return maxIndex;
    return value;
  }

  void _safeSetState(VoidCallback fn) {
    if (!_isDisposed && mounted) {
      setState(fn);
    }
  }

  Future<void> _refreshPost() async {
    if (_isRefreshing || _post.id.isEmpty) return;

    _safeSetState(() => _isRefreshing = true);
    try {
      final refreshed = await PostService.getPostById(_post.id);
      if (refreshed == null) return;

      _safeSetState(() {
        _post = refreshed;
        final lastIndex = _post.images.isEmpty ? 0 : _post.images.length - 1;
        if (_currentIndex > lastIndex) {
          _currentIndex = lastIndex;
        }
      });
    } finally {
      _safeSetState(() => _isRefreshing = false);
    }
  }

  void _close() {
    if (!mounted) return;
    Navigator.of(context).pop(_post);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imageCount = _post.images.length;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        _close();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF05070C),
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: imageCount > 0
                    ? PageView.builder(
                        controller: _pageController,
                        itemCount: imageCount,
                        onPageChanged: (index) {
                          _safeSetState(() => _currentIndex = index);
                        },
                        itemBuilder: (context, index) {
                          final image = _post.images[index];
                          final imageUrl =
                              resolveMediaUrl(image['url']?.toString()) ?? '';

                          return Padding(
                            padding: const EdgeInsets.fromLTRB(12, 82, 12, 180),
                            child: InteractiveViewer(
                              minScale: 1,
                              maxScale: 4,
                              child: Center(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(28),
                                  child: Container(
                                    color: const Color(0xFF111827),
                                    child: CachedNetworkImage(
                                      imageUrl: imageUrl,
                                      fit: BoxFit.contain,
                                      errorWidget: (_, __, ___) => const SizedBox(
                                        height: 280,
                                        child: Center(
                                          child: Icon(
                                            Icons.broken_image_outlined,
                                            color: Colors.white70,
                                            size: 34,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      )
                    : Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 28),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12),
                              ),
                            ),
                            child: Text(
                              _post.content.trim().isEmpty
                                  ? 'No image in this moment.'
                                  : _post.content.trim(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                height: 1.55,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Container(
                    height: 122,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xD9000000),
                          Color(0x80000000),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 14,
                left: 14,
                right: 14,
                child: Row(
                  children: [
                    _GlassIconButton(
                      icon: Icons.arrow_back_rounded,
                      onTap: _close,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Row(
                        children: [
                          UserAvatar(
                            imageUrl: _post.userAvatar,
                            username: _post.username,
                            radius: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _post.username,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${_post.timeAgo} • Moment',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (imageCount > 1)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Text(
                          '${_currentIndex + 1}/$imageCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Positioned(
                left: 14,
                right: 14,
                bottom: 18,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.80),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 20,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _ViewerStatChip(
                            icon: Icons.favorite_rounded,
                            label: '${_post.likeCount}',
                            color: const Color(0xFFFF6A88),
                          ),
                          _ViewerStatChip(
                            icon: Icons.mode_comment_outlined,
                            label: '${_post.commentCount}',
                            color: const Color(0xFF7DD3FC),
                          ),
                          _ViewerStatChip(
                            icon: Icons.visibility_outlined,
                            label: '${_post.views}',
                            color: const Color(0xFFF8FAFC),
                          ),
                        ],
                      ),
                      if (_post.content.trim().isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(
                          _post.content.trim(),
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            height: 1.55,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      if (_isRefreshing) ...[
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: const LinearProgressIndicator(
                            minHeight: 4,
                            backgroundColor: Color(0x33475569),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.primaryBlue,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _GlassIconButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }
}

class _ViewerStatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _ViewerStatChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
