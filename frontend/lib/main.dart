import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'theme/app_theme.dart';
import 'screens/auth/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/main_screen.dart';
import 'screens/wallet/wallet_screen.dart';
import 'screens/wallet/transactions_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/settings/account_settings_screen.dart';
import 'screens/settings/change_password_screen.dart';
import 'screens/settings/notification_settings_screen.dart';
import 'screens/settings/privacy_settings_screen.dart';
import 'screens/settings/quiet_hours_screen.dart';
import 'screens/settings/language_settings_screen.dart';
import 'screens/settings/support_screen.dart';
import 'screens/explore/explore_screen.dart';
import 'screens/rooms/rooms_screen.dart';
import 'screens/groups/groups_screen.dart';
import 'screens/groups/group_detail_screen.dart';
import 'screens/nearby/nearby_screen.dart';
import 'screens/friends/friends_screen.dart';
import 'screens/messages/conversations_screen.dart';
import 'screens/profile/enhanced_profile_screen.dart';
import 'screens/profile/visitors_screen.dart';
import 'screens/profile/badges_screen.dart';
import 'screens/profile/game_stats_screen.dart';
import 'screens/rankings/rankings_screen.dart';
import 'screens/rooms/create_room_screen.dart';
import 'screens/gifts/gift_history_screen.dart';
import 'screens/gifts/gift_leaderboard_screen.dart';
import 'screens/gifts/gift_achievements_screen.dart';
import 'screens/vip/vip_screen.dart';
import 'screens/economy/daily_rewards_screen.dart';
import 'screens/economy/quests_screen.dart';
import 'screens/posts/create_post_screen.dart';
import 'screens/posts/feed_screen.dart';
import 'screens/auth/otp_screen.dart';
import 'screens/auth/auth_callback_screen.dart';
import 'screens/wedding/wedding_screen.dart';

import 'services/app_route_observer.dart';
import 'widgets/error_boundary.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize error reporting, analytics, etc. here

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ],
      child: ErrorBoundary(
        child: MaterialApp(
          title: 'Friend Circle',
          debugShowCheckedModeBanner: false,
          navigatorObservers: [appRouteObserver],
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: ThemeMode.system,
          initialRoute: '/',
          routes: {
            '/': (context) => const SplashScreen(),
            '/login': (context) => const LoginScreen(),
            '/register': (context) => const RegisterScreen(),
            '/otp': (context) {
              final phone =
                  ModalRoute.of(context)!.settings.arguments as String;
              return OTPScreen(phone: phone);
            },
            '/auth-callback': (context) => const AuthCallbackScreen(),
            '/home': (context) => const MainScreen(),
            '/wallet': (context) => const WalletScreen(),
            '/wallet/transactions': (context) => const TransactionsScreen(),
            '/settings': (context) => const SettingsScreen(),
            '/settings/account': (context) => AccountSettingsScreen(
                  settings: const {},
                  onUpdate: () {},
                ),
            '/settings/password': (context) => const ChangePasswordScreen(),
            '/settings/notifications': (context) => NotificationSettingsScreen(
                  settings: const {},
                  onUpdate: () {},
                ),
            '/settings/privacy': (context) => PrivacySettingsScreen(
                  settings: const {},
                  onUpdate: () {},
                ),
            '/settings/quiet-hours': (context) => QuietHoursScreen(
                  settings: const {},
                  onUpdate: () {},
                ),
            '/settings/language': (context) => LanguageSettingsScreen(
                  settings: const {},
                  onUpdate: () {},
                ),
            '/settings/support': (context) => const SupportScreen(),
            '/explore': (context) => const ExploreScreen(),
            '/rooms': (context) => const RoomsScreen(),
            '/groups': (context) => const GroupsScreen(),
            '/nearby': (context) => const NearbyScreen(),
            '/friends': (context) => const FriendsScreen(),
            '/groups/detail': (context) {
              final args = ModalRoute.of(context)!.settings.arguments as String;
              return GroupDetailScreen(groupId: args);
            },
            '/rooms/create': (context) => const CreateRoomScreen(),
            '/gifts/history': (context) => const GiftHistoryScreen(),
            '/gifts/leaderboard': (context) => const GiftLeaderboardScreen(),
            '/gifts/achievements': (context) => const GiftAchievementsScreen(),
            '/vip': (context) => const VipScreen(),
            '/daily-rewards': (context) => const DailyRewardsScreen(),
            '/quests': (context) => const QuestsScreen(),
            '/messages': (context) => const ConversationsScreen(),
            '/feed': (context) => const FeedScreen(),
            '/posts/create': (context) => const CreatePostScreen(),
            '/profile/:userId': (context) {
              final userId =
                  ModalRoute.of(context)?.settings.arguments as String?;
              return EnhancedProfileScreen(userId: userId);
            },
            '/profile': (context) {
              final userId =
                  ModalRoute.of(context)?.settings.arguments as String?;
              return EnhancedProfileScreen(userId: userId);
            },
            '/visitors': (context) {
              final args =
                  ModalRoute.of(context)?.settings.arguments as List? ??
                      const [];
              return VisitorsScreen(visitors: args);
            },
            '/badges': (context) {
              final args = ModalRoute.of(context)!.settings.arguments as List;
              return BadgesScreen(badges: args);
            },
            '/game-stats': (context) {
              final args = ModalRoute.of(context)!.settings.arguments
                  as Map<String, dynamic>;
              return GameStatsScreen(gameStats: args);
            },
            '/rankings': (context) => const RankingsScreen(),
            '/mingle': (context) => const WeddingScreen(),
            '/wedding': (context) => const WeddingScreen(),
          },
        ),
      ),
    );
  }
}
