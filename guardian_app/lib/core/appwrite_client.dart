import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/io.dart';

const appwriteEndpoint = 'https://appwrite.guardian-com.de/v1';
const appwriteProjectId = '6a02e4160023948ef257';
const appwriteMediaBucketId = '6a02e524000954c9f1de';

/// Öffentliche View-URL einer Datei im Media-Bucket (Profil-/Gruppen-/Chatbilder).
String appwriteFileViewUrl(String fileId) =>
    '$appwriteEndpoint/storage/buckets/$appwriteMediaBucketId/files/$fileId/view?project=$appwriteProjectId';

final _appwriteStorageHost = Uri.parse(appwriteEndpoint).host;

/// Einzige Quelle der Wahrheit für „darf ein Bild von diesem Host geladen werden".
/// Aktueller Speicher ist Appwrite (Host aus [appwriteEndpoint] abgeleitet);
/// firebasestorage bleibt vorerst erlaubt für Alt-URLs, bis das Reset-Skript sie
/// entfernt (sie liefern ohnehin 402 → Avatar fällt crash-sicher auf Fallback zurück).
bool isTrustedStorageHost(String url) {
  final host = Uri.tryParse(url)?.host ?? '';
  return host == _appwriteStorageHost || host == 'firebasestorage.googleapis.com';
}

// Cached session cookie value for Realtime WebSocket fallback auth.
// RealtimeIO doesn't set getFallbackCookie (unlike RealtimeBrowser), so the
// WebSocket upgrade may go out unauthenticated on reconnects. We cache the
// session secret here and pass it via the post-connect authentication message.
String? _realtimeSessionCookie;

final appwriteClientProvider = Provider<Client>((ref) {
  return Client()
      .setEndpoint(appwriteEndpoint)
      .setProject(appwriteProjectId);
});

final appwriteRealtimeProvider = Provider<Realtime>((ref) {
  return createPatchedRealtime(ref.watch(appwriteClientProvider));
});

final appwriteStorageProvider = Provider<Storage>((ref) {
  return Storage(ref.watch(appwriteClientProvider));
});

/// Ref-counted Realtime channel multiplexer.
/// Multiple concurrent listeners to the same channel share one WebSocket slot;
/// the Realtime subscription is opened on the first listen and cancelled
/// automatically when the last listener unsubscribes.
class RealtimeBroadcaster {
  RealtimeBroadcaster(this._realtime);

  final Realtime _realtime;
  final Map<String, Stream<dynamic>> _cache = {};

  Stream<dynamic> stream(String channel) {
    return _cache.putIfAbsent(channel, () {
      // LinkedHashSet.identity(): O(1) add/remove by object identity.
      final sinks = LinkedHashSet<MultiStreamController<dynamic>>.identity();
      StreamSubscription<dynamic>? sub;
      // Guard against reentrant cancellation during fan-out: if a listener
      // cancels synchronously inside its onData, defer the remove until after
      // the current dispatch loop finishes to avoid concurrent modification.
      bool dispatching = false;
      final deferred = <MultiStreamController<dynamic>>[];

      void fanOut(void Function(MultiStreamController<dynamic>) fn) {
        dispatching = true;
        for (final s in sinks) {
          if (!s.isClosed) fn(s);
        }
        dispatching = false;
        for (final s in deferred) { sinks.remove(s); }
        deferred.clear();
        if (sinks.isEmpty) {
          sub?.cancel();
          sub = null;
          _cache.remove(channel);
        }
      }

      return Stream<dynamic>.multi(
        (controller) {
          if (sinks.isEmpty) {
            sub = _realtime.subscribe([channel]).stream.listen(
              (event) => fanOut((s) => s.add(event)),
              onDone: () {
                // Clean up cache first so any onCancel triggered by s.close()
                // finds sub == null and _cache already evicted (both no-ops).
                sub = null;
                _cache.remove(channel);
                for (final s in List.of(sinks)) {
                  if (!s.isClosed) s.close();
                }
                sinks.clear();
              },
              onError: (Object e, StackTrace st) =>
                  fanOut((s) => s.addError(e, st)),
            );
          }
          sinks.add(controller);
          controller.onCancel = () {
            if (dispatching) {
              deferred.add(controller);
            } else {
              sinks.remove(controller);
              if (sinks.isEmpty) {
                sub?.cancel();
                sub = null;
                _cache.remove(channel);
              }
            }
          };
        },
        isBroadcast: true,
      );
    });
  }
}

final appwriteRealtimeBroadcasterProvider = Provider<RealtimeBroadcaster>((ref) {
  return RealtimeBroadcaster(ref.watch(appwriteRealtimeProvider));
});

/// Call after every successful login/session-restore to cache the Appwrite
/// session cookie so Realtime can use it for post-connect authentication.
Future<void> cacheRealtimeSessionCookie(Client client) async {
  try {
    final dynamic cookieJar = (client as dynamic).cookieJar;
    final cookies =
        await cookieJar.loadForRequest(Uri.parse(appwriteEndpoint))
            as List<dynamic>;

    // Prefer non-legacy cookie — its value IS the raw session secret.
    for (final cookie in cookies) {
      final name = cookie.name as String;
      if (name.startsWith('a_session_') && !name.endsWith('_legacy')) {
        _realtimeSessionCookie = cookie.value as String;
        return;
      }
    }

    // Fall back to legacy cookie: value is urlencode(base64(userId:secret)).
    // Decode to extract just the secret, which is what the server expects.
    for (final cookie in cookies) {
      final name = cookie.name as String;
      if (name.startsWith('a_session_') && name.endsWith('_legacy')) {
        final secret = _decodeSessionSecret(cookie.value as String);
        if (secret != null) {
          _realtimeSessionCookie = secret;
          return;
        }
      }
    }
  } catch (e) {
    debugPrint('[Realtime] cacheRealtimeSessionCookie failed: $e');
  }
}

// Legacy cookie format: urlencode(base64(userId:secret)) — extract the secret.
String? _decodeSessionSecret(String legacyValue) {
  try {
    final decoded = utf8.decode(base64.decode(Uri.decodeComponent(legacyValue)));
    final i = decoded.indexOf(':');
    if (i != -1) return decoded.substring(i + 1);
  } catch (_) {}
  return null;
}

void clearRealtimeSessionCookie() => _realtimeSessionCookie = null;

/// Creates a Realtime instance that correctly authenticates the WebSocket.
///
/// RealtimeIO builds the WebSocket URI with wss:// but the cookie jar stores
/// cookies under https://, so loadForRequest(wssUri) returns nothing — the
/// upgrade goes out unauthenticated. We replace getWebSocket with a version
/// that loads cookies from the https:// equivalent URI instead, and set
/// getFallbackCookie so the SDK sends an auth message on reconnects.
Realtime createPatchedRealtime(Client client) {
  final realtime = Realtime(client);
  final dynamic dyn = realtime;

  dyn.getWebSocket = (Uri wsUri) async {
    final dynamic c = client;
    // Mirror the init-wait logic from RealtimeIO._getWebSocket
    while (c.initProgress == true && c.initialized != true) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    if (c.initialized != true) await c.init();

    // Load cookies from https:// (where PersistCookieJar actually stores them)
    final httpsUri =
        wsUri.replace(scheme: wsUri.scheme == 'wss' ? 'https' : 'http');
    final dynamic jar = c.cookieJar;
    final rawCookies = await jar.loadForRequest(httpsUri) as List<dynamic>;
    final cookieStr = rawCookies
        .map((cookie) => '${(cookie as dynamic).name}=${(cookie as dynamic).value}')
        .join('; ');

    final headers = cookieStr.isNotEmpty
        ? {HttpHeaders.cookieHeader: cookieStr}
        : <String, String>{};

    // Dart doesn't register a default port for the wss/ws schemes (only for
    // http/https), so wsUri.port is 0 when no explicit port was given.
    // WebSocket.connect converts wss:// → https:// internally while preserving
    // the port, which produces "https://host:0/..." and fails immediately.
    // Fix: add the standard port before connecting, but keep wsUri unchanged
    // above so httpsUri (used for cookie lookup) still has no explicit port —
    // matching the cookies stored under https://host/v1 (no explicit port).
    final connectUri = wsUri.port == 0
        ? wsUri.replace(port: wsUri.scheme == 'wss' ? 443 : 80)
        : wsUri;

    return IOWebSocketChannel(
        await WebSocket.connect(connectUri.toString(), headers: headers));
  };

  dyn.getFallbackCookie = () => _realtimeSessionCookie;

  return realtime;
}
