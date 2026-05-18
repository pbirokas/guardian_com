import 'package:flutter/material.dart';
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
import '../../features/relationships/screens/relationships_screen.dart';
import '../../features/relationships/screens/child_summary_screen.dart';

class _AuthNotifier extends ChangeNotifier {
  _AuthNotifier(this._ref) {
    _ref.listen<AsyncValue<dynamic>>(authStateProvider, (prev, next) {
      notifyListeners();
    });
  }
  final Ref _ref;
}

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthNotifier(ref);
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: notifier,
    onException: (context, state, router) {
      final isLoggedIn = ref.read(authStateProvider).value != null;
      router.go(isLoggedIn ? '/organizations' : '/login');
    },
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      if (authState.isLoading) return null;
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
      GoRoute(
        path: '/relationships',
        builder: (context, state) => const RelationshipsScreen(),
      ),
      GoRoute(
        path: '/child-summary/:childUid',
        builder: (context, state) => ChildSummaryScreen(
          childUid: state.pathParameters['childUid']!,
          childName: state.extra as String? ?? '',
        ),
      ),
    ],
  );
});
