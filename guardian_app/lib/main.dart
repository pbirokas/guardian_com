import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:appwrite/appwrite.dart' show Databases;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/appwrite_client.dart';
import 'core/utils/launch_url.dart';
import 'core/providers/app_update_provider.dart';
import 'core/services/app_update_service.dart';
import 'core/models/app_user.dart';
import 'core/providers/connectivity_provider.dart';
import 'core/providers/share_provider.dart';
import 'core/services/share_service.dart';
import 'features/chat/providers/chat_provider.dart';
import 'features/organizations/providers/organizations_provider.dart';
import 'features/relationships/providers/relationships_provider.dart';
import 'features/share/share_picker_sheet.dart';
import 'core/providers/locale_provider.dart' show localeProvider;
import 'core/providers/chat_font_size_provider.dart';
import 'core/providers/scale_provider.dart';
import 'core/providers/theme_provider.dart';
import 'core/router/app_router.dart';
import 'core/services/desktop_notification_service_stub.dart'
    if (dart.library.io) 'core/services/desktop_notification_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/tray_service_stub.dart'
    if (dart.library.io) 'core/services/tray_service.dart';
import 'features/auth/providers/auth_provider.dart';
import 'firebase_options.dart';
import 'package:guardian_app/l10n/app_localizations.dart';

bool get _isDesktop =>
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.linux;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final isDesktop = _isDesktop;

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

class _GuardianAppState extends ConsumerState<GuardianApp>
    with WidgetsBindingObserver {
  bool _wasInBackground = false;
  DateTime? _lastInvalidation;
  ProviderSubscription<AsyncValue<bool>>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForSharedData();
      _connectivitySub = ref.listenManual<AsyncValue<bool>>(
        connectivityProvider,
        (prev, next) {
          final wasOffline = prev?.value == false;
          final isNowOnline = next.value == true;
          if (wasOffline && isNowOnline) _invalidateRealtimeProviders();
        },
      );
    });
  }

  @override
  void dispose() {
    _connectivitySub?.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _invalidateRealtimeProviders() {
    if (ref.read(authStateProvider).value == null) return;
    if (ref.read(connectivityProvider).value != true) return;
    final now = DateTime.now();
    if (_lastInvalidation != null &&
        now.difference(_lastInvalidation!) < const Duration(minutes: 2)) {
      return;
    }
    _lastInvalidation = now;
    // Realtime zuerst invalidieren: neue Services erhalten eine frische Instanz
    // mit _reconnect=true statt der nach _closeConnection() auf false gesetzten.
    ref.invalidate(appwriteRealtimeProvider);
    ref.invalidate(appwriteRealtimeBroadcasterProvider);
    ref.invalidate(chatServiceProvider);
    ref.invalidate(organizationServiceProvider);
    ref.invalidate(parentClaimServiceProvider);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _wasInBackground = true;
    }
    if (state == AppLifecycleState.resumed) {
      NotificationService.clearAll();
      _checkForSharedData();
      if (_wasInBackground) {
        _wasInBackground = false;
        _invalidateRealtimeProviders();
      }
    }
  }

  Future<void> _checkForSharedData() async {
    if (ref.read(authStateProvider).value == null) return;
    final data = await ref.read(shareServiceProvider).getSharedData();
    if (data != null && mounted) {
      ref.read(pendingShareProvider.notifier).set(data);
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider).value ?? const Locale('de');
    NotificationService.setRouter(router);
    if (_isDesktop) DesktopNotificationService.setRouter(router);

    // FCM-Token bei jedem Auth-State-Wechsel refreshen (Token-Rotation).
    // Desktop: Realtime-Listener starten/stoppen je nach Login-Status.
    ref.listen<AsyncValue<AppUser?>>(authStateProvider, (prev, next) {
      final user = next.value;
      final client = ref.read(appwriteClientProvider);
      if (user != null) {
        NotificationService().initialize(Databases(client), user.uid);
        if (_isDesktop) DesktopNotificationService().startListening(client, ref.read(appwriteRealtimeBroadcasterProvider), user.uid);
        // Cold-Start via Share: wenn die App über "Teilen" gestartet wurde,
        // war Auth beim ersten _checkForSharedData()-Aufruf noch nicht geladen.
        // Sobald Auth erstmals verfügbar wird, erneut prüfen.
        if (prev?.value == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _checkForSharedData());
        }
      } else if (!next.isLoading && prev?.value != null) {
        // Nur bei echtem Logout invalidieren (prev war eingeloggt, next ist null).
        // Nicht bei AsyncLoading (Login-Start) oder initialem Laden (prev == null).
        // ref.invalidate während eines Provider-Flush würde eine Rebuild-Kaskade
        // auslösen → Bad state / _skippedNotification assertion.
        if (_isDesktop) DesktopNotificationService().stopListening();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.invalidate(appwriteRealtimeProvider);
          ref.invalidate(appwriteRealtimeBroadcasterProvider);
          ref.invalidate(chatServiceProvider);
          ref.invalidate(organizationServiceProvider);
          ref.invalidate(parentClaimServiceProvider);
        });
      }
    });

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
        final scale = _isDesktop
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

        content = _UpdateListener(child: _ShareListener(child: content));

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

class _ShareListener extends ConsumerWidget {
  final Widget child;

  const _ShareListener({required this.child});

  static final _chatRoutePattern = RegExp(r'^/chat/(.+)$');

  Future<void> _sendDirectToChat(
    WidgetRef ref,
    ShareData shareData,
    String chatId,
    BuildContext navContext,
  ) async {
    final chatService = ref.read(chatServiceProvider);
    final shareService = ref.read(shareServiceProvider);
    try {
      if (shareData.isText) {
        await chatService.sendMessage(chatId, shareData.text!);
      } else {
        for (var i = 0; i < shareData.uris.length; i++) {
          final bytes = await shareService.readUri(shareData.uris[i]);
          if (bytes == null) continue;
          final fileName =
              shareData.fileNames.length > i ? shareData.fileNames[i] : 'file';
          if (shareData.isImage) {
            await chatService.sendImage(chatId, bytes);
          } else {
            await chatService.sendFile(chatId, bytes, fileName, bytes.length);
          }
        }
      }
    } catch (e) {
      if (navContext.mounted) {
        ScaffoldMessenger.of(navContext).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.read(routerProvider);
    ref.listen<ShareData?>(pendingShareProvider, (_, shareData) {
      if (shareData == null) return;
      ref.read(pendingShareProvider.notifier).clear();

      final navContext = router.routerDelegate.navigatorKey.currentContext;
      if (navContext == null) return;

      // Wenn der User gerade in einem Chat ist: direkt dorthin senden,
      // kein Picker zeigen (z. B. GIF-Einfügen über die Tastatur).
      final currentPath = router.routeInformationProvider.value.uri.path;
      final chatMatch = _chatRoutePattern.firstMatch(currentPath);
      if (chatMatch != null) {
        _sendDirectToChat(ref, shareData, chatMatch.group(1)!, navContext);
        return;
      }

      showModalBottomSheet(
        context: navContext,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => SharePickerSheet(shareData: shareData),
      );
    });
    return child;
  }
}

/// Zeigt beim Start einen wegklickbaren „Update empfohlen"-Hinweis, wenn eine
/// neuere (aber nicht erzwungene) Version verfügbar ist. Höchstens 1×/Tag und
/// pro Version wegklickbar (gemerkt in SharedPreferences). Die erzwungene Sperre
/// läuft dagegen über das Router-Gate.
class _UpdateListener extends ConsumerStatefulWidget {
  final Widget child;

  const _UpdateListener({required this.child});

  @override
  ConsumerState<_UpdateListener> createState() => _UpdateListenerState();
}

class _UpdateListenerState extends ConsumerState<_UpdateListener> {
  static const _kLastShown = 'update_prompt_last_shown';
  static const _kDismissedVersion = 'update_prompt_dismissed_version';

  bool _handled = false;

  Future<void> _maybeShowRecommended(AppUpdateStatus status) async {
    if (status.level != UpdateLevel.recommended) return;

    // Kurz warten, bis der Start-Redirect (login → organizations) abgeschlossen
    // ist — sonst räumt die Navigation den frisch geöffneten Dialog sofort weg.
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final versionKey = status.latestVersionName ?? '';
    final today = DateTime.now().toIso8601String().substring(0, 10);

    // Throttle nur im Release-Build: pro Version wegklickbar + höchstens 1×/Tag.
    // Im Debug-Modus übersprungen, damit sich der Hinweis bei jedem Start testen
    // lässt (kein Storage-Leeren / Neu-Login nötig).
    if (!kDebugMode) {
      if (versionKey.isNotEmpty &&
          prefs.getString(_kDismissedVersion) == versionKey) {
        return;
      }
      if (prefs.getString(_kLastShown) == today) return;
    }

    await prefs.setString(_kLastShown, today);

    if (!mounted) return;
    final router = ref.read(routerProvider);
    final navContext = router.routerDelegate.navigatorKey.currentContext;
    if (navContext == null || !navContext.mounted) return;

    final l = AppLocalizations.of(navContext);
    final action = await showDialog<String>(
      context: navContext,
      builder: (ctx) => AlertDialog(
        title: Text(l.updateAvailableTitle),
        content: Text(l.updateRecommendedBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('later'),
            child: Text(l.updateLaterButton),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('update'),
            child: Text(l.updateNowButton),
          ),
        ],
      ),
    );

    // „Später" und „Jetzt aktualisieren" merken die Version → kein erneutes Zeigen
    // für diese Version. Tippt der Nutzer daneben (action == null), greift nur der
    // Tages-Throttle und der Hinweis erscheint am nächsten Tag wieder.
    if (action == 'later' || action == 'update') {
      if (versionKey.isNotEmpty) {
        await prefs.setString(_kDismissedVersion, versionKey);
      }
    }
    if (action == 'update') {
      await openExternalUrl(status.targetUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Erst zeigen, wenn Update-Status geladen UND Auth geklärt ist (damit der
    // Start-Redirect durch ist und den Dialog nicht wieder wegräumt). _handled
    // stellt sicher, dass es genau einmal pro Sitzung passiert.
    final status = ref.watch(appUpdateStatusProvider).value;
    final authSettled = !ref.watch(authStateProvider).isLoading;
    if (!_handled &&
        authSettled &&
        status != null &&
        status.level == UpdateLevel.recommended) {
      _handled = true;
      _maybeShowRecommended(status);
    }
    return widget.child;
  }
}
