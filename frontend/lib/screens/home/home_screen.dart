import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/room_model.dart';
import '../../services/room_service.dart';
import '../../services/socket_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/constants.dart';
import '../../widgets/room_card.dart';
import '../rooms/create_room_screen.dart';
import '../rooms/rooms_screen.dart';
import '../vip/vip_screen.dart';
import '../wallet/wallet_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<RoomModel> _trendingRooms = [];
  bool _isLoading = true;
  bool _isDisposed = false;
  Timer? _realtimeDebounce;
  Timer? _rallyExpiryTimer;
  StreamSubscription<Map<String, dynamic>>? _roomRealtimeSubscription;
  StreamSubscription<Map<String, dynamic>>? _socketResyncSubscription;

  @override
  void initState() {
    super.initState();
    _subscribeToRealtime();
    _loadData();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _realtimeDebounce?.cancel();
    _rallyExpiryTimer?.cancel();
    _roomRealtimeSubscription?.cancel();
    _socketResyncSubscription?.cancel();
    super.dispose();
  }

  void _subscribeToRealtime() {
    _roomRealtimeSubscription = SocketService.roomUpdateStream.listen((data) {
      final eventType = data['_eventType']?.toString();
      if (!{
        'room_created',
        'room_deleted',
        'room_updated',
        'lobby_update',
        'participant_joined',
        'participant_left',
        'rally_fans',
      }.contains(eventType)) {
        return;
      }

      _realtimeDebounce?.cancel();
      _realtimeDebounce = Timer(const Duration(milliseconds: 500), () {
        if (!_isDisposed && mounted) {
          _loadData(showLoader: false);
        }
      });
    });

    _socketResyncSubscription = SocketService.resyncStream.listen((_) {
      _realtimeDebounce?.cancel();
      _realtimeDebounce = Timer(const Duration(milliseconds: 500), () {
        if (!_isDisposed && mounted) {
          _loadData(showLoader: false);
        }
      });
    });
  }

  Future<void> _loadData({bool showLoader = true}) async {
    if (!mounted) return;
    if (showLoader) {
      setState(() => _isLoading = true);
    }

    try {
      final trendingRooms = await RoomService.getTrendingRooms();

      if (!mounted) return;
      setState(() {
        _trendingRooms = trendingRooms;
        _isLoading = false;
      });
      _scheduleRallyRefresh(trendingRooms);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _scheduleRallyRefresh(List<RoomModel> rooms) {
    _rallyExpiryTimer?.cancel();

    final now = DateTime.now();
    DateTime? nearestExpiry;
    for (final room in rooms) {
      final expiry = room.rallyExpiresAt;
      if (expiry == null || !expiry.isAfter(now)) continue;
      if (nearestExpiry == null || expiry.isBefore(nearestExpiry)) {
        nearestExpiry = expiry;
      }
    }

    if (nearestExpiry == null) return;

    final duration = nearestExpiry.difference(now) + const Duration(seconds: 1);
    _rallyExpiryTimer = Timer(duration, () {
      if (!_isDisposed && mounted) {
        _loadData(showLoader: false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final mood = context.mood;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            mood.shellTop.withValues(alpha: 0.45),
            Colors.transparent,
          ],
        ),
      ),
      child: RefreshIndicator(
        color: AppColors.primaryBlue,
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          children: [
            _buildSectionHeader(
              'Quick hops',
              'Open the things you use most in one tap.',
            ),
            const SizedBox(height: 12),
            _buildActions(),
            const SizedBox(height: 22),
            _buildSectionHeader(
              'Live picks',
              'Rooms with a fun pulse right now.',
            ),
            const SizedBox(height: 12),
            if (_isLoading && _trendingRooms.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_trendingRooms.isEmpty)
              _buildEmptyPanel(
                icon: Icons.celebration_rounded,
                title: 'Quiet for a moment',
                message:
                    'New rooms will pop here as soon as people start hanging out.',
                cta: 'Create a room',
                onTap: _openCreateRoom,
              )
            else
              ..._trendingRooms.take(4).map(
                    (room) => RoomCard(room: room),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    String title,
    String subtitle, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            child: Text(actionLabel),
          ),
      ],
    );
  }

  Widget _buildActions() {
    final actions = [
      _ActionItem(
        'Rooms',
        'Drop into live spaces',
        'assets/images/home_rooms.png',
        AppColors.primaryBlue,
        const RoomsScreen(),
      ),
      _ActionItem(
        'Create',
        'Start a vibe fast',
        'assets/images/home_create.png',
        AppColors.secondaryBlue,
        const CreateRoomScreen(),
      ),
      _ActionItem(
        'Wallet',
        'Coins and gems',
        'assets/images/home_wallet.png',
        const Color(0xFF39424D),
        const WalletScreen(),
      ),
      _ActionItem(
        'VIP',
        'Extra sparkle perks',
        'assets/images/home_vip.png',
        AppColors.accentBerry,
        const VipScreen(),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: actions
              .map(
                (item) => SizedBox(
                  width: width,
                  child: _buildActionCard(item),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _buildActionCard(_ActionItem item) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: () => _open(item.target),
      borderRadius: BorderRadius.circular(28),
      child: Ink(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: context.mood.outlineSoft),
          boxShadow: [
            BoxShadow(
              color: item.color.withValues(alpha: 0.12),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 92,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Image.asset(
                  item.assetPath,
                  width: 92,
                  height: 92,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              item.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              item.subtitle,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyPanel({
    required IconData icon,
    required String title,
    required String message,
    required String cta,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: context.mood.outlineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.primaryBlue),
          ),
          const SizedBox(height: 16),
          Text(title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onTap,
            child: Text(cta),
          ),
        ],
      ),
    );
  }

  void _open(Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  void _openCreateRoom() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateRoomScreen()),
    );
  }
}

class _ActionItem {
  const _ActionItem(
    this.title,
    this.subtitle,
    this.assetPath,
    this.color,
    this.target,
  );

  final String title;
  final String subtitle;
  final String assetPath;
  final Color color;
  final Widget target;
}
