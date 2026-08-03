import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/connection_error_screen.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/organizations/screens/organizations_screen.dart';
import '../../features/organizations/screens/organization_detail_screen.dart';
import '../../features/chat/screens/chat_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/profile/screens/notifications_screen.dart';
import '../../features/profile/screens/privacy_screen.dart';
import '../../features/relationships/screens/relationships_screen.dart';
import '../../features/relationships/screens/child_summary_screen.dart';
import '../../features/update/update_required_screen.dart';
import '../providers/app_update_provider.dart';
import '../services/app_update_service.dart';

class _AuthNotifier extends ChangeNotifier {
  _AuthNotifier(this._ref) {
    _ref.listen<AsyncValue<dynamic>>(authStateProvider, (prev, next) {
      notifyListeners();
    });
    // Löst eine Router-Neubewertung aus, sobald der Update-Status geladen ist
    // (für die Force-Update-Sperre unten).
    _ref.listen<AsyncValue<dynamic>>(appUpdateStatusProvider, (prev, next) {
      notifyListeners();
    });
  }
  final Ref _ref;
}

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthNotifier(ref);
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: notifier,
    onException: (context, state, router) {
      final isLoggedIn = ref.read(authStateProvider).value != null;
      router.go(isLoggedIn ? '/organizations' : '/login');
    },
    redirect: (context, state) {
      final isOnUpdate = state.uri.path == '/update-required';
      final needsUpdate = ref.read(appUpdateStatusProvider).value?.level ==
          UpdateLevel.required;

      // Force-Update hat Vorrang vor allem anderen.
      if (needsUpdate) return isOnUpdate ? null : '/update-required';
      // Kein (erzwungenes) Update mehr nötig → von der Sperr-Seite weiterleiten.
      if (isOnUpdate) {
        final isLoggedIn = ref.read(authStateProvider).value != null;
        return isLoggedIn ? '/organizations' : '/login';
      }

      final authState = ref.read(authStateProvider);
      final path = state.uri.path;
      final isOnSplash = path == '/splash';
      final isOnConnError = path == '/connection-error';

      // Solange der Session-Check läuft: Splash zeigen (nicht Login). Beim
      // Retry auf dem Verbindungs-Screen dort bleiben (er hat einen eigenen
      // Ladeindikator).
      if (authState.isLoading) {
        return (isOnSplash || isOnConnError) ? null : '/splash';
      }

      // Verbindungs-/Serverfehler (kein echter 401): Session-Status unbekannt →
      // Verbindungs-Screen statt Login, damit die Anmeldung erhalten bleibt.
      if (authState.hasError) return isOnConnError ? null : '/connection-error';

      final isLoggedIn = authState.value != null;
      final isOnLogin = path == '/login';
      // Nach Auflösung von Splash/Fehlerseite normal weiterleiten.
      if (isOnSplash || isOnConnError) {
        return isLoggedIn ? '/organizations' : '/login';
      }
      if (!isLoggedIn && !isOnLogin) return '/login';
      if (isLoggedIn && isOnLogin) return '/organizations';
      return null;
    },
    routes: [
      GoRoute(
        path: '/update-required',
        builder: (context, state) => const UpdateRequiredScreen(),
      ),
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/connection-error',
        builder: (context, state) => const ConnectionErrorScreen(),
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
