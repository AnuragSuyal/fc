import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/auth_service.dart';
import '../models/user_model.dart';
import '../models/message_model.dart';
import '../services/chat_activity_service.dart';
import '../services/notification_sound_service.dart';
import '../services/socket_service.dart';
import '../services/wallet_service.dart';

class AuthProvider extends ChangeNotifier {
  UserModel? _user;
  bool _isLoading = false;
  String? _error;
  int _pendingFriendRequests = 0;

  UserModel? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _user != null;
  int get pendingFriendRequests => _pendingFriendRequests;

  final List<StreamSubscription> _subs = [];
  Future<void>? _loadUserFuture;

  // ── Auth flows ──────────────────────────────────────────────────────────────
  Future<void> handleSocialToken(String token) async {
    _setLoading(true);
    try {
      final res = await AuthService.handleSocialToken(token);
      final rawUser = res['user'] is Map
          ? Map<String, dynamic>.from(res['user'] as Map)
          : null;
      if (rawUser == null) {
        throw Exception('Failed to load user profile');
      }
      _user = UserModel.fromJson(rawUser);
      await _initSocket();
      _setLoading(false);
    } catch (_) {
      _setError('Failed to load user profile');
    }
  }

  Future<bool> login(String email, String password) async {
    _setLoading(true);
    try {
      final res = await AuthService.login(email: email, password: password);
      _user = UserModel.fromJson(res['user']);
      await _initSocket();
      _setLoading(false);
      return true;
    } catch (e) {
      _setError(e.toString().replaceFirst('Exception: ', ''));
      return false;
    }
  }

  Future<bool> register(
      {required String username,
      required String email,
      required String password}) async {
    _setLoading(true);
    try {
      final res = await AuthService.register(
          username: username, email: email, password: password);
      _user = UserModel.fromJson(res['user']);
      await _initSocket();
      _setLoading(false);
      return true;
    } catch (e) {
      _setError(e.toString().replaceFirst('Exception: ', ''));
      return false;
    }
  }

  Future<bool> guestLogin() async {
    _setLoading(true);
    try {
      final res = await AuthService.guestLogin();
      _user = UserModel.fromJson(res['user']);
      await _initSocket();
      _setLoading(false);
      return true;
    } catch (e) {
      _setError(e.toString().replaceFirst('Exception: ', ''));
      return false;
    }
  }

  Future<void> logout() async {
    await AuthService.logout();
    _cancelSubs();
    await SocketService.dispose();
    _user = null;
    _pendingFriendRequests = 0;
    notifyListeners();
  }

  Future<void> loadUser() async {
    final pending = _loadUserFuture;
    if (pending != null) return pending;

    final future = _loadUserInternal();
    _loadUserFuture = future;
    try {
      await future;
    } finally {
      if (identical(_loadUserFuture, future)) {
        _loadUserFuture = null;
      }
    }
  }

  // ── Socket setup ────────────────────────────────────────────────────────────
  Future<void> _initSocket() async {
    await SocketService.init();
    _cancelSubs();
    _subs.add(SocketService.balanceStream.listen(_onBalance));
    _subs.add(SocketService.levelUpStream.listen(_onLevelUp));
    _subs.add(SocketService.friendStream.listen(_onFriend));
    _subs.add(SocketService.dmStream.listen(_onDirectMessage));
  }

  void _onBalance(Map<String, dynamic> d) => updateProfile(
        coins: _toInt(d['coins']),
        gems: _toInt(d['gems']),
        xp: _toInt(d['xp']),
        level: _toInt(d['level']),
        vipLevel: _toInt(d['vipLevel']),
      );

  void _onLevelUp(Map<String, dynamic> d) => updateProfile(
        level: _toInt(d['newLevel']),
        xp: _toInt(d['xp']),
      );

  void _onFriend(Map<String, dynamic> d) {
    final type = d['_eventType'] as String? ?? '';
    if (type == 'friend_request_received') {
      _pendingFriendRequests++;
      notifyListeners();
    } else if (type == 'friend_request_accepted' ||
        type == 'friend_request_rejected') {
      notifyListeners();
    }
  }

  void _onDirectMessage(Map<String, dynamic> d) {
    final rawMessage = d['message'];
    final currentUserId = _user?.id;
    if (rawMessage is! Map || currentUserId == null || currentUserId.isEmpty) {
      return;
    }

    final message = MessageModel.fromJson(Map<String, dynamic>.from(rawMessage));
    if (message.senderId == currentUserId) {
      return;
    }

    if (ChatActivityService.isDirectChatOpenFor(message.senderId)) {
      return;
    }

    unawaited(NotificationSoundService.playMessage());
  }

  // ── Profile helpers ─────────────────────────────────────────────────────────
  void updateProfile(
      {int? coins, int? gems, int? xp, int? level, int? vipLevel}) {
    if (_user == null) return;
    final nextUser = _user!.copyWith(
      coins: coins,
      gems: gems,
      xp: xp,
      level: level,
      vipLevel: vipLevel,
    );
    if (_sameUserSnapshot(_user!, nextUser)) return;
    _user = nextUser;
    notifyListeners();
  }

  void updateBalance({int? coins, int? gems}) =>
      updateProfile(coins: coins, gems: gems);

  void updateAvatar(String url) {
    if (_user == null || _user!.avatar == url) return;
    _user = _user!.copyWith(avatar: url);
    notifyListeners();
  }

  void updateUserDetails({
    String? username,
    String? email,
    String? avatar,
    String? coverPhoto,
    String? bio,
    String? region,
  }) {
    if (_user == null) return;

    final nextUser = _user!.copyWith(
      username: username,
      email: email,
      avatar: avatar,
      coverPhoto: coverPhoto,
      bio: bio,
      region: region,
    );

    if (_sameUserSnapshot(_user!, nextUser)) return;
    _user = nextUser;
    notifyListeners();
  }

  Future<void> refreshBalance() async {
    try {
      final b = await WalletService.getBalance();
      updateProfile(
          coins: b['coins'], gems: b['gems'], vipLevel: b['vipLevel']);
    } catch (_) {}
  }

  void clearPendingFriendRequests() {
    if (_pendingFriendRequests == 0) return;
    _pendingFriendRequests = 0;
    notifyListeners();
  }

  void syncPendingFriendRequests(int count) {
    final nextCount = count < 0 ? 0 : count;
    if (_pendingFriendRequests == nextCount) return;
    _pendingFriendRequests = nextCount;
    notifyListeners();
  }

  Future<String?> sendOTP(String phone) async {
    _setLoading(true);
    try {
      final res = await AuthService.sendOTP(phone);
      _setLoading(false);
      return res['otp']?.toString();
    } catch (e) {
      _setError(e.toString().replaceFirst('Exception: ', ''));
      rethrow;
    }
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  // ── Internals ───────────────────────────────────────────────────────────────
  Future<void> _loadUserInternal() async {
    final previousUser = _user;
    _setLoading(true);

    try {
      final isLoggedIn = await AuthService.isLoggedIn();
      if (!isLoggedIn) {
        _cancelSubs();
        _user = null;
        _pendingFriendRequests = 0;
        _setLoading(false);
        return;
      }

      final response = await AuthService.getCurrentUser();
      final rawUser = response['user'] is Map
          ? Map<String, dynamic>.from(response['user'] as Map)
          : Map<String, dynamic>.from(response as Map);
      _user = UserModel.fromJson(rawUser);
      await _initSocket();
      _setLoading(false);
    } catch (e) {
      final stillLoggedIn = await AuthService.isLoggedIn();
      if (!stillLoggedIn) {
        _cancelSubs();
        await SocketService.dispose();
        _user = null;
        _pendingFriendRequests = 0;
        _setLoading(false);
        return;
      }

      _user = previousUser;
      _setError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _setLoading(bool v) {
    final shouldClearError = v && _error != null;
    if (_isLoading == v && !shouldClearError) return;
    _isLoading = v;
    if (v) _error = null;
    notifyListeners();
  }

  void _setError(String m) {
    if (_isLoading == false && _error == m) return;
    _isLoading = false;
    _error = m;
    notifyListeners();
  }

  void _cancelSubs() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return null;
  }

  static bool _sameUserSnapshot(UserModel a, UserModel b) {
    return a.id == b.id &&
        a.uid == b.uid &&
        a.username == b.username &&
        a.email == b.email &&
        a.avatar == b.avatar &&
        a.coverPhoto == b.coverPhoto &&
        a.bio == b.bio &&
        a.region == b.region &&
        a.level == b.level &&
        a.xp == b.xp &&
        a.coins == b.coins &&
        a.gems == b.gems &&
        a.vipLevel == b.vipLevel &&
        a.isOnline == b.isOnline &&
        a.isGuest == b.isGuest &&
        a.lastActive == b.lastActive &&
        mapEquals(a.gameStats, b.gameStats) &&
        listEquals(a.badges, b.badges) &&
        mapEquals(a.stats, b.stats);
  }

  @override
  void dispose() {
    _cancelSubs();
    super.dispose();
  }
}
