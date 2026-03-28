class ChatActivityService {
  static final Set<String> _activeDirectChatUserIds = <String>{};

  static String? get activeDirectChatUserId =>
      _activeDirectChatUserIds.isEmpty ? null : _activeDirectChatUserIds.first;

  static bool isDirectChatOpenFor(String userId) =>
      _activeDirectChatUserIds.contains(userId);

  static void markDirectChatOpen(String userId) {
    if (userId.isEmpty) return;
    _activeDirectChatUserIds.add(userId);
  }

  static void markDirectChatClosed(String userId) {
    _activeDirectChatUserIds.remove(userId);
  }
}
