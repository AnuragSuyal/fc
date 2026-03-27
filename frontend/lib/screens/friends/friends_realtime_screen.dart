import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/socket_service.dart';
import '../../services/api_service.dart';
import '../../services/friend_service.dart';
import '../../utils/constants.dart';
import '../../widgets/user_avatar.dart';

class FriendsRealtimeScreen extends StatefulWidget {
  const FriendsRealtimeScreen({super.key});
  @override
  State<FriendsRealtimeScreen> createState() => _FriendsRealtimeScreenState();
}

class _FriendsRealtimeScreenState extends State<FriendsRealtimeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  List<dynamic> _online = [], _offline = [], _requests = [];
  bool _loading = true;
  StreamSubscription? _friendSub;
  StreamSubscription? _resyncSub;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _load();
    _friendSub = SocketService.friendStream.listen(_onFriend);
    _resyncSub = SocketService.resyncStream.listen((_) => _load());
  }

  @override
  void dispose() {
    _tabs.dispose();
    _friendSub?.cancel();
    _resyncSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final fr = await ApiService.get('/friends');
      final rq = await ApiService.get('/friends/requests');
      if (!mounted) return;
      setState(() {
        _online = fr['online'] as List? ?? [];
        _offline = fr['offline'] as List? ?? [];
        _requests = rq is List ? rq : [];
        _loading = false;
      });
      Provider.of<AuthProvider>(context, listen: false)
          .clearPendingFriendRequests();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onFriend(Map<String, dynamic> d) {
    if (!mounted) return;
    final type = d['_eventType'] as String? ?? '';
    if (type == 'friend_request_received') {
      setState(() => _requests.insert(0, d));
      _snack('New friend request from ${d['from']?['username'] ?? 'someone'}',
          AppColors.primaryBlue);
    } else if (type == 'friend_request_accepted') {
      _snack('${d['user']?['username'] ?? 'Someone'} accepted your request! 🎉',
          AppColors.successGreen);
      _load();
    } else if (type == 'friend_request_rejected') {
      _snack('Friend request declined.', AppColors.warningOrange);
    } else if (type == 'friend_removed') {
      _load();
    } else if (type == 'friend_online') {
      final uid = d['userId']?.toString();
      if (uid == null) return;
      final idx =
          _offline.indexWhere((f) => (f['_id'] ?? f['id'])?.toString() == uid);
      if (idx != -1) {
        setState(() {
          _online.insert(0, _offline.removeAt(idx));
        });
      }
    } else if (type == 'friend_offline') {
      final uid = d['userId']?.toString();
      if (uid == null) return;
      final idx =
          _online.indexWhere((f) => (f['_id'] ?? f['id'])?.toString() == uid);
      if (idx != -1) {
        setState(() {
          _offline.add(_online.removeAt(idx));
        });
      }
    }
  }

  void _snack(String msg, Color bg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
          backgroundColor: bg,
          duration: const Duration(seconds: 3)));

  Future<void> _accept(String uid) async {
    final success = await FriendService.acceptFriendRequest(uid);
    if (success) {
      _load();
      return;
    }
    _snack('Failed to accept friend request', AppColors.errorRed);
  }

  Future<void> _reject(String uid) async {
    final success = await FriendService.rejectFriendRequest(uid);
    if (success) {
      setState(() => _requests.removeWhere(
            (r) => (r['from']?['_id'] ?? r['from'])?.toString() == uid,
          ));
      return;
    }
    _snack('Failed to reject friend request', AppColors.errorRed);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text('Friends'),
          bottom: TabBar(controller: _tabs, tabs: [
            Tab(text: 'Online (${_online.length})'),
            Tab(text: 'Offline (${_offline.length})'),
            Tab(
                child: Stack(clipBehavior: Clip.none, children: [
              const Text('Requests'),
              if (_requests.isNotEmpty)
                Positioned(
                    right: -12,
                    top: -4,
                    child: CircleAvatar(
                        radius: 8,
                        backgroundColor: AppColors.errorRed,
                        child: Text('${_requests.length}',
                            style: const TextStyle(
                                fontSize: 10, color: Colors.white)))),
            ])),
          ])),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: TabBarView(controller: _tabs, children: [
                _list(_online, 'No friends online'),
                _list(_offline, 'No offline friends'),
                _reqList(),
              ])),
    );
  }

  Widget _list(List<dynamic> items, String empty) {
    if (items.isEmpty) {
      return Center(
          child: Text(empty, style: TextStyle(color: Colors.grey.shade500)));
    }
    return ListView.builder(
        itemCount: items.length,
        itemBuilder: (_, i) {
          final f = items[i] as Map<String, dynamic>;
          return ListTile(
            leading: UserAvatar(
                imageUrl: f['avatar']?.toString(),
                username: f['username']?.toString() ?? 'U',
                radius: 24),
            title: Text(f['username']?.toString() ?? 'Unknown'),
            subtitle: Text('Level ${f['level'] ?? 1}'),
            trailing: CircleAvatar(
                radius: 5,
                backgroundColor:
                    items == _online ? AppColors.successGreen : Colors.grey),
          );
        });
  }

  Widget _reqList() {
    if (_requests.isEmpty) {
      return const Center(
          child: Text('No pending requests',
              style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
        itemCount: _requests.length,
        itemBuilder: (_, i) {
          final r = _requests[i] as Map<String, dynamic>;
          final from = r['from'] is Map
              ? r['from'] as Map<String, dynamic>
              : <String, dynamic>{};
          final uid =
              (from['_id'] ?? from['id'] ?? r['userId'])?.toString() ?? '';
          return ListTile(
            leading: UserAvatar(
                imageUrl: from['avatar']?.toString(),
                username: from['username']?.toString() ?? 'U',
                radius: 24),
            title: Text(from['username']?.toString() ?? 'Unknown'),
            subtitle: const Text('Sent you a friend request'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              TextButton(
                  onPressed: () => _accept(uid),
                  child: const Text('Accept',
                      style: TextStyle(color: AppColors.successGreen))),
              TextButton(
                  onPressed: () => _reject(uid),
                  child: const Text('Decline',
                      style: TextStyle(color: AppColors.errorRed))),
            ]),
          );
        });
  }
}
