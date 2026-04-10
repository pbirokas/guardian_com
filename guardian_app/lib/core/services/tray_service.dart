import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';
import 'package:windows_taskbar/windows_taskbar.dart';

/// Verwaltet das System-Tray-Icon und das Minimieren in die Taskleiste.
/// Wird nur auf Windows/Linux verwendet.
class TrayService with WindowListener {
  static final TrayService instance = TrayService._();
  TrayService._();

  final SystemTray _systemTray = SystemTray();
  bool _initialized = false;
  int _unreadCount = 0;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await windowManager.ensureInitialized();
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);

    await _systemTray.initSystemTray(
      title: '',
      iconPath: 'assets/icon/app_icon.ico',
      toolTip: 'Guardian Com',
    );

    final menu = Menu();
    await menu.buildFrom([
      MenuItemLabel(
        label: 'Öffnen',
        onClicked: (_) => _bringToFront(),
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: 'Beenden',
        onClicked: (_) => _quit(),
      ),
    ]);
    await _systemTray.setContextMenu(menu);

    _systemTray.registerSystemTrayEventHandler((eventName) {
      if (eventName == kSystemTrayEventClick ||
          eventName == kSystemTrayEventDoubleClick) {
        _bringToFront();
      } else if (eventName == kSystemTrayEventRightClick) {
        _systemTray.popUpContextMenu();
      }
    });

    debugPrint('TrayService initialized');
  }

  /// Aktualisiert den Badge-Zähler im Tray-Icon.
  /// count == 0 → normales Icon + Standard-Tooltip
  /// count  > 0 → Badge-Icon + Tooltip mit Anzahl
  Future<void> updateBadge(int count) async {
    if (!_initialized) return;
    if (_unreadCount == count) return;
    _unreadCount = count;

    if (count > 0) {
      // Tray-Icon: Badge-Variante
      await _systemTray.setImage('assets/icon/app_icon_badge.ico');
      await _systemTray.setToolTip(
        'Guardian Com · $count ungelesene Nachricht${count == 1 ? '' : 'en'}',
      );
      // Taskleisten-Symbol: roter Overlay-Badge mit Zahl
      if (!kIsWeb && Platform.isWindows) {
        final label = count > 99 ? '99+' : '$count';
        WindowsTaskbar.setOverlayIcon(
          ThumbnailToolbarAssetIcon('assets/icon/app_icon_badge.ico'),
          tooltip: '$label ungelesene Nachricht${count == 1 ? '' : 'en'}',
        );
        WindowsTaskbar.setFlashTaskbarAppIcon(
          mode: TaskbarFlashMode.tray | TaskbarFlashMode.timer,
          flashCount: 3,
        );
      }
    } else {
      // Tray-Icon: normales Icon
      await _systemTray.setImage('assets/icon/app_icon.ico');
      await _systemTray.setToolTip('Guardian Com');
      // Taskleisten-Symbol: Overlay entfernen
      if (!kIsWeb && Platform.isWindows) {
        WindowsTaskbar.resetOverlayIcon();
        WindowsTaskbar.resetFlashTaskbarAppIcon();
      }
    }
  }

  Future<void> _bringToFront() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _quit() async {
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  @override
  void onWindowClose() async {
    await windowManager.hide();
  }

  void dispose() {
    windowManager.removeListener(this);
    _initialized = false;
  }
}
