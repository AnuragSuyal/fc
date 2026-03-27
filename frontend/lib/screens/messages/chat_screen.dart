import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/message_service.dart';
import '../../services/socket_service.dart';
import '../../models/message_model.dart';
import '../../providers/auth_provider.dart';
import '../../utils/constants.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/rounded_scaffold.dart';

class ChatScreen extends StatefulWidget {
  final String userId;
  final String username;
  final String? avatar;

  const ChatScreen({
    super.key,
    required this.userId,
    required this.username,
    this.avatar,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<StreamSubscription> _socketSubs = [];
  List<MessageModel> _messages = [];
  bool _isLoading = true;
  bool _isPaging = false;
  bool _isSending = false;
  bool _isPartnerTyping = false;
  bool _hasSentTyping = false;
  Timer? _typingTimer;
  int _currentPage = 1;
  bool _hasMore = true;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _currentUserId = context.read<AuthProvider>().user?.id;
    _loadMessages();
    _setupSocketListeners();
  }

  @override
  void dispose() {
    _clearTypingState();
    for (final sub in _socketSubs) {
      sub.cancel();
    }
    _messageController.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadMessages({bool reset = false}) async {
    if (reset) {
      _currentPage = 1;
      _hasMore = true;
    }

    if (!_hasMore) return;
    if (_currentPage == 1 && _isLoading && !reset) return;
    if (_currentPage > 1 && _isPaging) return;

    setState(() {
      if (_currentPage == 1) {
        _isLoading = true;
      } else {
        _isPaging = true;
      }
    });

    final requestedPage = _currentPage;

    final result = await MessageService.getDirectMessages(
      widget.userId,
      page: requestedPage,
    );

    if (!mounted) return;

    setState(() {
      final incomingMessages = List<MessageModel>.from(result['messages']);

      if (requestedPage == 1) {
        _messages = incomingMessages;
      } else {
        _messages = [...incomingMessages, ..._messages];
      }

      final totalPages = result['pagination']?['pages'];
      _hasMore = totalPages is num ? totalPages > requestedPage : false;
      _isLoading = false;
      _isPaging = false;

      // Scroll to bottom on first load
      if (requestedPage == 1 && _messages.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom();
        });
      }
    });
  }

  void _setupSocketListeners() {
    _socketSubs.add(SocketService.dmStream.listen(_handleIncomingMessage));
    _socketSubs.add(SocketService.typingStream.listen(_handleTypingEvent));
    _socketSubs.add(
      SocketService.messageReactionStream.listen(_handleReactionEvent),
    );
    _socketSubs.add(
      SocketService.messageReadStream.listen(_handleReadReceipt),
    );
    _socketSubs.add(
      SocketService.resyncStream.listen((_) => _loadMessages(reset: true)),
    );
  }

  void _handleIncomingMessage(Map<String, dynamic> data) {
    final messageJson = data['message'];
    if (messageJson is! Map) return;

    final currentUserId = _currentUserId;
    if (currentUserId == null) return;

    final message =
        MessageModel.fromJson(Map<String, dynamic>.from(messageJson));
    final participantIds = <String>{
      message.senderId,
      if (message.recipientId != null) message.recipientId!,
    };
    final isRelevant = participantIds.contains(currentUserId) &&
        participantIds.contains(widget.userId);

    if (!isRelevant || _messages.any((item) => item.id == message.id)) {
      return;
    }

    setState(() {
      _messages = [message, ..._messages];
    });
    _scrollToBottom();

    if (message.senderId == widget.userId) {
      _markAsRead();
    }
  }

  void _handleTypingEvent(Map<String, dynamic> data) {
    if (data['userId']?.toString() != widget.userId) return;
    final isTyping = data['isTyping'] == true;
    if (_isPartnerTyping == isTyping) return;
    setState(() => _isPartnerTyping = isTyping);
  }

  void _handleReactionEvent(Map<String, dynamic> data) {
    final messageId = data['messageId']?.toString();
    final userId = data['userId']?.toString();
    final reaction = data['reaction']?.toString();
    if (messageId == null || userId == null || reaction == null) return;
    _updateMessageReaction(messageId, userId, reaction);
  }

  void _handleReadReceipt(Map<String, dynamic> data) {
    final currentUserId = _currentUserId;
    final byUserId = data['byUserId']?.toString();
    final fromUserId = data['fromUserId']?.toString();
    if (currentUserId == null ||
        byUserId != widget.userId ||
        fromUserId != currentUserId) {
      return;
    }

    setState(() {
      _messages = _messages.map((message) {
        final isOutgoingToCurrentChat = message.senderId == currentUserId &&
            message.recipientId == widget.userId;
        if (!isOutgoingToCurrentChat || message.readBy.isNotEmpty) {
          return message;
        }

        return message.copyWith(
          readBy: [
            ...message.readBy,
            {
              'userId': widget.userId,
              'readAt': DateTime.now().toIso8601String(),
            },
          ],
        );
      }).toList(growable: false);
    });
  }

  void _updateMessageReaction(
      String messageId, String userId, String reaction) {
    setState(() {
      final index = _messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        final message = _messages[index];
        final existingIndex = message.reactions
            .indexWhere((r) => r.userId == userId && r.reaction == reaction);

        if (existingIndex != -1) {
          message.reactions.removeAt(existingIndex);
        } else {
          message.reactions.add(Reaction(
            userId: userId,
            reaction: reaction,
            createdAt: DateTime.now(),
          ));
        }
      }
    });
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0, // Because this layout is `reverse: true`
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _handleTyping(String value) {
    if (value.trim().isEmpty) {
      _typingTimer?.cancel();
      _clearTypingState();
      return;
    }

    if (!_hasSentTyping) {
      _hasSentTyping = true;
      SocketService.sendTyping(recipientId: widget.userId, isTyping: true);
    }

    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), _clearTypingState);
  }

  void _clearTypingState() {
    if (!_hasSentTyping) return;
    _hasSentTyping = false;
    SocketService.sendTyping(recipientId: widget.userId, isTyping: false);
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    setState(() => _isSending = true);

    final content = _messageController.text.trim();
    // Optimistic UI updates could go here
    _messageController.clear();

    final message = await MessageService.sendDirectMessage(
      recipientId: widget.userId,
      content: content,
    );

    if (message != null && mounted) {
      // Typically if socket echo happens we wouldn't double add, but for DM sending the socket might only go to recipient.
      // If our API returns it, we can insert it.
      setState(() {
        // Only insert if it's not already there (if socket delivered it first)
        if (!_messages.any((m) => m.id == message.id)) {
          _messages.insert(0, message);
        }
      });
      _scrollToBottom();
    }

    if (mounted) {
      setState(() => _isSending = false);
    }
  }

  Future<void> _handleReaction(String messageId, String reaction) async {
    await MessageService.addReaction(messageId, reaction);
  }

  Future<void> _handleDeleteMessage(String messageId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Message'),
        content: const Text('Are you sure you want to delete this message?'),
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
      final success = await MessageService.deleteMessage(messageId);
      if (success && mounted) {
        setState(() {
          _messages.removeWhere((m) => m.id == messageId);
        });
      }
    }
  }

  Future<void> _markAsRead() async {
    await MessageService.markAsRead(widget.userId);
  }

  void _loadMore() {
    if (_hasMore && !_isLoading && !_isPaging) {
      _currentPage++;
      _loadMessages();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _currentUserId;

    return RoundedScaffold(
      titleWidget: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          UserAvatar(
            imageUrl: widget.avatar,
            username: widget.username,
            radius: 20,
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.username,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_isPartnerTyping)
                const Text(
                  'typing...',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.info_outline, color: Colors.white),
          onPressed: () {
            // TODO: Open user profile or chat settings
          },
        ),
      ],
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: _isLoading && _messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification is ScrollUpdateNotification &&
                          notification.metrics.extentAfter < 100 &&
                          _hasMore &&
                          !_isLoading) {
                        _loadMore();
                      }
                      return false;
                    },
                    child: ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length + (_isPaging ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _messages.length) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(8),
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }

                        // Index 0 is bottom with reverse: true
                        final message = _messages[index];
                        final isFromMe = message.senderId == currentUserId;

                        return GestureDetector(
                          onLongPress: () {
                            if (isFromMe) {
                              _showMessageOptions(message);
                            } else {
                              _showReactionOptions(message);
                            }
                          },
                          child: Container(
                            margin: EdgeInsets.only(
                              bottom: 8,
                              left: isFromMe ? 50 : 0,
                              right: isFromMe ? 0 : 50,
                            ),
                            child: Row(
                              mainAxisAlignment: isFromMe
                                  ? MainAxisAlignment.end
                                  : MainAxisAlignment.start,
                              children: [
                                if (!isFromMe)
                                  UserAvatar(
                                    imageUrl: widget.avatar,
                                    username: widget.username,
                                    radius: 16,
                                  ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: isFromMe
                                          ? AppColors.primaryBlue
                                          : Colors.grey.shade200,
                                      borderRadius:
                                          BorderRadius.circular(16).copyWith(
                                        bottomLeft: isFromMe
                                            ? const Radius.circular(16)
                                            : const Radius.circular(4),
                                        bottomRight: isFromMe
                                            ? const Radius.circular(4)
                                            : const Radius.circular(16),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Reply indicator
                                        if (message.replyTo != null) ...[
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: isFromMe
                                                  ? Colors.white
                                                      .withValues(alpha: 0.2)
                                                  : Colors.grey.shade300,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              message.replyTo!.content,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: isFromMe
                                                    ? Colors.white70
                                                    : Colors.grey.shade700,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                        ],

                                        // Message content
                                        Text(
                                          message.content,
                                          style: TextStyle(
                                            color: isFromMe
                                                ? Colors.white
                                                : Colors.black87,
                                          ),
                                        ),

                                        // Reactions
                                        if (message.reactions.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Wrap(
                                            spacing: 4,
                                            children: message.reactions
                                                .map((r) => Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 6,
                                                        vertical: 2,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: isFromMe
                                                            ? Colors.white
                                                                .withValues(
                                                                    alpha: 0.2)
                                                            : Colors
                                                                .grey.shade300,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(12),
                                                      ),
                                                      child: Text(
                                                        r.reaction,
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: isFromMe
                                                              ? Colors.white
                                                              : Colors.black87,
                                                        ),
                                                      ),
                                                    ))
                                                .toList(),
                                          ),
                                        ],

                                        // Time and read status
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              message.timeAgo,
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: isFromMe
                                                    ? Colors.white70
                                                    : Colors.grey.shade600,
                                              ),
                                            ),
                                            if (isFromMe) ...[
                                              const SizedBox(width: 4),
                                              Icon(
                                                message.isRead
                                                    ? Icons.done_all
                                                    : Icons.done,
                                                size: 12,
                                                color: message.isRead
                                                    ? Colors.blue.shade200
                                                    : Colors.white70,
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),

          // Typing indicator
          if (_isPartnerTyping)
            Container(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ...List.generate(
                            3,
                            (index) => Container(
                                  width: 6,
                                  height: 6,
                                  margin:
                                      const EdgeInsets.symmetric(horizontal: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade600,
                                    shape: BoxShape.circle,
                                  ),
                                  child: _buildTypingAnimation(index),
                                )),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // Message input
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: Colors.grey.shade200),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    onChanged: _handleTyping,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.primaryBlue,
                  child: IconButton(
                    icon: _isSending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.send, color: Colors.white),
                    onPressed: _isSending ? null : _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingAnimation(int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.5, end: 1.0),
      duration: Duration(milliseconds: 600 + (index * 200)),
      curve: Curves.easeInOut,
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: child,
        );
      },
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: Colors.grey.shade600,
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  void _showMessageOptions(MessageModel message) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete Message'),
              onTap: () {
                Navigator.pop(context);
                _handleDeleteMessage(message.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showReactionOptions(MessageModel message) {
    final reactions = ['ðŸ‘', 'â¤ï¸', 'ðŸ˜‚', 'ðŸ˜®', 'ðŸ˜¢', 'ðŸ˜¡'];

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Add Reaction',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: reactions.map((reaction) {
                final hasReacted =
                    message.reactions.any((r) => r.reaction == reaction);
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    _handleReaction(message.id, reaction);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: hasReacted
                          ? AppColors.primaryBlue.withValues(alpha: 0.1)
                          : Colors.grey.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      reaction,
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
