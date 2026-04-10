import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/providers/theme_provider.dart';
import 'core/router/app_router.dart';
import 'core/services/auth_service.dart';
import 'core/services/desktop_notification_service_stub.dart'
    if (dart.library.io) 'core/services/desktop_notification_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/tray_service_stub.dart'
    if (dart.library.io) 'core/services/tray_service.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // App Check wird nur auf Android und Web unterstützt (nicht auf Windows/Linux).
  if (kIsWeb || defaultTargetPlatform == TargetPlatform.android) {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
      providerWeb: kDebugMode ? WebDebugProvider() : null,
    );
  }

  final isDesktop = !kIsWeb && (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux);

  // Crashlytics und FCM nur auf mobilen Plattformen (nicht Web, nicht Desktop)
  if (!kIsWeb && !isDesktop) {
    await FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(!kDebugMode);
    FlutterError.onError =
        FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };

    // FCM Background-Handler nur auf mobilen Plattformen registrieren
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  if (isDesktop) {
    await TrayService.instance.initialize();
    await DesktopNotificationService().initialize();
  }

  final savedTheme = await loadSavedThemeMode();

  final app = ProviderScope(
    overrides: [
      themeModeProvider.overrideWith(() => ThemeModeNotifier(savedTheme)),
    ],
    child: const GuardianApp(),
  );

  runApp(app);
}

class GuardianApp extends ConsumerStatefulWidget {
  const GuardianApp({super.key});

  @override
  ConsumerState<GuardianApp> createState() => _GuardianAppState();
}

class _GuardianAppState extends ConsumerState<GuardianApp> {
  AppLinks? _appLinks;
  StreamSubscription? _linkSub;

  @override
  void initState() {
    super.initState();
    // App Links nur auf Plattformen mit Deep-Link-Support
    if (!kIsWeb &&
        defaultTargetPlatform != TargetPlatform.windows &&
        defaultTargetPlatform != TargetPlatform.linux) {
      _appLinks = AppLinks();
      _handleIncomingLinks();
    }
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  void _handleIncomingLinks() {
    _appLinks?.getInitialLink().then((uri) {
      if (uri != null) _processEmailLink(uri);
    });
    _linkSub = _appLinks?.uriLinkStream.listen((uri) {
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
    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux)) {
      DesktopNotificationService.setRouter(router);
    }

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
