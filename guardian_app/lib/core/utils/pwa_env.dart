/// Erkennt, ob die Web-App im iPhone/iPad-Browser läuft und ob sie bereits
/// als App (PWA) zum Home-Bildschirm hinzugefügt wurde. Nativ immer `false`.
library;

export 'pwa_env_stub.dart' if (dart.library.js_interop) 'pwa_env_web.dart';
