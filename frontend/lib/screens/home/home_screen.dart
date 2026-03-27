import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/room_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/room_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/constants.dart';
import '../../widgets/room_card.dart';
import '../../widgets/user_avatar.dart';
import '../gifts/gift_shop_screen.dart';
import '../rooms/create_room_screen.dart';
import '../rooms/room_detail_screen.dart';
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
  List<RoomModel> _myRooms = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait<List<RoomModel>>([
        RoomService.getTrendingRooms(),
        RoomService.getMyRooms(),
      ]);

      if (!mounted) return;
      setState(() {
        _trendingRooms = results[0];
        _myRooms = results[1];
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
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
            _buildWalletSummary(),
            const SizedBox(height: 22),
            _buildSectionHeader(
              'Quick hops',
              'Open the things you use most in one tap.',
            ),
            const SizedBox(height: 12),
            _buildActions(),
            const SizedBox(height: 22),
            _buildSectionHeader(
              'Your rooms',
              _myRooms.isEmpty
                  ? 'Create a room or jump back into one.'
                  : 'The spaces your circle already knows.',
              actionLabel: 'See all',
              onAction: () => _open(const RoomsScreen()),
            ),
            const SizedBox(height: 12),
            _buildMyRooms(),
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

  Widget _buildWalletSummary() {
    final theme = Theme.of(context);

    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        final coins = authProvider.user?.coins ?? 0;
        final gems = authProvider.user?.gems ?? 0;

        return InkWell(
          onTap: () => _open(const WalletScreen()),
          borderRadius: BorderRadius.circular(30),
          child: Ink(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF16181C),
                  Color(0xFF2A2F36),
                ],
              ),
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 22,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Wallet',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Live coins and diamonds. Tap to open wallet.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.72),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _balancePill(
                        icon: Icons.monetization_on_rounded,
                        iconColor: const Color(0xFFFFC857),
                        label: 'Coins',
                        value: '$coins',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _balancePill(
                        icon: Icons.diamond_rounded,
                        iconColor: const Color(0xFF8EDBFF),
                        label: 'Diamonds',
                        value: '$gems',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _balancePill({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.70),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
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
        Icons.mic_none_rounded,
        AppColors.primaryBlue,
        const RoomsScreen(),
      ),
      _ActionItem(
        'Create',
        'Start a vibe fast',
        Icons.add_circle_outline_rounded,
        AppColors.secondaryBlue,
        const CreateRoomScreen(),
      ),
      _ActionItem(
        'Wallet',
        'Coins and gems',
        Icons.wallet_rounded,
        const Color(0xFF39424D),
        const WalletScreen(),
      ),
      _ActionItem(
        'VIP',
        'Extra sparkle perks',
        Icons.workspace_premium_rounded,
        AppColors.accentBerry,
        const VipScreen(),
      ),
      _ActionItem(
        'Gifts',
        'Send playful reactions',
        Icons.card_giftcard_rounded,
        AppColors.accentSky,
        const GiftShopScreen(),
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
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: item.color.withValues(alpha: 0.14)),
              ),
              child: Icon(item.icon, color: item.color, size: 22),
            ),
            const SizedBox(height: 16),
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

  Widget _buildMyRooms() {
    if (_isLoading && _myRooms.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_myRooms.isEmpty) {
      return _buildEmptyPanel(
        icon: Icons.weekend_rounded,
        title: 'No rooms yet',
        message: 'Open your first playful space and let your people join in.',
        cta: 'Create your first room',
        onTap: _openCreateRoom,
      );
    }

    return SizedBox(
      height: 190,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _myRooms.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final room = _myRooms[index];
          final accent = _roomColor(room.type);
          return InkWell(
            onTap: () => _openRoom(room),
            borderRadius: BorderRadius.circular(30),
            child: Ink(
              width: 248,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    accent.withValues(alpha: 0.18),
                    Colors.white,
                  ],
                ),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: context.mood.outlineSoft),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _pill(
                        room.category.toUpperCase(),
                        background: accent.withValues(alpha: 0.16),
                        foreground: AppColors.textPrimary,
                      ),
                      const Spacer(),
                      _pill(
                        '${room.onlineCount} online',
                        background: Colors.white,
                        foreground: AppColors.textSecondary,
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    room.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    room.description.isNotEmpty
                        ? room.description
                        : 'Hosted by ${room.hostName}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      UserAvatar(
                        username: room.hostName,
                        imageUrl: room.hostAvatar,
                        radius: 14,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          room.hostName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: accent,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
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

  Widget _pill(
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
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }

  Color _roomColor(String type) {
    switch (type) {
      case 'music':
        return AppColors.accentBerry;
      case 'chat':
        return AppColors.secondaryBlue;
      case 'video':
        return AppColors.accentSky;
      case 'auction':
        return AppColors.accentYellow;
      default:
        return AppColors.primaryBlue;
    }
  }

  void _open(Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  void _openRoom(RoomModel room) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RoomDetailScreen(room: room)),
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
    this.icon,
    this.color,
    this.target,
  );

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Widget target;
}
