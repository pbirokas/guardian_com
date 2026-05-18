import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/io.dart';

const appwriteEndpoint = 'https://appwrite.guardian-com.de/v1';
const appwriteProjectId = '6a02e4160023948ef257';
const appwriteMediaBucketId = '6a02e524000954c9f1de';

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

    return IOWebSocketChannel(
        await WebSocket.connect(wsUri.toString(), headers: headers));
  };

  dyn.getFallbackCookie = () => _realtimeSessionCookie;

  return realtime;
}
