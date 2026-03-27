import 'package:flutter/material.dart';

import '../models/post_model.dart';
import '../screens/posts/comments_screen.dart';
import '../theme/app_theme.dart';
import '../utils/constants.dart';
import '../widgets/user_avatar.dart';

class PostCard extends StatefulWidget {
  final PostModel post;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onDelete;
  final bool showActions;
  final bool? showMenu;

  const PostCard({
    super.key,
    required this.post,
    this.onLike,
    this.onComment,
    this.onDelete,
    this.showActions = true,
    this.showMenu,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool _isLiked = false;
  int _likeCount = 0;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.post.isLikedByUser;
    _likeCount = widget.post.likeCount;
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

  void _handleLike() {
    _safeSetState(() {
      if (_isLiked) {
        _likeCount--;
      } else {
        _likeCount++;
      }
      _isLiked = !_isLiked;
    });
    widget.onLike?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mood = context.mood;
    final showMenu = widget.showMenu ?? widget.showActions;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, mood.surfaceSoft],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  UserAvatar(
                    imageUrl: widget.post.userAvatar,
                    username: widget.post.username,
                    radius: 20,
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
                                widget.post.username,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
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
                                color: AppColors.accentYellow
                                    .withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'Lv ${widget.post.userLevel}',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          widget.post.timeAgo,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (showMenu)
                    PopupMenuButton(
                      icon: const Icon(Icons.more_horiz_rounded),
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete'),
                        ),
                      ],
                      onSelected: (value) {
                        if (value == 'delete') {
                          widget.onDelete?.call();
                        }
                      },
                    ),
                ],
              ),
            ),
            if (widget.post.content.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  widget.post.content,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            if (widget.post.images.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 220,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.post.images.length,
                  itemBuilder: (context, index) {
                    final image = widget.post.images[index];
                    return Container(
                      width: 220,
                      margin: EdgeInsets.only(
                        left: index == 0 ? 16 : 0,
                        right: 16,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        color: mood.surfaceSoft,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Image.network(
                          image['url'] ?? '',
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Center(
                            child: Icon(
                              Icons.broken_image_outlined,
                              color: AppColors.textSecondary
                                  .withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  _statChip(
                    context,
                    icon: _isLiked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    label: '$_likeCount',
                    color:
                        _isLiked ? AppColors.errorRed : AppColors.primaryBlue,
                  ),
                  const SizedBox(width: 10),
                  _statChip(
                    context,
                    icon: Icons.chat_bubble_outline_rounded,
                    label: '${widget.post.commentCount}',
                    color: AppColors.secondaryBlue,
                  ),
                  const Spacer(),
                  Text(
                    '${widget.post.views} views',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (widget.showActions)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: _handleLike,
                        icon: Icon(
                          _isLiked
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: _isLiked
                              ? AppColors.errorRed
                              : AppColors.textPrimary,
                        ),
                        label: Text(_isLiked ? 'Loved it' : 'Love'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  CommentsScreen(post: widget.post),
                            ),
                          );
                        },
                        icon: const Icon(Icons.mode_comment_outlined),
                        label: const Text('Comment'),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
  }) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
