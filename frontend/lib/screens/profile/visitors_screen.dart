import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/profile_service.dart';
import '../../services/socket_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/constants.dart';
import '../../widgets/rounded_scaffold.dart';
import '../../widgets/user_avatar.dart';

class VisitorsScreen extends StatefulWidget {
  final List<dynamic> visitors;

  const VisitorsScreen({super.key, required this.visitors});

  @override
  State<VisitorsScreen> createState() => _VisitorsScreenState();
}

class _VisitorsScreenState extends State<VisitorsScreen> {
  late List<dynamic> _visitors = List<dynamic>.from(widget.visitors);

  StreamSubscription<Map<String, dynamic>>? _profileSubscription;

  String? _currentUserId;
  bool _isLoading = true;
  bool _isDisposed = false;
  String _liveLabel = 'People who viewed your profile appear here.';

  void _safeSetState(VoidCallback fn) {
    if (!_isDisposed && mounted) {
      setState(fn);
    }
  }

  @override
  void initState() {
    super.initState();
    _currentUserId = context.read<AuthProvider>().user?.id;
    _bindRealtime();
    unawaited(_loadVisitors(showLoader: _visitors.isEmpty));
  }

  @override
  void dispose() {
    _isDisposed = true;
    _profileSubscription?.cancel();
    super.dispose();
  }

  void _bindRealtime() {
    _profileSubscription = SocketService.profileStream.listen((event) {
      final type = event['_eventType']?.toString();
      if (type != 'profile_visitor' ||
          _currentUserId == null ||
          event['userId']?.toString() != _currentUserId) {
        return;
      }

      final visitor = event['visitor'];
      if (visitor is! Map) return;

      final visitorMap = Map<String, dynamic>.from(visitor);
      final username =
          visitorMap['username']?.toString().trim().isNotEmpty == true
              ? visitorMap['username'].toString().trim()
              : 'Someone';

      _safeSetState(() {
        _liveLabel = '$username viewed your profile just now.';
        _upsertVisitor({
          'userId': visitorMap,
          'visitedAt': event['timestamp'],
          'message': event['message'],
        });
      });
    });
  }

  Future<void> _loadVisitors({bool showLoader = false}) async {
    final userId = _currentUserId;
    if (userId == null || userId.isEmpty) {
      _safeSetState(() => _isLoading = false);
      return;
    }

    if (showLoader) {
      _safeSetState(() => _isLoading = true);
    }

    final data = await ProfileService.getVisitors(userId, limit: 50);
    if (!mounted || _isDisposed) return;

    final visitors = data['visitors'] is List
        ? List<dynamic>.from(data['visitors'] as List)
        : <dynamic>[];

    _safeSetState(() {
      _visitors = visitors;
      _isLoading = false;
      _liveLabel = _visitors.isEmpty
          ? 'People who viewed your profile appear here.'
          : '${_visitors.length} recent profile view${_visitors.length == 1 ? '' : 's'}.';
    });
  }

  void _upsertVisitor(Map<String, dynamic> entry) {
    final visitorId = _visitorId(entry);
    if (visitorId.isNotEmpty) {
      _visitors.removeWhere((item) => _visitorId(item) == visitorId);
    }
    _visitors.insert(0, entry);
  }

  Map<String, dynamic> _visitorUser(dynamic entry) {
    if (entry is! Map) return const {};

    final raw = entry['userId'] ?? entry['visitor'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return const {};
  }

  String _visitorId(dynamic entry) {
    final user = _visitorUser(entry);
    return user['id']?.toString() ?? user['_id']?.toString() ?? '';
  }

  DateTime? _visitedAt(dynamic entry) {
    if (entry is! Map) return null;

    final raw = entry['visitedAt'] ?? entry['timestamp'];
    if (raw is DateTime) return raw;
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  String _visitorMessage(dynamic entry) {
    if (entry is! Map) return '';
    return entry['message']?.toString().trim() ?? '';
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return RoundedScaffold(
      title: 'Visitors',
      body: _isLoading && _visitors.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _loadVisitors(showLoader: false),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                children: [
                  _buildLiveStrip(),
                  const SizedBox(height: 12),
                  if (_visitors.isEmpty)
                    _buildEmptyState()
                  else
                    ..._visitors.map(_buildVisitorCard),
                ],
              ),
            ),
    );
  }

  Widget _buildLiveStrip() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: context.mood.outlineSoft),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.visibility_outlined,
              color: Color(0xFF6366F1),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Profile visitors',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  _liveLabel,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _infoPill(
            '${_visitors.length}',
            background: const Color(0xFFEEF2FF),
            foreground: const Color(0xFF6366F1),
          ),
        ],
      ),
    );
  }

  Widget _buildVisitorCard(dynamic entry) {
    final user = _visitorUser(entry);
    final userId = _visitorId(entry);
    final username = user['username']?.toString().trim().isNotEmpty == true
        ? user['username'].toString().trim()
        : 'Visitor';
    final uid = user['uid']?.toString().trim() ?? '';
    final avatar = user['avatar']?.toString();
    final level = _toInt(user['level']);
    final visitedAt = _visitedAt(entry);
    final message = _visitorMessage(entry);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: userId.isEmpty
            ? null
            : () => Navigator.pushNamed(context, '/profile', arguments: userId),
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: context.mood.outlineSoft),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              UserAvatar(
                imageUrl: avatar != null && avatar.isNotEmpty ? avatar : null,
                username: username,
                radius: 24,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (visitedAt != null)
                          Text(
                            _timeAgo(visitedAt),
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (uid.isNotEmpty)
                          _infoPill(
                            'UID $uid',
                            background: const Color(0xFFF8FAFC),
                            foreground: AppColors.textSecondary,
                          ),
                        if (level > 0)
                          _infoPill(
                            'Lv $level',
                            background: const Color(0xFFEEF2FF),
                            foreground: const Color(0xFF4338CA),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      message.isNotEmpty
                          ? message
                          : 'Viewed your profile recently.',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              if (userId.isNotEmpty) ...[
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textTertiary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.mood.outlineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.visibility_outlined,
              color: Color(0xFF6366F1),
              size: 30,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'No visitors yet',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'When someone opens your profile, they will show up here with the time they visited.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoPill(
    String label, {
    required Color background,
    required Color foreground,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _timeAgo(DateTime dateTime) {
    final difference = DateTime.now().difference(dateTime);
    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    }
    if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    }
    if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    }
    return 'Just now';
  }
}
