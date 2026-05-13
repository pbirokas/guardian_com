import 'dart:async';
import 'dart:convert';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as aw;
import '../models/app_user.dart';
import '../models/notification_settings.dart';
import 'notification_service.dart';

class AuthService {
  AuthService(Client client)
      : _account = Account(client),
        _db = Databases(client),
        _functions = Functions(client),
        _realtime = Realtime(client);

  final Account _account;
  final Databases _db;
  final Functions _functions;
  final Realtime _realtime;

  static const _dbId = 'guardian';
  static const _colUsers = 'users';

  Future<AppUser?> getCurrentAppUser() async {
    try {
      final account = await _account.get();
      return _getOrCreateUserDoc(account);
    } on AppwriteException {
      return null;
    }
  }

  Future<AppUser> signIn(String email, String password) async {
    await _account.createEmailPasswordSession(email: email, password: password);
    final account = await _account.get();
    return _afterAuth(account);
  }

  Future<AppUser> register(String email, String password, String name) async {
    final account = await _account.create(
      userId: ID.unique(),
      email: email,
      password: password,
      name: name,
    );
    await _account.createEmailPasswordSession(email: email, password: password);
    return _afterAuth(account);
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

  Future<void> signOut() async {
    try {
      await _account.deleteSessions();
    } catch (_) {}
  }

  Future<AppUser> _afterAuth(aw.User account) async {
    final user = await _getOrCreateUserDoc(account);
    unawaited(_callProcessMyInvitations());
    await NotificationService().initialize(_db, account.$id);
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
    RealtimeSubscription? sub;

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
      sub?.close();
      ctrl.close();
    }

    ctrl = StreamController(onCancel: dispose);
    sub = _realtime.subscribe(
        ['databases.$_dbId.collections.$_colUsers.documents.$uid']);
    sub.stream.listen((_) => reload(), onDone: dispose, onError: (_) {});
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
