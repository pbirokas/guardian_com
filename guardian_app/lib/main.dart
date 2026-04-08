import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/providers/theme_provider.dart';
import 'core/router/app_router.dart';
import 'core/services/auth_service.dart';
import 'core/services/notification_service.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // ── Crashlytics ─────────────────────────────────────────────────────────────
  // Im Debug-Modus Berichte deaktivieren, damit die Console nicht überflutet wird.
  await FirebaseCrashlytics.instance
      .setCrashlyticsCollectionEnabled(!kDebugMode);

  // Flutter-Fehler (Widget-Fehler, etc.) an Crashlytics weiterleiten
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  final savedTheme = await loadSavedThemeMode();

  // Dart-Fehler außerhalb des Flutter-Frameworks abfangen (async, isolates)
  await runZonedGuarded(
    () async {
      runApp(ProviderScope(
        overrides: [
          themeModeProvider.overrideWith(() => ThemeModeNotifier(savedTheme)),
        ],
        child: const GuardianApp(),
      ));
    },
    (error, stack) =>
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true),
  );
}

class GuardianApp extends ConsumerStatefulWidget {
  const GuardianApp({super.key});

  @override
  ConsumerState<GuardianApp> createState() => _GuardianAppState();
}

class _GuardianAppState extends ConsumerState<GuardianApp> {
  final _appLinks = AppLinks();
  StreamSubscription? _linkSub;

  @override
  void initState() {
    super.initState();
    _handleIncomingLinks();
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  void _handleIncomingLinks() {
    // App wurde über einen Link geöffnet (cold start)
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) _processEmailLink(uri);
    });

    // App läuft bereits und Link wird geöffnet (warm start)
    _linkSub = _appLinks.uriLinkStream.listen((uri) {
      _processEmailLink(uri);
    });
  }

  Future<void> _processEmailLink(Uri link) async {
    try {
      await AuthService().handleEmailLink(link);
    } catch (e) {
      debugPrint('E-Mail-Link-Login fehlgeschlagen: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    NotificationService.setRouter(router);

    const seedColor = Colors.blue;

    return MaterialApp.router(
      title: 'Guardian Com',
      debugShowCheckedModeBanner: false,

      themeMode: themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}
