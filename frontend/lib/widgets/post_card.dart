import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/post_model.dart';
import '../screens/posts/comments_screen.dart';
import '../utils/constants.dart';
import '../utils/media_url.dart';
import 'post_moment_viewer.dart';
import 'user_avatar.dart';

class PostCard extends StatefulWidget {
  final PostModel post;
  final Future<void> Function(PostModel post)? onLike;
  final VoidCallback? onComment;
  final Future<void> Function(PostModel post)? onDelete;
  final ValueChanged<PostModel>? onPostChanged;
  final bool showActions;
  final bool? showMenu;

  const PostCard({
    super.key,
    required this.post,
    this.onLike,
    this.onComment,
    this.onDelete,
    this.onPostChanged,
    this.showActions = true,
    this.showMenu,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  late PostModel _post;
  bool _isDisposed = false;
  bool _isLiking = false;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
  }

  @override
  void didUpdateWidget(covariant PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.id != widget.post.id ||
        oldWidget.post.updatedAt != widget.post.updatedAt ||
        oldWidget.post.likeCount != widget.post.likeCount ||
        oldWidget.post.commentCount != widget.post.commentCount ||
        oldWidget.post.views != widget.post.views ||
        oldWidget.post.isLikedByUser != widget.post.isLikedByUser) {
      _post = widget.post;
    }
  }

  void _safeSetState(VoidCallback fn) {
    if (!_isDisposed && mounted) {
      setState(fn);
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  Future<void> _handleLike() async {
    if (_isLiking || widget.onLike == null) return;

    final previousPost = _post;
    final nextLiked = !_post.isLikedByUser;
    final nextLikeCount = nextLiked
        ? _post.likeCount + 1
        : (_post.likeCount > 0 ? _post.likeCount - 1 : 0);

    _safeSetState(() {
      _isLiking = true;
      _post = _post.copyWith(
        isLikedByUser: nextLiked,
        likeCount: nextLikeCount,
        updatedAt: DateTime.now(),
      );
    });
    widget.onPostChanged?.call(_post);

    try {
      await widget.onLike!.call(_post);
    } catch (error) {
      _safeSetState(() {
        _post = previousPost;
      });
      widget.onPostChanged?.call(previousPost);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update the like right now.'),
        ),
      );
    } finally {
      _safeSetState(() {
        _isLiking = false;
      });
    }
  }

  Future<void> _openComments() async {
    final updatedPost = await Navigator.push<PostModel>(
      context,
      MaterialPageRoute(
        builder: (context) => CommentsScreen(post: _post),
      ),
    );

    if (updatedPost == null || !mounted) return;

    _safeSetState(() {
      _post = updatedPost;
    });
    widget.onComment?.call();
    widget.onPostChanged?.call(updatedPost);
  }

  Future<void> _handleDelete() async {
    if (widget.onDelete == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete post'),
        content: const Text(
          'This post will be removed from your profile and Social Move.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await widget.onDelete!.call(_post);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not delete the post right now.'),
        ),
      );
    }
  }

  Future<void> _openMediaViewer({int initialIndex = 0}) async {
    if (_post.images.isEmpty) return;

    final updatedPost = await showPostMomentViewer(
      context,
      post: _post,
      initialIndex: initialIndex,
    );

    if (updatedPost == null || !mounted) return;

    _safeSetState(() {
      _post = updatedPost;
    });
    widget.onPostChanged?.call(updatedPost);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showMenu = widget.showMenu ?? widget.onDelete != null;
    final imageCount = _post.images.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
            child: Row(
              children: [
                UserAvatar(
                  imageUrl: _post.userAvatar,
                  username: _post.username,
                  radius: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              _post.username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF2F4F7),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'Lv ${_post.userLevel}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            _post.timeAgo,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          if (_post.isEdited) ...[
                            const SizedBox(width: 8),
                            const Text(
                              'Edited',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (showMenu)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_horiz_rounded),
                    onSelected: (value) {
                      if (value == 'delete') {
                        _handleDelete();
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: Text('Delete post'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          if (_post.content.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                _post.content.trim(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textPrimary,
                  height: 1.55,
                ),
              ),
            ),
          if (imageCount > 0)
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                _post.content.trim().isEmpty ? 0 : 2,
                16,
                14,
              ),
              child: _buildImageGallery(imageCount),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _StatPill(
                  icon: _post.isLikedByUser
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  label: '${_post.likeCount}',
                  color: _post.isLikedByUser
                      ? AppColors.errorRed
                      : AppColors.textSecondary,
                  onTap: widget.showActions && widget.onLike != null && !_isLiking
                      ? _handleLike
                      : null,
                  isLoading: _isLiking,
                ),
                _StatPill(
                  icon: Icons.mode_comment_outlined,
                  label: '${_post.commentCount}',
                  color: AppColors.primaryBlue,
                  onTap: widget.showActions ? _openComments : null,
                ),
                _StatPill(
                  icon: Icons.visibility_outlined,
                  label: '${_post.views}',
                  color: AppColors.textSecondary,
                  onTap: _post.images.isEmpty
                      ? null
                      : () => _openMediaViewer(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageGallery(int imageCount) {
    if (imageCount == 1) {
      return _PostImage(
        imageUrl: _post.images.first['url']?.toString() ?? '',
        borderRadius: BorderRadius.circular(22),
        height: 240,
        onTap: () => _openMediaViewer(),
      );
    }

    return SizedBox(
      height: 208,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: imageCount,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          return SizedBox(
            width: 188,
            child: _PostImage(
              imageUrl: _post.images[index]['url']?.toString() ?? '',
              borderRadius: BorderRadius.circular(22),
              onTap: () => _openMediaViewer(initialIndex: index),
            ),
          );
        },
      ),
    );
  }
}

class _PostImage extends StatelessWidget {
  final String imageUrl;
  final BorderRadius borderRadius;
  final double? height;
  final VoidCallback? onTap;

  const _PostImage({
    required this.imageUrl,
    required this.borderRadius,
    this.height,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedUrl = resolveMediaUrl(imageUrl) ?? '';

    return ClipRRect(
      borderRadius: borderRadius,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: AspectRatio(
            aspectRatio: height == null ? 1 : 1.55,
            child: Container(
              height: height,
              color: const Color(0xFFF4F6F8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: resolvedUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.46),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.open_in_full_rounded,
                            color: Colors.white,
                            size: 14,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Open',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
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

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool isLoading;

  const _StatPill({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                )
              else
                Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
