import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/post_model.dart';
import 'api_service.dart';
import 'upload_service.dart';

class PostService {
  // Get feed
  static Future<Map<String, dynamic>> getFeed(
      {int page = 1, int limit = 20}) async {
    try {
      final response =
          await ApiService.get('/posts/feed?page=$page&limit=$limit');

      final posts = (response['posts'] as List)
          .map((p) => PostModel.fromJson(p))
          .toList();

      return {
        'posts': posts,
        'pagination': response['pagination'],
      };
    } catch (e) {
      debugPrint('Error getting feed: $e');
      return {'posts': <PostModel>[], 'pagination': null};
    }
  }

  // Get user posts
  static Future<Map<String, dynamic>> getUserPosts(String userId,
      {int page = 1, int limit = 20}) async {
    try {
      final response =
          await ApiService.get('/posts/user/$userId?page=$page&limit=$limit');

      final posts = (response['posts'] as List)
          .map((p) => PostModel.fromJson(p))
          .toList();

      return {
        'posts': posts,
        'pagination': response['pagination'],
      };
    } catch (e) {
      debugPrint('Error getting user posts: $e');
      return {'posts': <PostModel>[], 'pagination': null};
    }
  }

  // Get single post
  static Future<PostModel?> getPostById(String postId) async {
    try {
      final response = await ApiService.get('/posts/$postId');
      return PostModel.fromJson(response);
    } catch (e) {
      debugPrint('Error getting post: $e');
      return null;
    }
  }

  static Future<List<String>> uploadImages(List<File> images) async {
    final urls = <String>[];

    for (final image in images) {
      final upload = await UploadService.uploadImage(image.path);
      final url = upload['url']?.toString();
      if (url == null || url.isEmpty) {
        throw Exception('Image upload failed');
      }
      urls.add(url);
    }

    return urls;
  }

  static Future<PostModel?> createPost({
    required String content,
    List<File>? imageFiles,
    String type = 'normal',
    Map<String, dynamic>? metadata,
  }) async {
    try {
      if (content.trim().isEmpty) {
        throw Exception('Post content cannot be empty');
      }

      List<Map<String, dynamic>> imageUrls = [];

      // Upload images first if any
      if (imageFiles != null && imageFiles.isNotEmpty) {
        final urls = await uploadImages(imageFiles);
        imageUrls = urls.map((url) => {'url': url}).toList();
      }

      final response = await ApiService.post('/posts', {
        'content': content,
        'images': imageUrls,
        'type': type,
        'metadata': metadata ?? {},
      });
      return PostModel.fromJson(response);
    } catch (e) {
      debugPrint('Error creating post: $e');
      rethrow;
    }
  }

  // Like/unlike post
  static Future<Map<String, dynamic>> toggleLike(String postId) async {
    try {
      final response = await ApiService.post('/posts/$postId/like', {});
      return response;
    } catch (e) {
      debugPrint('Error toggling like: $e');
      rethrow;
    }
  }

  // Add comment
  static Future<Map<String, dynamic>> addComment(
      String postId, String content) async {
    try {
      final response = await ApiService.post('/posts/$postId/comments', {
        'content': content,
      });
      return response;
    } catch (e) {
      debugPrint('Error adding comment: $e');
      rethrow;
    }
  }

  // Delete comment
  static Future<bool> deleteComment(String postId, String commentId) async {
    try {
      await ApiService.delete('/posts/$postId/comments/$commentId');
      return true;
    } catch (e) {
      debugPrint('Error deleting comment: $e');
      return false;
    }
  }

  // Update post
  static Future<PostModel?> updatePost(String postId,
      {String? content, List<Map<String, dynamic>>? images}) async {
    try {
      final response = await ApiService.put('/posts/$postId', {
        if (content != null) 'content': content,
        if (images != null) 'images': images,
      });
      return PostModel.fromJson(response);
    } catch (e) {
      debugPrint('Error updating post: $e');
      return null;
    }
  }

  // Delete post
  static Future<bool> deletePost(String postId) async {
    try {
      await ApiService.delete('/posts/$postId');
      return true;
    } catch (e) {
      debugPrint('Error deleting post: $e');
      return false;
    }
  }
}
