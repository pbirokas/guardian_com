import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/organizations/screens/organizations_screen.dart';
import '../../features/organizations/screens/organization_detail_screen.dart';
import '../../features/chat/screens/chat_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/profile/screens/notifications_screen.dart';
import '../../features/profile/screens/privacy_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/login',
    // Firebase Auth Deep Links (/__/auth/...) sind keine App-Routen.
    // Werden von app_links im Hintergrund verarbeitet.
    // onException fängt den GoException ab und navigiert zur passenden Seite.
    onException: (context, state, router) {
      router.go(authState.value != null ? '/organizations' : '/login');
    },
    redirect: (context, state) {
      // Firebase Auth Deep Links vor dem Route-Matching abfangen
      if (state.uri.path.startsWith('/__/auth/')) {
        return authState.value != null ? '/organizations' : '/login';
      }
      final isLoggedIn = authState.value != null;
      final isOnLogin = state.uri.path == '/login';
      if (!isLoggedIn && !isOnLogin) return '/login';
      if (isLoggedIn && isOnLogin) return '/organizations';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/organizations',
        builder: (context, state) => const OrganizationsScreen(),
      ),
      GoRoute(
        path: '/org/:orgId',
        builder: (context, state) =>
            OrganizationDetailScreen(orgId: state.pathParameters['orgId']!),
      ),
      GoRoute(
        path: '/chat/:chatId',
        builder: (context, state) => ChatScreen(
          chatId: state.pathParameters['chatId']!,
          partnerName: state.extra as String?,
        ),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/settings/notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/settings/privacy',
        builder: (context, state) => const PrivacyScreen(),
      ),
    ],
  );
});
