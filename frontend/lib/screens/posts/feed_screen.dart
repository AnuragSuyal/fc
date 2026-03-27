import 'package:flutter/material.dart';
import '../../services/post_service.dart';
import '../../models/post_model.dart';
import '../../widgets/post_card.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  List<PostModel> _posts = [];
  bool _isLoading = true;
  int _currentPage = 1;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _loadFeed();
  }

  Future<void> _loadFeed({bool reset = false}) async {
    if (reset) {
      _currentPage = 1;
      _hasMore = true;
      setState(() => _posts = []);
    }

    if (!_hasMore || _isLoadingMore) return;

    setState(() {
      if (_currentPage == 1) {
        _isLoading = true;
      } else {
        _isLoadingMore = true;
      }
    });

    final result = await PostService.getFeed(page: _currentPage);

    setState(() {
      if (_currentPage == 1) {
        _posts = result['posts'];
      } else {
        _posts.addAll(result['posts']);
      }

      _hasMore = (result['pagination']?['pages'] ?? 0) > _currentPage;
      _isLoading = false;
      _isLoadingMore = false;
    });
  }

  Future<void> _handleLike(PostModel post) async {
    try {
      await PostService.toggleLike(post.id);
      // UI already updated optimistically
    } catch (e) {
      // Revert on error
      _loadFeed(reset: true);
    }
  }

  Future<void> _handleDelete(PostModel post) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Post'),
        content: const Text('Are you sure you want to delete this post?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await PostService.deletePost(post.id);
      if (success) {
        setState(() {
          _posts.removeWhere((p) => p.id == post.id);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Feed'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              final created =
                  await Navigator.pushNamed(context, '/posts/create');
              if (created == true && mounted) {
                await _loadFeed(reset: true);
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _loadFeed(reset: true),
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _posts.length + (_hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _posts.length) {
                    if (_isLoadingMore) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    } else {
                      _currentPage++;
                      _loadFeed();
                      return const SizedBox.shrink();
                    }
                  }

                  final post = _posts[index];
                  return PostCard(
                    post: post,
                    onLike: () => _handleLike(post),
                    onDelete: () => _handleDelete(post),
                  );
                },
              ),
            ),
    );
  }
}
