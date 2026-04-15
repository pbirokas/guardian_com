import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/providers/connectivity_provider.dart';
import 'core/providers/locale_provider.dart' show localeProvider;
import 'core/providers/chat_font_size_provider.dart';
import 'core/providers/scale_provider.dart';
import 'core/providers/theme_provider.dart';
import 'core/router/app_router.dart';
import 'core/services/auth_service.dart';
import 'core/services/desktop_notification_service_stub.dart'
    if (dart.library.io) 'core/services/desktop_notification_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/tray_service_stub.dart'
    if (dart.library.io) 'core/services/tray_service.dart';
import 'firebase_options.dart';
import 'package:guardian_app/l10n/app_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // App Check wird nur auf Android unterstützt (nicht auf Windows/Linux).
  if (defaultTargetPlatform == TargetPlatform.android) {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
    );
  }

  final isDesktop = defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;

  // Crashlytics und FCM nur auf mobilen Plattformen (nicht Desktop)
  if (!isDesktop) {
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
  final savedScale = await loadSavedScaleFactor();
  final savedChatFontSize = await loadSavedChatFontSize();

  final app = ProviderScope(
    overrides: [
      themeModeProvider.overrideWith(() => ThemeModeNotifier(savedTheme)),
      scaleFactorProvider.overrideWith(() => ScaleFactorNotifier(savedScale)),
      chatFontSizeProvider.overrideWith(() => ChatFontSizeNotifier(savedChatFontSize)),
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
    if (defaultTargetPlatform != TargetPlatform.windows &&
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
    final locale = ref.watch(localeProvider).value ?? const Locale('de');
    NotificationService.setRouter(router);
    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux) {
      DesktopNotificationService.setRouter(router);
    }

    const seedColor = Colors.blue;
    final isOnline = ref.watch(connectivityProvider).value ?? true;

    return MaterialApp.router(
      title: 'Guardian Com',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
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
      builder: (context, child) {
        final l = AppLocalizations.of(context);
        final isDesktopPlatform =
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux;
        final scale = isDesktopPlatform
            ? ref.watch(scaleFactorProvider)
            : 1.0;
        final mq = MediaQuery.of(context);

        Widget content = Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: isOnline ? 0 : 28,
              color: Colors.red.shade700,
              child: isOnline
                  ? const SizedBox.shrink()
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.wifi_off,
                            size: 14, color: Colors.white),
                        const SizedBox(width: 6),
                        Text(
                          l.noConnection,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
            ),
            Expanded(child: child!),
          ],
        );

        if (scale == 1.0) return content;

        // Apply UI scaling.
        //
        // Problem: MaterialApp passes TIGHT constraints (exactly the window
        // size) down the tree. A plain SizedBox(w/scale, h/scale) cannot
        // satisfy tight constraints that are LARGER than its configured size,
        // so it silently renders at the full window size. After
        // Transform.scale(1.25) the content then overflows 25% beyond the
        // window edge, hiding the AppBar actions and FABs.
        //
        // Fix: OverflowBox breaks the tight-constraint chain by forwarding
        // LOOSE constraints (0..scaledSize) to its child, allowing the inner
        // SizedBox to actually constrain the layout to scaledSize.
        // Transform.scale then zooms that smaller canvas back up to fill the
        // physical window. MediaQuery.size is overridden so that dialogs,
        // bottom sheets and other overlay widgets position themselves relative
        // to the smaller logical size.
        final scaledSize = Size(mq.size.width / scale, mq.size.height / scale);
        return Transform.scale(
          scale: scale,
          alignment: Alignment.topLeft,
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: 0,
            maxWidth: scaledSize.width,
            minHeight: 0,
            maxHeight: scaledSize.height,
            child: MediaQuery(
              data: mq.copyWith(size: scaledSize),
              child: SizedBox(
                width: scaledSize.width,
                height: scaledSize.height,
                child: content,
              ),
            ),
          ),
        );
      },
    );
  }
}
