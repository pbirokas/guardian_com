import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// iPhone, iPod oder iPad. iPadOS meldet sich als „Macintosh“ — dort hilft
/// nur die Touch-Erkennung.
bool get isAppleMobileBrowser {
  final nav = web.window.navigator;
  final ua = nav.userAgent;
  if (RegExp('iPhone|iPad|iPod').hasMatch(ua)) return true;
  return ua.contains('Macintosh') && nav.maxTouchPoints > 1;
}

/// Läuft die Seite als installierte App (vom Home-Bildschirm gestartet)?
/// Safari kennt dafür das nicht standardisierte `navigator.standalone`.
bool get isRunningAsInstalledPwa {
  if (web.window.matchMedia('(display-mode: standalone)').matches) return true;
  final standalone =
      (web.window.navigator as JSObject).getProperty<JSAny?>('standalone'.toJS);
  return standalone.dartify() == true;
}
