import 'package:go_router/go_router.dart';

final _chatPathPattern = RegExp(r'^/chat/([^/]+)$');

/// Liefert die Chat-ID, wenn [path] eine Chat-Route ist, sonst `null`.
String? chatIdFromPath(String path) =>
    _chatPathPattern.firstMatch(path)?.group(1);

/// Pfad der **obersten** Seite. `router.state` berücksichtigt per `push`
/// gestapelte Routen — `routerDelegate.currentConfiguration.uri` dagegen
/// bleibt beim Pfad der Basis-Route (z. B. `/org/…`), wenn der Chat per
/// `context.push` geöffnet wurde. Leer, solange der Router noch keine Route hat.
String currentTopPath(GoRouter router) {
  try {
    return router.state.uri.path;
  } catch (_) {
    return '';
  }
}

/// ID des Chats, der gerade die oberste Seite ist, sonst `null`.
String? openChatId(GoRouter router) => chatIdFromPath(currentTopPath(router));

/// Entscheidet, wie ein Chat aus einer Benachrichtigung geöffnet wird, ohne
/// Chat-Seiten zu stapeln (sonst braucht es mehrere „Zurück", um den Chat zu
/// verlassen).
enum ChatOpenAction {
  /// Der Chat ist bereits die oberste Seite → nichts tun.
  none,

  /// Ein anderer Chat liegt oben → ersetzen statt stapeln.
  replace,

  /// Kein Chat offen → normal auf den Stapel legen.
  push,
}

ChatOpenAction chatOpenActionFor(String currentPath, String convId) {
  final openChatId = chatIdFromPath(currentPath);
  if (openChatId == null) return ChatOpenAction.push;
  return openChatId == convId ? ChatOpenAction.none : ChatOpenAction.replace;
}

/// Öffnet [convId] aus einer Benachrichtigung. „Zurück" führt danach immer
/// auf die Seite unter dem Chat (Übersicht), egal wie viele Benachrichtigungen
/// zuvor geöffnet wurden.
void openChatFromNotification(GoRouter router, String convId, {String? title}) {
  // Leer, wenn der Router noch keine Route aufgebaut hat (sehr früher Kaltstart).
  final currentPath = currentTopPath(router);
  final location = '/chat/$convId';
  switch (chatOpenActionFor(currentPath, convId)) {
    case ChatOpenAction.none:
      return;
    case ChatOpenAction.replace:
      router.pushReplacement(location, extra: title);
    case ChatOpenAction.push:
      router.push(location, extra: title);
  }
}
