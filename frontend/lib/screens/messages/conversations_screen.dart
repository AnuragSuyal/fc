import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/message_service.dart';
import '../../services/socket_service.dart';
import '../../models/message_model.dart';
import '../../providers/auth_provider.dart';
import '../../utils/constants.dart';
import 'chat_screen.dart';
import '../../widgets/user_avatar.dart';

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  List<ConversationModel> _conversations = [];
  final List<StreamSubscription> _subs = [];
  Timer? _refreshDebounce;
  bool _isLoading = true;
  Future<void>? _loadConversationsFuture;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _currentUserId = context.read<AuthProvider>().user?.id;
    _loadConversations();
    _setupSocketListeners();
  }

  Future<void> _loadConversations({bool force = false}) async {
    final pending = _loadConversationsFuture;
    if (pending != null && !force) {
      return pending;
    }

    final future = _loadConversationsInternal();
    _loadConversationsFuture = future;
    try {
      await future;
    } finally {
      if (identical(_loadConversationsFuture, future)) {
        _loadConversationsFuture = null;
      }
    }
  }

  Future<void> _loadConversationsInternal() async {
    if (_conversations.isEmpty && mounted) {
      setState(() => _isLoading = true);
    }

    final conversations = await MessageService.getConversations();

    if (!mounted) return;

    setState(() {
      _conversations = conversations;
      _isLoading = false;
    });
  }

  void _setupSocketListeners() {
    _subs.add(SocketService.dmStream.listen(_handleDirectMessage));
    _subs.add(
      SocketService.messageReactionStream.listen((_) => _scheduleRefresh()),
    );
    _subs.add(
      SocketService.messageReadStream.listen((_) => _scheduleRefresh()),
    );
    _subs.add(
      SocketService.resyncStream.listen((_) => _scheduleRefresh()),
    );
  }

  void _handleDirectMessage(Map<String, dynamic> event) {
    final messageJson = event['message'];
    final currentUserId = _currentUserId;
    if (messageJson is! Map || currentUserId == null) {
      _scheduleRefresh();
      return;
    }

    final message =
        MessageModel.fromJson(Map<String, dynamic>.from(messageJson));
    final partnerId = message.senderId == currentUserId
        ? message.recipientId
        : message.senderId;

    if (partnerId == null || partnerId.isEmpty) {
      _scheduleRefresh();
      return;
    }

    final index = _conversations.indexWhere(
      (conversation) =>
          conversation.id == partnerId ||
          conversation.user['_id']?.toString() == partnerId,
    );

    if (index == -1) {
      _scheduleRefresh();
      return;
    }

    final existing = _conversations[index];
    final updatedConversation = ConversationModel(
      id: existing.id,
      user: Map<String, dynamic>.from(existing.user),
      lastMessage: message,
      unreadCount:
          message.senderId == currentUserId ? 0 : existing.unreadCount + 1,
    );
    final updated = [..._conversations]..removeAt(index);
    updated.insert(0, updatedConversation);

    if (!mounted) return;
    setState(() {
      _conversations = updated;
    });
  }

  void _scheduleRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(
      const Duration(milliseconds: 400),
      () => _loadConversations(force: true),
    );
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _currentUserId;

    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _conversations.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.chat_bubble_outline,
                      size: 64,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No conversations yet',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Start chatting with your friends',
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: _conversations.length,
                itemBuilder: (context, index) {
                  final conv = _conversations[index];
                  final isFromMe = conv.lastMessage.senderId == currentUserId;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: conv.unreadCount > 0
                          ? Colors.white
                          : AppColors.surfaceGrey,
                      borderRadius: BorderRadius.circular(16),
                      border: conv.unreadCount > 0
                          ? Border.all(
                              color:
                                  AppColors.primaryBlue.withValues(alpha: 0.3),
                              width: 1)
                          : Border.all(color: Colors.transparent, width: 0),
                      boxShadow: conv.unreadCount > 0
                          ? [
                              BoxShadow(
                                color: AppColors.primaryBlue
                                    .withValues(alpha: 0.05),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              )
                            ]
                          : null,
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      leading: Stack(
                        children: [
                          UserAvatar(
                            imageUrl: conv.user['avatar'],
                            username: conv.user['username'] ?? '',
                            radius: 28,
                          ),
                          if (conv.user['status']?['isOnline'] == true)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                  border:
                                      Border.all(color: Colors.white, width: 2),
                                ),
                              ),
                            ),
                        ],
                      ),
                      title: Text(
                        conv.user['username'] ?? 'Unknown',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary),
                      ),
                      subtitle: Row(
                        children: [
                          if (isFromMe)
                            const Padding(
                              padding: EdgeInsets.only(right: 4),
                              child: Text(
                                'You: ',
                                style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textSecondary),
                              ),
                            ),
                          Expanded(
                            child: Text(
                              conv.lastMessage.content,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: conv.unreadCount > 0 && !isFromMe
                                    ? Colors.black
                                    : Colors.grey.shade600,
                                fontWeight: conv.unreadCount > 0 && !isFromMe
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (conv.unreadCount > 0 && !isFromMe)
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: AppColors.primaryBlue,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${conv.unreadCount}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          const SizedBox(width: 8),
                          Text(
                            conv.lastMessage.timeAgo,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ChatScreen(
                              userId: conv.user['_id'],
                              username: conv.user['username'],
                              avatar: conv.user['avatar'],
                            ),
                          ),
                        ).then((_) => _loadConversations(force: true));
                      },
                    ),
                  );
                },
              );
  }
}
