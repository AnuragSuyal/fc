import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/user_avatar.dart';
import 'explore/explore_screen.dart';
import 'games/games_screen.dart';
import 'home/home_screen.dart';
import 'profile/me_screen.dart';
import 'social/social_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  final ValueNotifier<int> _exploreFocusSignal = ValueNotifier<int>(0);

  late final List<Widget> _screens = [
    const HomeScreen(),
    ExploreScreen(focusSignal: _exploreFocusSignal),
    const GamesScreen(),
    const SocialScreen(),
    const MeScreen(),
  ];

  final List<_NavItem> _navItems = const [
    _NavItem(label: 'Home', icon: Icons.cottage_rounded),
    _NavItem(label: 'Discover', icon: Icons.travel_explore_rounded),
    _NavItem(label: 'Games', icon: Icons.sports_esports_rounded),
    _NavItem(label: 'Circle', icon: Icons.groups_rounded),
    _NavItem(label: 'Me', icon: Icons.face_retouching_natural_rounded),
  ];

  bool get _showHeader => _selectedIndex == 0 || _selectedIndex == 2;

  @override
  void dispose() {
    _exploreFocusSignal.dispose();
    super.dispose();
  }

  void _openExploreSearch() {
    setState(() => _selectedIndex = 1);
    _exploreFocusSignal.value++;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mood = context.mood;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Container(
        decoration: BoxDecoration(gradient: mood.shellGradient),
        child: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              Positioned(
                top: -40,
                right: -10,
                child: _Orb(color: mood.sun.withValues(alpha: 0.24), size: 156),
              ),
              Positioned(
                top: 130,
                left: -42,
                child: _Orb(color: mood.sky.withValues(alpha: 0.18), size: 122),
              ),
              Column(
                children: [
                  if (_showHeader)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: _buildTopHeader(context),
                    ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        14,
                        _showHeader ? 16 : 8,
                        14,
                        94,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(36),
                        child: Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface
                                .withValues(alpha: 0.9),
                            border: Border.all(color: mood.outlineSoft),
                            boxShadow: [
                              BoxShadow(
                                color: mood.shadow,
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: IndexedStack(
                            index: _selectedIndex,
                            children: _screens,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: _buildBottomNav(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopHeader(BuildContext context) {
    final theme = Theme.of(context);
    final mood = context.mood;
    final title =
        _selectedIndex == 2 ? 'Pick a game night' : 'Let the room find you';
    final subtitle = _selectedIndex == 2
        ? 'Party games, quick laughs, and lobbies with your people.'
        : 'Casual hangouts, fun rooms, and a warmer Friend Circle vibe.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: const Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF4B5563),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Consumer<AuthProvider>(
              builder: (context, authProvider, _) {
                return PopupMenuButton<String>(
                  offset: const Offset(0, 46),
                  color: theme.colorScheme.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  onSelected: (value) async {
                    if (value == 'logout') {
                      await authProvider.logout();
                      if (context.mounted) {
                        Navigator.pushReplacementNamed(context, '/login');
                      }
                    } else if (value == 'settings') {
                      Navigator.pushNamed(context, '/settings');
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'settings',
                      child: Text('Settings'),
                    ),
                    PopupMenuItem(
                      value: 'logout',
                      child: Text('Logout'),
                    ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.32),
                      ),
                    ),
                    child: UserAvatar(
                      imageUrl: authProvider.user?.avatar,
                      radius: 20,
                      username: authProvider.user?.username ?? '?',
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: _openExploreSearch,
                borderRadius: BorderRadius.circular(26),
                child: Container(
                  height: 58,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: mood.outlineSoft),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      Icon(
                        Icons.search_rounded,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.55),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _selectedIndex == 2
                              ? 'Search games, party tables, hosts'
                              : 'Search user UID, room UID, hosts',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.55),
                          ),
                        ),
                      ),
                      Icon(
                        Icons.tune_rounded,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    final theme = Theme.of(context);
    final mood = context.mood;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: mood.outlineSoft),
        boxShadow: [
          BoxShadow(
            color: mood.shadow,
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: List.generate(_navItems.length, (index) {
          final item = _navItems[index];
          final selected = index == _selectedIndex;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => setState(() => _selectedIndex = index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  padding:
                      const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
                  decoration: BoxDecoration(
                    color: selected
                        ? theme.colorScheme.onSurface
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.16),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ]
                        : const [],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.icon,
                        color: selected
                            ? theme.colorScheme.surface
                            : theme.colorScheme.onSurface
                                .withValues(alpha: 0.56),
                        size: 20,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.label,
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: selected
                                      ? theme.colorScheme.surface
                                      : theme.colorScheme.onSurface
                                          .withValues(alpha: 0.64),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _NavItem {
  const _NavItem({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

class _Orb extends StatelessWidget {
  const _Orb({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
        ),
      ),
    );
  }
}
