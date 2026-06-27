import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/enums.dart';
import 'package:appwrite/models.dart' as aw;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../appwrite_client.dart';
import '../models/app_user.dart';
import '../models/notification_settings.dart';
import 'notification_service.dart';

class AuthService {
  AuthService(Client client, RealtimeBroadcaster broadcaster)
      : _client = client,
        _account = Account(client),
        _db = Databases(client),
        _functions = Functions(client),
        _storage = Storage(client),
        _broadcaster = broadcaster;

  final Client _client;
  final Account _account;
  final Databases _db;
  final Functions _functions;
  final Storage _storage;
  final RealtimeBroadcaster _broadcaster;

  static const _dbId = 'guardian';
  static const _colUsers = 'users';

  Future<AppUser?> getCurrentAppUser() async {
    try {
      final account = await _account.get();
      await cacheRealtimeSessionCookie(_client);
      return _getOrCreateUserDoc(account);
    } on AppwriteException {
      return null;
    }
  }

  /// Lädt ein Profilbild in den Appwrite-Media-Bucket hoch und gibt dessen
  /// öffentliche View-URL zurück. Das Bild wird auf 400×400 JPEG komprimiert
  /// (analog zu Gruppenbildern).
  Future<String> uploadProfileImage(String uid, Uint8List bytes) async {
    final compressed = await FlutterImageCompress.compressWithList(
      bytes,
      minWidth: 400,
      minHeight: 400,
      quality: 80,
      format: CompressFormat.jpeg,
    );
    final file = await _storage.createFile(
      bucketId: appwriteMediaBucketId,
      fileId: ID.unique(),
      file: InputFile.fromBytes(
          bytes: compressed,
          filename: 'profile.jpg',
          contentType: 'image/jpeg'),
      permissions: [
        Permission.read(Role.any()),
        Permission.delete(Role.user(uid)),
      ],
    );
    return appwriteFileViewUrl(file.$id);
  }

  Future<AppUser> updateProfile(String uid, String displayName,
      {String? photoUrl}) async {
    await _account.updateName(name: displayName);
    final updates = <String, dynamic>{'displayName': displayName};
    if (photoUrl != null) updates['photoUrl'] = photoUrl;
    final doc = await _db.updateDocument(
      databaseId: _dbId,
      collectionId: _colUsers,
      documentId: uid,
      data: updates,
    );
    return AppUser.fromAppwrite({r'$id': doc.$id, ...doc.data});
  }

  Future<AppUser> signInWithGoogle() async {
    await _resetSession();
    await _account.createOAuth2Session(provider: OAuthProvider.google);
    // Führe server-seitigen Account-Merge durch (falls ein migrierter Firebase-Account
    // mit dieser E-Mail existiert, werden alle Daten auf den Google-Account übertragen).
    try {
      await _functions.createExecution(
        functionId: 'merge-oauth-account',
        xasync: false,
      );
      // Kurze Pause damit Appwrite DB-Änderungen aus dem Merge propagieren können
      await Future.delayed(const Duration(seconds: 2));
    } catch (e) {
      if (kDebugMode) debugPrint('[AuthService] merge-oauth-account failed: $e');
    }
    return _finalizeSession();
  }

  /// Links a Google identity to the currently authenticated account.
  /// Call this only when the user already has an active session.
  Future<void> linkGoogleAccount() async {
    await _account.createOAuth2Token(provider: OAuthProvider.google);
  }

  Future<bool> isGoogleLinked() async {
    try {
      final identities = await _account.listIdentities();
      return identities.identities.any((id) => id.provider == 'google');
    } catch (_) {
      return false;
    }
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
      // Eine vorhandene Session (z.B. nach fehlgeschlagenem OAuth) ist akzeptabel
      if (e.type != 'user_session_already_exists') rethrow;
    }
    return _finalizeSession();
  }

  Future<void> signOut() async {
    clearRealtimeSessionCookie();
    await _resetSession();
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
  /// (Appwrite SDK 23.0.0). Bei SDK-Upgrades prüfen ob das Feld noch existiert.
  Future<void> _clearCookieJar() async {
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
      final newUser = AppUser(
        uid: account.$id,
        email: account.email.toLowerCase(),
        displayName: account.name.isNotEmpty ? account.name : account.email,
        memberships: const [],
        createdAt: DateTime.now(),
      );
      final doc = await _db.createDocument(
        databaseId: _dbId,
        collectionId: _colUsers,
        documentId: account.$id,
        data: newUser.toAppwrite(),
        permissions: [
          Permission.read(Role.user(account.$id)),
          Permission.update(Role.user(account.$id)),
          Permission.delete(Role.user(account.$id)),
        ],
      );
      return AppUser.fromAppwrite({r'$id': doc.$id, ...doc.data});
    }
  }

  Stream<NotificationSettings> watchNotificationSettings(String uid) {
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
    realtimeSub = _broadcaster
        .stream('databases.$_dbId.collections.$_colUsers.documents.$uid')
        .listen((_) => reload(), onDone: dispose, onError: (_) {});
    reload();
    return ctrl.stream;
  }

  Future<void> saveNotificationSettings(
      String uid, NotificationSettings settings) async {
    await _db.updateDocument(
      databaseId: _dbId,
      collectionId: _colUsers,
      documentId: uid,
      data: {'notificationSettingsJson': jsonEncode(settings.toMap())},
    );
  }

  Future<void> _callProcessMyInvitations() async {
    try {
      await _functions.createExecution(
        functionId: 'process-my-invitations',
        xasync: true,
      );
    } catch (_) {}
  }
}
