import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/post_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/post_service.dart';
import '../../services/socket_service.dart';
import '../../widgets/post_card.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final List<PostModel> _posts = [];

  StreamSubscription<Map<String, dynamic>>? _postSubscription;
  Timer? _refreshDebounce;

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _isDisposed = false;
  int _currentPage = 1;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _currentUserId = context.read<AuthProvider>().user?.id;
    _bindRealtime();
    _loadFeed();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _postSubscription?.cancel();
    _refreshDebounce?.cancel();
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (!_isDisposed && mounted) {
      setState(fn);
    }
  }

  void _bindRealtime() {
    _postSubscription = SocketService.postStream.listen((event) {
      if (!_shouldRefreshForEvent(event)) return;

      _refreshDebounce?.cancel();
      _refreshDebounce = Timer(
        const Duration(milliseconds: 450),
        () => _loadFeed(reset: true, silent: true),
      );
    });
  }

  bool _shouldRefreshForEvent(Map<String, dynamic> event) {
    final action = event['action']?.toString() ?? '';
    final userId = event['userId']?.toString() ?? '';
    final postId = event['postId']?.toString() ?? '';

    if (action == 'create') {
      return true;
    }

    return _posts.any(
      (post) => post.id == postId || post.userId == userId,
    );
  }

  Future<void> _loadFeed({bool reset = false, bool silent = false}) async {
    if (reset) {
      _currentPage = 1;
      _hasMore = true;
      _safeSetState(() => _posts.clear());
    }

    if (_isLoadingMore || !_hasMore) return;

    _safeSetState(() {
      if (_currentPage == 1 && !silent) {
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
    await PostService.toggleLike(post.id);
  }

  Future<void> _handleDelete(PostModel post) async {
    final success = await PostService.deletePost(post.id);
    if (success) {
      _safeSetState(() {
        _posts.removeWhere((item) => item.id == post.id);
      });
    } else {
      throw Exception('Could not delete the post.');
    }
  }

  void _upsertPost(PostModel updatedPost) {
    final index = _posts.indexWhere((post) => post.id == updatedPost.id);
    if (index == -1) return;

    _safeSetState(() {
      _posts[index] = updatedPost;
    });
  }

  Future<void> _openCreatePost() async {
    final created = await Navigator.pushNamed(context, '/posts/create');
    if (created == true && mounted) {
      await _loadFeed(reset: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Feed'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: _openCreatePost,
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
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (_hasMore && !_isLoadingMore) {
                        _currentPage += 1;
                        _loadFeed(silent: true);
                      }
                    });
                    return const SizedBox(height: 20);
                  }

                  final post = _posts[index];
                  return PostCard(
                    post: post,
                    onLike: _handleLike,
                    onDelete:
                        post.userId == _currentUserId ? _handleDelete : null,
                    onPostChanged: _upsertPost,
                    showMenu: post.userId == _currentUserId,
                  );
                },
              ),
            ),
    );
  }
}
