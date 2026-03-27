import 'package:flutter/foundation.dart';
import '../models/message_model.dart';
import 'api_service.dart';

class MessageService {
  // Get all conversations
  static Future<List<ConversationModel>> getConversations() async {
    try {
      final response = await ApiService.get('/messages/conversations');
      return _parseConversationList(response);
    } catch (e) {
      debugPrint('Error getting conversations: $e');
      return [];
    }
  }

  // Get direct messages with a user
  static Future<Map<String, dynamic>> getDirectMessages(
    String userId, {
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final response = await ApiService.get(
        '/messages/dm/$userId?page=$page&limit=$limit',
      );
      final messages = await _parseMessageList(response['messages']);

      return {
        'messages': messages,
        'pagination': response['pagination'],
      };
    } catch (e) {
      debugPrint('Error getting direct messages: $e');
      return {'messages': [], 'pagination': null};
    }
  }

  // Get room messages
  static Future<Map<String, dynamic>> getRoomMessages(
    String roomId, {
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final response = await ApiService.get(
        '/messages/room/$roomId?page=$page&limit=$limit',
      );
      final messages = await _parseMessageList(response['messages']);

      return {
        'messages': messages,
        'pagination': response['pagination'],
      };
    } catch (e) {
      debugPrint('Error getting room messages: $e');
      return {'messages': [], 'pagination': null};
    }
  }

  // Get group messages
  static Future<Map<String, dynamic>> getGroupMessages(
    String groupId, {
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final response = await ApiService.get(
        '/messages/group/$groupId?page=$page&limit=$limit',
      );
      final messages = await _parseMessageList(response['messages']);

      return {
        'messages': messages,
        'pagination': response['pagination'],
      };
    } catch (e) {
      debugPrint('Error getting group messages: $e');
      return {'messages': [], 'pagination': null};
    }
  }

  // Send direct message
  static Future<MessageModel?> sendDirectMessage({
    required String recipientId,
    required String content,
    String? replyTo,
  }) async {
    try {
      final response = await ApiService.post('/messages/dm', {
        'recipientId': recipientId,
        'content': content,
        if (replyTo != null) 'replyTo': replyTo,
      });
      return MessageModel.fromJson(response);
    } catch (e) {
      debugPrint('Error sending DM: $e');
      return null;
    }
  }

  // Send room message
  static Future<MessageModel?> sendRoomMessage({
    required String roomId,
    required String content,
    String type = 'text',
    String? replyTo,
  }) async {
    try {
      final response = await ApiService.post('/messages/room', {
        'roomId': roomId,
        'content': content,
        'type': type,
        if (replyTo != null) 'replyTo': replyTo,
      });
      return MessageModel.fromJson(response);
    } catch (e) {
      debugPrint('Error sending room message: $e');
      return null;
    }
  }

  // Send group message
  static Future<MessageModel?> sendGroupMessage({
    required String groupId,
    required String content,
    String? replyTo,
  }) async {
    try {
      final response = await ApiService.post('/messages/group', {
        'groupId': groupId,
        'content': content,
        if (replyTo != null) 'replyTo': replyTo,
      });
      return MessageModel.fromJson(response);
    } catch (e) {
      debugPrint('Error sending group message: $e');
      return null;
    }
  }

  // Add reaction
  static Future<bool> addReaction(String messageId, String reaction) async {
    try {
      await ApiService.post('/messages/$messageId/react', {
        'reaction': reaction,
      });
      return true;
    } catch (e) {
      debugPrint('Error adding reaction: $e');
      return false;
    }
  }

  // Delete message
  static Future<bool> deleteMessage(String messageId) async {
    try {
      await ApiService.delete('/messages/$messageId');
      return true;
    } catch (e) {
      debugPrint('Error deleting message: $e');
      return false;
    }
  }

  // Mark messages as read
  static Future<bool> markAsRead(String userId) async {
    try {
      await ApiService.post('/messages/dm/$userId/read', {});
      return true;
    } catch (e) {
      debugPrint('Error marking as read: $e');
      return false;
    }
  }

  static Future<List<ConversationModel>> _parseConversationList(
    dynamic response,
  ) async {
    final normalized = _normalizeMapList(response);
    if (normalized.isEmpty) {
      return const [];
    }

    if (normalized.length < 24) {
      return normalized.map(ConversationModel.fromJson).toList(growable: false);
    }

    return compute(_parseConversationListIsolate, normalized);
  }

  static Future<List<MessageModel>> _parseMessageList(dynamic rawList) async {
    final normalized = _normalizeMapList(rawList);
    if (normalized.isEmpty) {
      return const [];
    }

    if (normalized.length < 32) {
      return normalized.map(MessageModel.fromJson).toList(growable: false);
    }

    return compute(_parseMessageListIsolate, normalized);
  }

  static List<Map<String, dynamic>> _normalizeMapList(dynamic rawList) {
    if (rawList is! List) {
      return const [];
    }

    return rawList
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }
}

List<ConversationModel> _parseConversationListIsolate(
  List<Map<String, dynamic>> raw,
) {
  return raw.map(ConversationModel.fromJson).toList(growable: false);
}

List<MessageModel> _parseMessageListIsolate(List<Map<String, dynamic>> raw) {
  return raw.map(MessageModel.fromJson).toList(growable: false);
}
