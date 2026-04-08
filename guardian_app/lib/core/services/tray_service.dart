import 'package:flutter/foundation.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';

/// Verwaltet das System-Tray-Icon und das Minimieren in die Taskleiste.
/// Wird nur auf Windows/Linux verwendet.
class TrayService with WindowListener {
  static final TrayService instance = TrayService._();
  TrayService._();

  final SystemTray _systemTray = SystemTray();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Fenster-Manager einrichten: Schließen → in Tray minimieren
    await windowManager.ensureInitialized();
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);

    // Tray-Icon initialisieren
    // Hinweis: Für Windows wird eine .ico-Datei benötigt.
    // Die PNG-Datei aus assets/icon/ muss in eine ICO-Datei konvertiert werden.
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

    // Einfacher Klick / Doppelklick → Fenster anzeigen
    _systemTray.registerSystemTrayEventHandler((eventName) {
      if (eventName == kSystemTrayEventClick ||
          eventName == kSystemTrayEventDoubleClick) {
        _bringToFront();
      }
    });

    debugPrint('TrayService initialized');
  }

  Future<void> _bringToFront() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _quit() async {
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  // Wenn der Nutzer auf X klickt → Fenster ausblenden statt beenden
  @override
  void onWindowClose() async {
    await windowManager.hide();
  }

  void dispose() {
    windowManager.removeListener(this);
    _initialized = false;
  }
}
