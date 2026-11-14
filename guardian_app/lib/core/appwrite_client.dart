import 'dart:async';
import 'dart:collection';

import 'package:appwrite/appwrite.dart';
// HttpMethod wird vom SDK nicht öffentlich exportiert (nur für executeRaw).
// ignore: implementation_imports
import 'package:appwrite/src/enums.dart' show HttpMethod;
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Realtime-Cookie-Workaround nur nativ; im Web reicht der Standard-Realtime.
import 'realtime_patch_web.dart'
    if (dart.library.io) 'realtime_patch_io.dart';
export 'realtime_patch_web.dart'
    if (dart.library.io) 'realtime_patch_io.dart'
    show cacheRealtimeSessionCookie, clearRealtimeSessionCookie;

const appwriteEndpoint = 'https://appwrite.guardian-com.de/v1';
const appwriteProjectId = '6a02e4160023948ef257';
const appwriteMediaBucketId = '6a02e524000954c9f1de';

/// Ergebnis einer Function-Execution: HTTP-Status und Body der Function-Antwort.
typedef FunctionResult = ({int statusCode, String body});

extension FunctionsRawExecution on Functions {
  /// Ersatz für [Functions.createExecution]: ruft denselben Endpoint auf, liest
  /// aber nur `responseStatusCode`/`responseBody` statt das strikte
  /// `Execution`-Model zu bauen. SDK 26.x erwartet dort `resourceType`, das
  /// Server 1.9.x nicht liefert (sendet noch `functionId`) → `fromMap` wirft
  /// `StateError: No element`, obwohl die Function erfolgreich lief.
  /// (SDK-Bug: es fordert selbst Response-Format 1.9.6 an.)
  /// Bei `xasync: true` ist das Ergebnis `(statusCode: 0, body: '')`.
  /// Bei jedem SDK-/Server-Upgrade prüfen, ob `Execution.fromMap` wieder mit
  /// unserem Server funktioniert → dann zurück auf `createExecution`. Header
  /// spiegeln `Functions.createExecution` (SDK 26.1) — bei SDK-Bumps abgleichen.
  Future<FunctionResult> executeRaw({
    required String functionId,
    String? body,
    bool xasync = false,
  }) async {
    final res = await client.call(
      HttpMethod.post,
      path: '/functions/$functionId/executions',
      params: {
        'body': ?body,
        'async': xasync,
        'method': 'POST',
      },
      headers: {
        // SDK 26 setzt den Projekt-Header nicht mehr global (setProject füllt
        // nur config), sondern jede Service-Methode pro Request. Ohne ihn
        // prüft der Server gegen das Console-Projekt → 403 "Invalid Origin".
        'X-Appwrite-Project': client.config['project'] ?? '',
        'content-type': 'application/json',
        'accept': 'application/json',
      },
    );
    final data = res.data as Map;
    return (
      statusCode: (data['responseStatusCode'] as num?)?.toInt() ?? 0,
      body: data['responseBody']?.toString() ?? '',
    );
  }
}

/// Öffentliche View-URL einer Datei im Media-Bucket (Profil-/Gruppen-/Chatbilder).
String appwriteFileViewUrl(String fileId) =>
    '$appwriteEndpoint/storage/buckets/$appwriteMediaBucketId/files/$fileId/view?project=$appwriteProjectId';

/// Komprimiert [bytes] auf 400×400 JPEG (q80) und lädt sie in den Media-Bucket.
/// Rückgabe: öffentliche View-URL. Gemeinsame Basis für Profil- und Gruppenbilder
/// (ACL: `read any`, `delete` nur durch [ownerUid]).
Future<String> uploadMediaImage(
  Storage storage, {
  required Uint8List bytes,
  required String ownerUid,
  String filename = 'image.jpg',
}) async {
  final compressed = await FlutterImageCompress.compressWithList(
    bytes,
    minWidth: 400,
    minHeight: 400,
    quality: 80,
    format: CompressFormat.jpeg,
  );
  final file = await storage.createFile(
    bucketId: appwriteMediaBucketId,
    fileId: ID.unique(),
    file: InputFile.fromBytes(
        bytes: compressed, filename: filename, contentType: 'image/jpeg'),
    permissions: [
      Permission.read(Role.any()),
      Permission.delete(Role.user(ownerUid)),
    ],
  );
  return appwriteFileViewUrl(file.$id);
}

final _appwriteStorageHost = Uri.parse(appwriteEndpoint).host;

/// Einzige Quelle der Wahrheit für „darf ein Bild von diesem Host geladen werden":
/// nur der Appwrite-Storage (Host aus [appwriteEndpoint] abgeleitet). Alte
/// Firebase-Storage-URLs gelten nicht mehr als vertrauenswürdig — sie liefern
/// ohnehin 402; Avatare fallen dann auf Initialen/Icon zurück.
bool isTrustedStorageHost(String url) {
  final host = Uri.tryParse(url)?.host ?? '';
  return host == _appwriteStorageHost;
}

final appwriteClientProvider = Provider<Client>((ref) {
  return Client()
      .setEndpoint(appwriteEndpoint)
      .setProject(appwriteProjectId);
});

final appwriteStorageProvider = Provider<Storage>((ref) {
  return Storage(ref.watch(appwriteClientProvider));
});

/// Ref-counted Realtime channel multiplexer and owner of the Realtime instance.
/// Multiple concurrent listeners to the same channel share one WebSocket slot;
/// the Realtime subscription is opened on the first listen and cancelled
/// automatically when the last listener unsubscribes.
///
/// The broadcaster itself stays stable for the whole login session (only
/// replaced on logout). To refresh the connection — app resume, back online,
/// login — call [reconnect]: it swaps in a fresh Realtime instance and moves
/// every active channel over, so no service/provider has to be rebuilt.
class RealtimeBroadcaster {
  RealtimeBroadcaster(this._createRealtime) : _realtime = _createRealtime();

  final Realtime Function() _createRealtime;
  Realtime _realtime;
  final Map<String, Stream<RealtimeMessage>> _cache = {};
  // Active channels → re-subscribe on the current instance (see reconnect()).
  final Map<String, void Function()> _reattach = {};

  /// Opens a new WebSocket (with the current session cookies), re-subscribes
  /// all active channels on it and closes the old one. Each channel then gets
  /// an empty event so listeners reload data they may have missed while the
  /// old socket was dead (SDK heartbeat sends pings but never checks pongs, so
  /// a half-open socket after a long background phase goes unnoticed).
  void reconnect() {
    final old = _realtime;
    _realtime = _createRealtime();
    for (final reattach in List.of(_reattach.values)) {
      reattach();
    }
    old.disconnect();
  }

  Future<void> dispose() async {
    _reattach.clear();
    await _realtime.disconnect();
  }

  Stream<RealtimeMessage> stream(String channel) {
    return _cache.putIfAbsent(channel, () {
      // LinkedHashSet.identity(): O(1) add/remove by object identity.
      final sinks =
          LinkedHashSet<MultiStreamController<RealtimeMessage>>.identity();
      RealtimeSubscription? rtSub;
      StreamSubscription<RealtimeMessage>? sub;

      // Cancelling only the Dart listener leaves the subscription registered
      // in the SDK, which re-sends it on every reconnect. Cancel the listener
      // first (so unsubscribe()'s controller.close() doesn't hit onDone), then
      // unsubscribe.
      // Not close(): it sets the SDK's _reconnect=false, which would swallow
      // the next auto-reconnect if this instance is subscribed again later.
      void evict() {
        sub = null;
        rtSub = null;
        _cache.remove(channel);
        _reattach.remove(channel);
      }

      void teardown() {
        sub?.cancel();
        rtSub?.unsubscribe();
        evict();
      }

      // Guard against reentrant cancellation during fan-out: if a listener
      // cancels synchronously inside its onData, defer the remove until after
      // the current dispatch loop finishes to avoid concurrent modification.
      bool dispatching = false;
      final deferred = <MultiStreamController<RealtimeMessage>>[];

      void fanOut(void Function(MultiStreamController<RealtimeMessage>) fn) {
        dispatching = true;
        for (final s in sinks) {
          if (!s.isClosed) fn(s);
        }
        dispatching = false;
        for (final s in deferred) { sinks.remove(s); }
        deferred.clear();
        if (sinks.isEmpty) teardown();
      }

      void attach() {
        rtSub = _realtime.subscribe([channel]);
        sub = rtSub!.stream.listen(
          (event) => fanOut((s) => s.add(event)),
          onDone: () {
            // Evict first so any onCancel triggered by s.close() finds
            // sub == null and _cache already evicted (both no-ops).
            evict();
            for (final s in List.of(sinks)) {
              if (!s.isClosed) s.close();
            }
            sinks.clear();
          },
          onError: (Object e, StackTrace st) =>
              fanOut((s) => s.addError(e, st)),
        );
      }

      return Stream<RealtimeMessage>.multi(
        (controller) {
          if (sinks.isEmpty) {
            attach();
            _reattach[channel] = () {
              // Old instance is disconnected by reconnect(); only drop our
              // listener so its controller.close() doesn't reach onDone.
              sub?.cancel();
              attach();
              final resync = RealtimeMessage(
                events: const [],
                payload: const {},
                channels: [channel],
                timestamp: DateTime.now().toUtc().toIso8601String(),
              );
              fanOut((s) => s.add(resync));
            };
          }
          sinks.add(controller);
          controller.onCancel = () {
            if (dispatching) {
              deferred.add(controller);
            } else {
              sinks.remove(controller);
              if (sinks.isEmpty) teardown();
            }
          };
        },
        isBroadcast: true,
      );
    });
  }
}

final appwriteRealtimeBroadcasterProvider = Provider<RealtimeBroadcaster>((ref) {
  final client = ref.watch(appwriteClientProvider);
  final broadcaster = RealtimeBroadcaster(() => createPatchedRealtime(client));
  // Logout invalidates this provider → close the old user's WebSocket.
  ref.onDispose(broadcaster.dispose);
  return broadcaster;
});

