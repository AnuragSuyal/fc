import 'package:flutter/material.dart';

import '../../models/post_model.dart';
import '../../services/post_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/constants.dart';
import '../../widgets/post_card.dart';
import '../../widgets/rounded_scaffold.dart';

class VisitorsScreen extends StatefulWidget {
  final List<dynamic> visitors;

  const VisitorsScreen({super.key, required this.visitors});

  @override
  State<VisitorsScreen> createState() => _VisitorsScreenState();
}

class _VisitorsScreenState extends State<VisitorsScreen> {
  final List<PostModel> _posts = [];

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _isDisposed = false;
  int _currentPage = 1;

  void _safeSetState(VoidCallback fn) {
    if (!_isDisposed && mounted) {
      setState(fn);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadFeed();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  Future<void> _loadFeed({bool reset = false}) async {
    if (reset) {
      _currentPage = 1;
      _hasMore = true;
      _safeSetState(() => _posts.clear());
    }

    if (_isLoadingMore || !_hasMore) return;

    _safeSetState(() {
      if (_currentPage == 1) {
        _isLoading = true;
      } else {
        _isLoadingMore = true;
      }
    });

    final result = await PostService.getFeed(page: _currentPage);
    final posts = List<PostModel>.from(result['posts'] as List? ?? const []);
    final pages = result['pagination']?['pages'] as int? ?? 0;

    _safeSetState(() {
      if (_currentPage == 1) {
        _posts
          ..clear()
          ..addAll(posts);
      } else {
        _posts.addAll(posts);
      }

      _hasMore = pages > _currentPage;
      _isLoading = false;
      _isLoadingMore = false;
    });
  }

  Future<void> _handleLike(PostModel post) async {
    try {
      await PostService.toggleLike(post.id);
    } catch (_) {
      await _loadFeed(reset: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update the like right now.')),
      );
    }
  }

  Future<void> _openCreatePost() async {
    final created = await Navigator.pushNamed(context, '/posts/create');
    if (created == true && mounted) {
      await _loadFeed(reset: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RoundedScaffold(
      title: 'Social Move',
      actions: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: context.mood.outlineSoft),
          ),
          child: IconButton(
            onPressed: _openCreatePost,
            icon: const Icon(Icons.add_rounded),
          ),
        ),
      ],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _posts.isEmpty
              ? _buildEmptyState(context)
              : RefreshIndicator(
                  onRefresh: () => _loadFeed(reset: true),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    itemCount: _posts.length + (_hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _posts.length) {
                        if (_isLoadingMore) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }

                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!_isLoadingMore && _hasMore) {
                            _currentPage++;
                            _loadFeed();
                          }
                        });
                        return const SizedBox(height: 24);
                      }

                      final post = _posts[index];
                      return PostCard(
                        post: post,
                        onLike: () => _handleLike(post),
                        showActions: true,
                        showMenu: false,
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: () => _loadFeed(reset: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(
              Icons.dynamic_feed_rounded,
              color: AppColors.primaryBlue,
              size: 30,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'No friend posts yet',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Social Move shows the posts shared by your friends. When they post, you can like and comment on them here.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _openCreatePost,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Share a post'),
            ),
          ),
        ],
      ),
    );
  }
}
