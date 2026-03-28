import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/post_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/post_service.dart';
import '../../services/socket_service.dart';
import '../../utils/constants.dart';
import '../../widgets/user_avatar.dart';

class CommentsScreen extends StatefulWidget {
  final PostModel post;

  const CommentsScreen({super.key, required this.post});

  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  final _commentController = TextEditingController();
  final _scrollController = ScrollController();

  StreamSubscription<Map<String, dynamic>>? _postSubscription;
  Timer? _refreshDebounce;

  late PostModel _post;
  bool _isDisposed = false;
  bool _isSubmitting = false;
  bool _isRefreshing = false;
  String? _currentUserId;

  List<dynamic> get _comments => _post.comments;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _currentUserId = context.read<AuthProvider>().user?.id;
    _bindRealtime();
    unawaited(_refreshPost(silent: true));
  }

  @override
  void dispose() {
    _isDisposed = true;
    _refreshDebounce?.cancel();
    _postSubscription?.cancel();
    _commentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (!_isDisposed && mounted) {
      setState(fn);
    }
  }

  void _bindRealtime() {
    _postSubscription = SocketService.postStream.listen((event) {
      if (event['postId']?.toString() != _post.id) {
        return;
      }

      _refreshDebounce?.cancel();
      _refreshDebounce = Timer(
        const Duration(milliseconds: 350),
        () => _refreshPost(silent: true),
      );
    });
  }

  Future<void> _refreshPost({bool silent = false}) async {
    if (_isRefreshing) return;

    if (!silent) {
      _safeSetState(() => _isRefreshing = true);
    } else {
      _isRefreshing = true;
    }

    try {
      final refreshed = await PostService.getPostById(
        _post.id,
        trackView: false,
      );
      if (refreshed != null) {
        _safeSetState(() {
          _post = refreshed;
        });
      }
    } finally {
      _safeSetState(() => _isRefreshing = false);
    }
  }

  Future<void> _addComment() async {
    final content = _commentController.text.trim();
    if (content.isEmpty || _isSubmitting) return;

    _safeSetState(() => _isSubmitting = true);

    try {
      final result = await PostService.addComment(_post.id, content);
      final comment = result['comment'];
      final nextCount = result['commentCount'] as int? ?? (_post.commentCount + 1);

      if (comment is Map) {
        final normalizedComment = Map<String, dynamic>.from(comment);
        _safeSetState(() {
          _post = _post.copyWith(
            comments: [..._comments, normalizedComment],
            commentCount: nextCount,
            updatedAt: DateTime.now(),
          );
        });
        _scrollToBottom();
      } else {
        await _refreshPost(silent: true);
      }

      if (!mounted) return;
      _commentController.clear();
      FocusScope.of(context).unfocus();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );
    } finally {
      _safeSetState(() => _isSubmitting = false);
    }
  }

  Future<void> _deleteComment(Map<String, dynamic> comment) async {
    final commentId = comment['_id']?.toString();
    if (commentId == null || commentId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete comment'),
        content: const Text('This comment will be removed from the post.'),
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

    final success = await PostService.deleteComment(_post.id, commentId);
    if (!success) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete that comment.')),
      );
      return;
    }

    _safeSetState(() {
      _post = _post.copyWith(
        comments: _comments.where((item) {
          if (item is! Map) return true;
          return item['_id']?.toString() != commentId;
        }).toList(growable: false),
        commentCount: _post.commentCount > 0 ? _post.commentCount - 1 : 0,
        updatedAt: DateTime.now(),
      );
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 96,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  bool _canDeleteComment(Map<String, dynamic> comment) {
    final commentUser = comment['userId'];
    final commentUserId = commentUser is Map
        ? commentUser['_id']?.toString()
        : commentUser?.toString();

    return commentUserId == _currentUserId || _post.userId == _currentUserId;
  }

  Future<bool> _handleBack() async {
    if (!mounted) return false;
    Navigator.pop(context, _post);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleBack();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => _handleBack(),
          ),
          title: const Text('Comments'),
          actions: [
            if (_isRefreshing)
              const Padding(
                padding: EdgeInsets.only(right: 16),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: _buildPostSummary(),
            ),
            Expanded(
              child: _comments.isEmpty
                  ? _buildEmptyState()
                  : ListView.separated(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                      itemCount: _comments.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final rawComment = _comments[index];
                        if (rawComment is! Map) {
                          return const SizedBox.shrink();
                        }
                        final comment = Map<String, dynamic>.from(rawComment);
                        return _CommentTile(
                          comment: comment,
                          onDelete: _canDeleteComment(comment)
                              ? () => _deleteComment(comment)
                              : null,
                        );
                      },
                    ),
            ),
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: Color(0xFFE6EBF2)),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _commentController,
                        maxLength: 500,
                        minLines: 1,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: 'Write a comment...',
                          counterText: '',
                          filled: true,
                          fillColor: const Color(0xFFF7F9FC),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide:
                                const BorderSide(color: Color(0xFFD7DEE7)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide:
                                const BorderSide(color: Color(0xFFD7DEE7)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: const BorderSide(
                              color: AppColors.primaryBlue,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: _isSubmitting ? null : _addComment,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        foregroundColor: Colors.white,
                        shape: const CircleBorder(),
                        padding: const EdgeInsets.all(14),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.1,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostSummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
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
                Text(
                  _post.username,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _post.content.trim().isNotEmpty
                      ? _post.content.trim()
                      : 'Shared a photo',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F6F8),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${_post.commentCount} comments',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
      children: const [
        Icon(
          Icons.mode_comment_outlined,
          size: 56,
          color: AppColors.textTertiary,
        ),
        SizedBox(height: 14),
        Text(
          'No comments yet',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Start the conversation and your comment will appear here live.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textSecondary,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  final Map<String, dynamic> comment;
  final VoidCallback? onDelete;

  const _CommentTile({
    required this.comment,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final user = comment['userId'] is Map
        ? Map<String, dynamic>.from(comment['userId'] as Map)
        : <String, dynamic>{};
    final username = user['username']?.toString() ?? 'Unknown';
    final avatar = user['avatar']?.toString() ?? '';
    final content = comment['content']?.toString() ?? '';
    final createdAt = comment['createdAt']?.toString();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(
            imageUrl: avatar,
            username: username,
            radius: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        username,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      _timeAgo(createdAt),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  content,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          if (onDelete != null) ...[
            const SizedBox(width: 8),
            IconButton(
              onPressed: onDelete,
              tooltip: 'Delete comment',
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _timeAgo(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final date = DateTime.parse(dateStr);
      final difference = DateTime.now().difference(date);

      if (difference.inDays > 0) {
        return '${difference.inDays}d';
      }
      if (difference.inHours > 0) {
        return '${difference.inHours}h';
      }
      if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m';
      }
      return 'now';
    } catch (_) {
      return '';
    }
  }
}
