import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:appwrite/appwrite.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:appwrite/models.dart' as aw;
import '../appwrite_client.dart';
import '../models/app_user.dart';
import '../models/notification_settings.dart';
import 'notification_service.dart';

// Bewusst ohne RealtimeBroadcaster-Feld: authStateProvider hängt an diesem
// Service. Hinge er am Broadcaster-Provider, würde jedes Ersetzen des
// Broadcasters den Login-Status neu aufbauen → Router springt über /splash
// zurück auf /organizations. Wer Realtime braucht, bekommt ihn als Parameter.
class AuthService {
  AuthService(Client client)
      : _client = client,
        _account = Account(client),
        _db = Databases(client),
        _functions = Functions(client),
        _storage = Storage(client);

  final Client _client;
  final Account _account;
  final Databases _db;
  final Functions _functions;
  final Storage _storage;

  static const _dbId = 'guardian';
  static const _colUsers = 'users';
  static const _selfServiceId = 'self-service';

  Future<AppUser?> getCurrentAppUser() async {
    // Ohne Netz sofort scheitern, statt ~60s auf den SDK-Timeout zu warten.
    final conn = await Connectivity().checkConnectivity();
    if (conn.every((r) => r == ConnectivityResult.none)) {
      throw Exception('Keine Netzwerkverbindung');
    }
    try {
      // Backstop, falls ein Netzwerk-Interface existiert, der Server aber nicht
      // antwortet (z. B. Server offline / VM ohne Internet).
      final account =
          await _account.get().timeout(const Duration(seconds: 12));
      await cacheRealtimeSessionCookie(_client);
      return _getOrCreateUserDoc(account);
    } on AppwriteException catch (e) {
      // Nur ein echter Auth-Fehler (401) bedeutet "nicht angemeldet".
      if (e.code == 401) return null;
      // Netzwerk-/Serverfehler (z. B. code 0 offline, 5xx) NICHT als Logout
      // werten — Fehler weiterreichen, damit die Session erhalten bleibt und
      // der Router den Verbindungs-Screen zeigt statt den Login.
      rethrow;
    }
    // TimeoutException / Exception('Keine Netzwerkverbindung') propagieren
    // ungefangen → authState.hasError → Verbindungs-Screen.
  }

  /// Lädt ein Profilbild in den Appwrite-Media-Bucket hoch und gibt dessen
  /// öffentliche View-URL zurück. Das Bild wird auf 400×400 JPEG komprimiert
  /// (analog zu Gruppenbildern, siehe [uploadMediaImage]).
  Future<String> uploadProfileImage(String uid, Uint8List bytes) =>
      uploadMediaImage(_storage, bytes: bytes, ownerUid: uid,
          filename: 'profile.jpg');

  Future<AppUser> updateProfile(String uid, String displayName,
      {String? photoUrl}) async {
    await _account.updateName(name: displayName);
    // users- und Member-Docs sind nicht mehr client-schreibbar (Selbst-
    // Eskalation über role/isChild) → `self-service` schreibt die Whitelist-
    // Felder in users/{uid} und alle eigenen Member-Docs.
    await _functions.callJson(_selfServiceId, {
      'action': 'updateProfile',
      'displayName': displayName,
      'photoUrl': ?photoUrl,
    });
    final doc = await _db.getDocument(
        databaseId: _dbId, collectionId: _colUsers, documentId: uid);
    return AppUser.fromAppwrite({r'$id': doc.$id, ...doc.data});
  }

  Future<String> sendEmailOtp(String email) async {
    await _resetSession();
    final token = await _account.createEmailToken(
      userId: ID.unique(),
      email: email.toLowerCase().trim(),
    );
    return token.userId;
  }

  Future<AppUser> confirmMagicLink(String userId, String secret) async {
    try {
      await _account.createSession(userId: userId, secret: secret);
    } on AppwriteException catch (e) {
      // Eine bereits vorhandene Session ist akzeptabel
      if (e.type != 'user_session_already_exists') rethrow;
    }
    return _finalizeSession();
  }

  Future<void> signOut() async {
    clearRealtimeSessionCookie();
    await _resetSession();
  }

  static const _deleteAccountId = 'delete-account';

  /// Serverseitige Sperr-Prüfung der Kontolöschung (Kind mit Eltern, Eltern
  /// mit Kindern, Admin einer Org mit weiteren Mitgliedern). Leer = frei.
  Future<List<AccountDeletionBlocker>> checkAccountDeletion() async {
    final r = await _functions.callJson(_deleteAccountId, {'action': 'check'});
    return [
      for (final b in (r['blockers'] as List? ?? const []))
        AccountDeletionBlocker.fromMap(Map<String, dynamic>.from(b as Map)),
    ];
  }

  /// Startet die Löschung. Die Function prüft die Sperren erneut und löscht
  /// dann asynchron weiter (kann Minuten dauern) — Fortschritt über
  /// [isAccountGone] bzw. `deletionStatus` im eigenen users-Doc.
  /// Wirft [FunctionCallException] (`blocked`), wenn inzwischen gesperrt.
  Future<void> startAccountDeletion() =>
      _functions.callJson(_deleteAccountId, {'action': 'start'});

  /// true, sobald das Auth-Konto gelöscht ist (Session ungültig → 401).
  Future<bool> isAccountGone() async {
    try {
      await _account.get();
      return false;
    } on AppwriteException catch (e) {
      return e.code == 401 || e.code == 404;
    }
  }

  /// Löscht alle Sessions server-seitig und leert den lokalen CookieJar.
  Future<void> _resetSession() async {
    try { await _account.deleteSessions(); } catch (_) {}
    await _clearCookieJar();
  }

  /// Cached den Realtime-Cookie, liest den aktuellen Account und schließt den Auth-Flow ab.
  Future<AppUser> _finalizeSession() async {
    await cacheRealtimeSessionCookie(_client);
    final account = await _account.get();
    return _afterAuth(account);
  }

  /// Löscht alle lokal gespeicherten Session-Cookies aus dem CookieJar.
  /// Nötig weil deleteSessions() nur den Server-Stand bereinigt, aber den
  /// lokalen CookieJar nicht leert — veraltete Cookies würden sonst mit
  /// dem nächsten Request mitgesendet und Appwrite zum 400/401 verleiten.
  /// Nutzt dynamischen Cast auf das interne `cookieJar`-Feld von ClientIO
  /// (geprüft mit Appwrite SDK 26.1.0). Bei SDK-Upgrades prüfen ob das Feld noch existiert.
  Future<void> _clearCookieJar() async {
    // Im Web verwaltet der Browser die Cookies; ClientBrowser hat keinen Jar.
    if (kIsWeb) return;
    try {
      final dynamic jar = (_client as dynamic).cookieJar;
      await jar.deleteAll();
    } catch (_) {}
  }

  Future<AppUser> _afterAuth(aw.User account) async {
    final user = await _getOrCreateUserDoc(account);
    unawaited(_callProcessMyInvitations());
    unawaited(NotificationService().initialize(_db, account.$id));
    return user;
  }

  Future<AppUser> _getOrCreateUserDoc(aw.User account) async {
    try {
      final doc = await _db.getDocument(
        databaseId: _dbId,
        collectionId: _colUsers,
        documentId: account.$id,
      );
      return AppUser.fromAppwrite({r'$id': doc.$id, ...doc.data});
    } on AppwriteException catch (e) {
      if (e.code != 404) rethrow;
      // Neues Konto: users-Doc legt `self-service` an (Felder wie isChild/
      // verifiedParentUids setzt nur der Server; ACL nur read user(self)).
      final result =
          await _functions.callJson(_selfServiceId, {'action': 'ensureUserDoc'});
      final user = Map<String, dynamic>.from(result['user'] as Map);
      return AppUser.fromAppwrite(user);
    }
  }

  /// Eigenes users-Doc live (Realtime-Payload direkt übernommen; leeres
  /// Resync-Event lädt neu). Damit sieht die App serverseitige Änderungen
  /// wie `isChild` nach einer bestätigten Eltern-Anfrage sofort — ohne
  /// `authStateProvider` neu aufzubauen (würde den Router zurücksetzen).
  Stream<AppUser?> watchOwnUser(String uid, RealtimeBroadcaster broadcaster) {
    late StreamController<AppUser?> ctrl;
    StreamSubscription? realtimeSub;

    Future<void> reload() async {
      if (ctrl.isClosed) return;
      try {
        final doc = await _db.getDocument(
            databaseId: _dbId, collectionId: _colUsers, documentId: uid);
        if (!ctrl.isClosed) {
          ctrl.add(AppUser.fromAppwrite({r'$id': doc.$id, ...doc.data}));
        }
      } catch (e) {
        if (!ctrl.isClosed) ctrl.addError(e);
      }
    }

    void dispose() {
      realtimeSub?.cancel();
      ctrl.close();
    }

    ctrl = StreamController(onCancel: dispose);
    realtimeSub = broadcaster
        .stream('databases.$_dbId.collections.$_colUsers.documents.$uid')
        .listen((msg) {
      if (msg.events.isEmpty || msg.payload[r'$id'] != uid) {
        reload();
      } else if (!ctrl.isClosed) {
        ctrl.add(AppUser.fromAppwrite(Map<String, dynamic>.from(msg.payload)));
      }
    }, onDone: dispose, onError: (_) {});
    reload();
    return ctrl.stream;
  }

  Stream<NotificationSettings> watchNotificationSettings(
      String uid, RealtimeBroadcaster broadcaster) {
    late StreamController<NotificationSettings> ctrl;
    StreamSubscription? realtimeSub;

    Future<void> reload() async {
      if (ctrl.isClosed) return;
      try {
        final doc = await _db.getDocument(
          databaseId: _dbId,
          collectionId: _colUsers,
          documentId: uid,
        );
        final raw = doc.data['notificationSettingsJson'] as String?;
        final map = raw != null ? jsonDecode(raw) as Map<String, dynamic>? : null;
        if (!ctrl.isClosed) ctrl.add(NotificationSettings.fromMap(map));
      } catch (_) {
        if (!ctrl.isClosed) ctrl.add(const NotificationSettings());
      }
    }

    void dispose() {
      realtimeSub?.cancel();
      ctrl.close();
    }

    ctrl = StreamController(onCancel: dispose);
    realtimeSub = broadcaster
        .stream('databases.$_dbId.collections.$_colUsers.documents.$uid')
        .listen((_) => reload(), onDone: dispose, onError: (_) {});
    reload();
    return ctrl.stream;
  }

  Future<void> saveNotificationSettings(
      String uid, NotificationSettings settings) async {
    await _functions.callJson(_selfServiceId, {
      'action': 'setNotificationSettings',
      'settings': settings.toMap(),
    });
  }

  Future<void> _callProcessMyInvitations() async {
    try {
      await _functions.executeRaw(
        functionId: 'process-my-invitations',
        xasync: true,
      );
    } catch (_) {}
  }
}

/// Grund, warum ein Konto (noch) nicht gelöscht werden kann
/// (`delete-account/check`).
class AccountDeletionBlocker {
  const AccountDeletionBlocker({required this.code, this.orgId, this.orgName});

  /// `childHasParents` | `parentHasChildren` | `orgAdmin`
  final String code;
  final String? orgId;
  final String? orgName;

  factory AccountDeletionBlocker.fromMap(Map<String, dynamic> m) =>
      AccountDeletionBlocker(
        code: m['code'] as String? ?? '',
        orgId: m['orgId'] as String?,
        orgName: m['orgName'] as String?,
      );
}
