import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/enums.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../appwrite_client.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/poll.dart';
import '../models/scheduled_message.dart';

class ChatService {
  ChatService({
    required Client client,
    required RealtimeBroadcaster broadcaster,
    required String uid,
    required String displayName,
  })  : _db = Databases(client),
        _storage = Storage(client),
        _functions = Functions(client),
        _broadcaster = broadcaster,
        _uid = uid,
        _displayName = displayName;

  final Databases _db;
  final Storage _storage;
  final Functions _functions;
  final RealtimeBroadcaster _broadcaster;
  final String _uid;
  final String _displayName;

  static const _dbId = 'guardian';
  static const _colConvs = 'conversations';
  static const _colMessages = 'chat_messages';
  static const _colPolls = 'polls';
  static const _colScheduled = 'scheduled_messages';
  static const _colMembers = 'members';
  static const _colOrgs = 'organizations';
  static const _colReports = 'reports';
  static const _colReceipts = 'read_receipts';

  static bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);


  /// Lese-/Schreibrechte einer Nachricht im Team-Modell (siehe
  /// `sync-conversation-permissions` / `sync-supervisor-team`):
  /// - Lesen: Conversation-Team (Teilnehmer + Guardians) + Org-Supervisor-Team
  ///   (Admin/Moderatoren, org-weite Aufsicht).
  /// - Der Autor darf zusätzlich direkt lesen — so sieht er seine eigene
  ///   Nachricht sofort, auch bevor die Server-Function die Team-Mitgliedschaft
  ///   eines frisch erstellten Chats gesetzt hat.
  /// - Ändern/Löschen: Autor (Bearbeiten) + Supervisor-Team (Moderation).
  List<String> _msgPerms(String convId) {
    final conv = Role.team(convId);
    final me = Role.user(_uid);
    return [
      // Lesen: das Conversation-Team (Teilnehmer + Guardians + Aufsicht) — vom
      // Server (sync-conversation-permissions) gepflegt.
      Permission.read(conv),
      // Der Autor darf zusätzlich direkt lesen (sieht die eigene Nachricht
      // sofort, auch bevor die Function ihn dem Team hinzugefügt hat) sowie
      // seine eigene Nachricht bearbeiten/löschen. Fremd-Moderation läuft über
      // die Function `moderate-message`.
      Permission.read(me),
      Permission.update(me),
      Permission.delete(me),
    ];
  }

  /// Rechte für ein Poll-Dokument: das Conversation-Team liest; Teilnehmer
  /// stimmen ab und Mods schließen (beides = Update auf dem Poll-Doc), daher
  /// Update fürs ganze Team. Löschen bleibt beim Ersteller.
  List<String> _pollPerms(String convId) {
    final conv = Role.team(convId);
    return [
      Permission.read(conv),
      Permission.update(conv),
      Permission.delete(Role.user(_uid)),
    ];
  }

  static int _byLastMessageDesc(Conversation a, Conversation b) {
    if (a.lastMessageAt == null) return 1;
    if (b.lastMessageAt == null) return -1;
    return b.lastMessageAt!.compareTo(a.lastMessageAt!);
  }

  // ── Realtime helpers ───────────────────────────────────────────────────────

  Stream<List<T>> _watchQuery<T>(
    String collectionId,
    T Function(Map<String, dynamic>) fromDoc,
    List<String> queries,
    int Function(T, T)? sort, {
    int limit = 500,
  }) {
    late StreamController<List<T>> ctrl;
    StreamSubscription? realtimeSub;

    Future<void> reload() async {
      if (ctrl.isClosed) return;
      try {
        final result = await _db.listDocuments(
          databaseId: _dbId,
          collectionId: collectionId,
          queries: [...queries, Query.limit(limit)],
        );
        var items = result.documents
            .map((d) => fromDoc({r'$id': d.$id, ...d.data}))
            .toList();
        if (sort != null) items.sort(sort);
        if (!ctrl.isClosed) ctrl.add(items);
      } catch (e) {
        if (!ctrl.isClosed) ctrl.addError(e);
      }
    }

    void dispose() {
      realtimeSub?.cancel();
      ctrl.close();
    }

    ctrl = StreamController(onCancel: dispose);
    realtimeSub = _broadcaster
        .stream('databases.$_dbId.collections.$collectionId.documents')
        .listen((_) => reload(), onDone: dispose, onError: (_) {});
    reload();
    return ctrl.stream;
  }

  Stream<T?> _watchDocument<T>(
    String collectionId,
    String docId,
    T Function(Map<String, dynamic>) fromDoc,
  ) {
    late StreamController<T?> ctrl;
    StreamSubscription? realtimeSub;

    Future<void> reload() async {
      if (ctrl.isClosed) return;
      try {
        final doc = await _db.getDocument(
            databaseId: _dbId,
            collectionId: collectionId,
            documentId: docId);
        if (!ctrl.isClosed) {
          ctrl.add(fromDoc({r'$id': doc.$id, ...doc.data}));
        }
      } on AppwriteException catch (e) {
        if (e.code == 404) {
          if (!ctrl.isClosed) ctrl.add(null);
        } else {
          if (!ctrl.isClosed) ctrl.addError(e);
        }
      }
    }

    void dispose() {
      realtimeSub?.cancel();
      ctrl.close();
    }

    ctrl = StreamController(onCancel: dispose);
    realtimeSub = _broadcaster
        .stream('databases.$_dbId.collections.$collectionId.documents.$docId')
        .listen((_) => reload(), onDone: dispose, onError: (_) {});
    reload();
    return ctrl.stream;
  }

  // ── Konversations-Abfragen ─────────────────────────────────────────────────

  Stream<List<Conversation>> watchOrgConversations(String orgId) {
    return _watchQuery(
      _colConvs,
      Conversation.fromAppwrite,
      [Query.contains('participantUids', [_uid]), Query.equal('orgId', orgId)],
      _byLastMessageDesc,
    );
  }

  Stream<List<Conversation>> watchAllMyApprovedConversations() {
    return _watchQuery(
      _colConvs,
      Conversation.fromAppwrite,
      [
        Query.contains('participantUids', [_uid]),
        Query.equal('status', 'approved'),
      ],
      _byLastMessageDesc,
    );
  }

  Stream<List<Conversation>> watchAdminConversations(String orgId) {
    return _watchQuery(
      _colConvs,
      Conversation.fromAppwrite,
      [Query.equal('orgId', orgId)],
      _byLastMessageDesc,
    );
  }

  Stream<List<Conversation>> watchPendingRequests(String orgId) {
    return _watchQuery(
      _colConvs,
      Conversation.fromAppwrite,
      [Query.equal('orgId', orgId), Query.equal('status', 'pending')],
      null,
    );
  }

  Stream<List<Conversation>> watchModeratorPendingRequests(String orgId) {
    return _watchQuery(
      _colConvs,
      Conversation.fromAppwrite,
      [
        Query.contains('canApproveUids', [_uid]),
        Query.equal('orgId', orgId),
        Query.equal('status', 'pending'),
      ],
      null,
    );
  }

  Stream<List<Conversation>> watchGuardianPendingRequests(String orgId) {
    return _watchQuery(
      _colConvs,
      Conversation.fromAppwrite,
      [
        Query.contains('guardianUids', [_uid]),
        Query.equal('orgId', orgId),
        Query.equal('status', 'pending'),
      ],
      null,
    ).map((list) => list.where((c) => c.orgAdminUid != _uid).toList());
  }

  Stream<List<Conversation>> watchSupervisorConversations(String orgId) {
    return _watchQuery(
      _colConvs,
      Conversation.fromAppwrite,
      [
        Query.contains('canApproveUids', [_uid]),
        Query.equal('orgId', orgId),
        Query.equal('status', 'approved'),
      ],
      _byLastMessageDesc,
    ).map((list) =>
        list.where((c) => !c.participantUids.contains(_uid)).toList());
  }

  Stream<List<Conversation>> watchGuardianSupervisorConversations(
      String orgId) {
    return _watchQuery(
      _colConvs,
      Conversation.fromAppwrite,
      [
        Query.contains('guardianUids', [_uid]),
        Query.equal('orgId', orgId),
        Query.equal('status', 'approved'),
      ],
      _byLastMessageDesc,
    );
  }

  Stream<List<Conversation>> watchShelteredModeratorConversations(
      String orgId, String adminUid) {
    return _watchQuery(
      _colConvs,
      Conversation.fromAppwrite,
      [
        Query.equal('orgId', orgId),
        Query.equal('orgAdminUid', adminUid),
        Query.equal('status', 'approved'),
      ],
      _byLastMessageDesc,
    ).map((list) =>
        list.where((c) => !c.participantUids.contains(_uid)).toList());
  }

  Stream<Conversation?> watchConversation(String convId) {
    return _watchDocument(_colConvs, convId, Conversation.fromAppwrite);
  }

  // ── Read Receipts ──────────────────────────────────────────────────────────

  /// Gibt einen Stream zurück der immer die aktuellen Lesezeitstempel
  /// des angemeldeten Nutzers für alle seine Konversationen enthält.
  /// Map<convId, readAt> — wird bei jedem Realtime-Ereignis auf read_receipts neu geladen.
  Stream<Map<String, DateTime>> watchMyReadReceipts() {
    late StreamController<Map<String, DateTime>> ctrl;
    StreamSubscription? realtimeSub;

    Future<void> reload() async {
      if (ctrl.isClosed) return;
      try {
        final result = await _db.listDocuments(
          databaseId: _dbId,
          collectionId: _colReceipts,
          queries: [Query.equal('uid', _uid), Query.limit(500)],
        );
        final map = <String, DateTime>{};
        for (final doc in result.documents) {
          final convId = doc.data['convId'] as String?;
          final readAtRaw = doc.data['readAt'] as String?;
          if (convId != null && readAtRaw != null) {
            map[convId] = DateTime.parse(readAtRaw).toLocal();
          }
        }
        if (!ctrl.isClosed) ctrl.add(map);
      } catch (e) {
        if (!ctrl.isClosed) ctrl.addError(e);
      }
    }

    void dispose() {
      realtimeSub?.cancel();
      ctrl.close();
    }

    ctrl = StreamController(onCancel: dispose);
    realtimeSub = _broadcaster
        .stream('databases.$_dbId.collections.$_colReceipts.documents')
        .listen((_) => reload(), onDone: dispose, onError: (_) {});
    reload();
    return ctrl.stream;
  }

  // ── Konversations-Aktionen ─────────────────────────────────────────────────

  Future<Conversation> requestConversation(
      String orgId, String targetUid) async {
    final existing = await _db.listDocuments(
      databaseId: _dbId,
      collectionId: _colConvs,
      queries: [
        Query.contains('participantUids', [_uid]),
        Query.equal('orgId', orgId),
        Query.limit(100),
      ],
    );
    for (final doc in existing.documents) {
      final conv = Conversation.fromAppwrite({r'$id': doc.$id, ...doc.data});
      if (!conv.isGroup &&
          conv.participantUids.contains(targetUid) &&
          conv.status != ConversationStatus.rejected &&
          conv.status != ConversationStatus.archived) {
        throw Exception('Eine Konversation mit dieser Person existiert bereits.');
      }
    }

    final memberDoc = await _safeGetDocument(
        _colMembers, '${orgId}_$_uid');
    final guardianUid = memberDoc?.data['guardianUids'] is List &&
            (memberDoc!.data['guardianUids'] as List).isNotEmpty
        ? (memberDoc.data['guardianUids'] as List).first as String?
        : null;

    final orgDoc = await _db.getDocument(
        databaseId: _dbId, collectionId: _colOrgs, documentId: orgId);
    final orgAdminUid = orgDoc.data['adminUid'] as String;
    final supervisors = await _buildSupervisorUids(orgId, [_uid, targetUid]);

    final convId = ID.unique();
    final conv = Conversation(
      id: convId,
      orgId: orgId,
      orgAdminUid: orgAdminUid,
      participantUids: [_uid, targetUid],
      requestedBy: _uid,
      status: ConversationStatus.pending,
      createdAt: DateTime.now().toUtc(),
      requestorGuardianUid: guardianUid,
      canApproveUids: supervisors.canApproveUids,
      guardianUids: supervisors.guardianUids,
    );
    await _db.createDocument(
      databaseId: _dbId,
      collectionId: _colConvs,
      documentId: convId,
      data: conv.toAppwrite(),
      // Nur der Ersteller — sofort sichtbar. Die Server-Function
      // `sync-conversation-permissions` legt danach das Team-Modell (Teilnehmer +
      // Guardians + Org-Supervisor-Team) als ACL fest.
      permissions: [
        Permission.read(Role.user(_uid)),
        Permission.update(Role.user(_uid)),
      ],
    );
    return conv;
  }

  Future<Conversation> createApprovedConversation(
      String orgId, String targetUid) async {
    final existing = await _db.listDocuments(
      databaseId: _dbId,
      collectionId: _colConvs,
      queries: [
        Query.contains('participantUids', [_uid]),
        Query.equal('orgId', orgId),
        Query.limit(100),
      ],
    );
    for (final doc in existing.documents) {
      final conv = Conversation.fromAppwrite({r'$id': doc.$id, ...doc.data});
      if (conv.participantUids.contains(targetUid) && !conv.isGroup) {
        return conv;
      }
    }

    final orgDoc = await _db.getDocument(
        databaseId: _dbId, collectionId: _colOrgs, documentId: orgId);
    final orgAdminUid = orgDoc.data['adminUid'] as String;
    final supervisors =
        await _buildSupervisorUids(orgId, [_uid, targetUid]);

    final convId = ID.unique();
    final conv = Conversation(
      id: convId,
      orgId: orgId,
      orgAdminUid: orgAdminUid,
      participantUids: [_uid, targetUid],
      requestedBy: _uid,
      status: ConversationStatus.approved,
      createdAt: DateTime.now().toUtc(),
      approvedBy: _uid,
      approvedAt: DateTime.now().toUtc(),
      canApproveUids: supervisors.canApproveUids,
      guardianUids: supervisors.guardianUids,
    );
    await _db.createDocument(
      databaseId: _dbId,
      collectionId: _colConvs,
      documentId: convId,
      data: conv.toAppwrite(),
      // Nur der Ersteller — sofort sichtbar. Die Server-Function
      // `sync-conversation-permissions` legt danach das Team-Modell (Teilnehmer +
      // Guardians + Org-Supervisor-Team) als ACL fest.
      permissions: [
        Permission.read(Role.user(_uid)),
        Permission.update(Role.user(_uid)),
      ],
    );
    return conv;
  }

  Future<Conversation> createGroupChat(
      String orgId, String name, List<String> memberUids) async {
    final orgDoc = await _db.getDocument(
        databaseId: _dbId, collectionId: _colOrgs, documentId: orgId);
    final orgAdminUid = orgDoc.data['adminUid'] as String;
    final supervisors = await _buildSupervisorUids(orgId, memberUids);

    final convId = ID.unique();
    final conv = Conversation(
      id: convId,
      orgId: orgId,
      orgAdminUid: orgAdminUid,
      participantUids: memberUids,
      requestedBy: _uid,
      status: ConversationStatus.approved,
      createdAt: DateTime.now().toUtc(),
      approvedBy: _uid,
      approvedAt: DateTime.now().toUtc(),
      name: name,
      isGroup: true,
      canApproveUids: supervisors.canApproveUids,
      guardianUids: supervisors.guardianUids,
    );
    await _db.createDocument(
      databaseId: _dbId,
      collectionId: _colConvs,
      documentId: convId,
      data: conv.toAppwrite(),
      // Nur der Ersteller — sofort sichtbar. Die Server-Function
      // `sync-conversation-permissions` legt danach das Team-Modell (Teilnehmer +
      // Guardians + Org-Supervisor-Team) als ACL fest.
      permissions: [
        Permission.read(Role.user(_uid)),
        Permission.update(Role.user(_uid)),
      ],
    );
    return conv;
  }

  Future<void> approveConversation(String convId) async {
    await _db.updateDocument(
      databaseId: _dbId,
      collectionId: _colConvs,
      documentId: convId,
      data: {
        'status': ConversationStatus.approved.name,
        'approvedBy': _uid,
        'approvedAt': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }

  Future<void> rejectConversation(String convId) async {
    await _db.deleteDocument(
        databaseId: _dbId, collectionId: _colConvs, documentId: convId);
  }

  Future<void> archiveConversation(String convId) async {
    await _db.updateDocument(
      databaseId: _dbId,
      collectionId: _colConvs,
      documentId: convId,
      data: {'status': ConversationStatus.archived.name},
    );
  }

  Future<void> deleteConversation(String convId) async {
    // Nachrichten löschen (in Batches à 100)
    while (true) {
      final msgs = await _db.listDocuments(
        databaseId: _dbId,
        collectionId: _colMessages,
        queries: [Query.equal('convId', convId), Query.limit(100)],
      );
      if (msgs.documents.isEmpty) break;
      for (final doc in msgs.documents) {
        await _db.deleteDocument(
            databaseId: _dbId,
            collectionId: _colMessages,
            documentId: doc.$id);
      }
    }
    await _db.deleteDocument(
        databaseId: _dbId, collectionId: _colConvs, documentId: convId);
  }

  Future<void> renameConversation(String convId, String name) async {
    await _db.updateDocument(
        databaseId: _dbId,
        collectionId: _colConvs,
        documentId: convId,
        data: {'name': name.trim()});
  }

  Future<void> markAsRead(String convId, {DateTime? readAt}) async {
    await _functions.createExecution(
      functionId: 'mark-as-read',
      body: jsonEncode({
        'convId': convId,
        if (readAt != null) 'readAt': readAt.toUtc().toIso8601String(),
      }),
      method: ExecutionMethod.pOST,
    );
  }

  Future<void> setPersonalName(String convId, String name) async {
    final doc = await _db.getDocument(
        databaseId: _dbId, collectionId: _colConvs, documentId: convId);
    final conv = Conversation.fromAppwrite({r'$id': doc.$id, ...doc.data});
    final names = Map<String, String>.from(conv.personalNames);
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      names.remove(_uid);
    } else {
      names[_uid] = trimmed;
    }
    await _db.updateDocument(
        databaseId: _dbId,
        collectionId: _colConvs,
        documentId: convId,
        data: {'personalNamesJson': jsonEncode(names)});
  }

  Future<void> pinMessage(String convId, String msgId, String text) async {
    await _db.updateDocument(
        databaseId: _dbId,
        collectionId: _colConvs,
        documentId: convId,
        data: {
          'pinnedMessageId': msgId,
          'pinnedMessageText':
              text.length > 120 ? '${text.substring(0, 120)}…' : text,
        });
  }

  Future<void> unpinMessage(String convId) async {
    await _db.updateDocument(
        databaseId: _dbId,
        collectionId: _colConvs,
        documentId: convId,
        data: {'pinnedMessageId': null, 'pinnedMessageText': null});
  }

  Future<void> setTyping(String convId, bool isTyping) async {
    // Typing-Indikator ist in Appwrite realtime-only — nicht in DB persistiert
  }

  // ── Gruppen-Chat Mitglieder ────────────────────────────────────────────────

  Future<void> removeMemberFromConversation(
      String convId, String memberUid, {String memberName = ''}) async {
    final doc = await _db.getDocument(
        databaseId: _dbId, collectionId: _colConvs, documentId: convId);
    final conv = Conversation.fromAppwrite({r'$id': doc.$id, ...doc.data});
    final newUids = conv.participantUids.where((u) => u != memberUid).toList();
    await _db.updateDocument(
        databaseId: _dbId,
        collectionId: _colConvs,
        documentId: convId,
        data: {'participantUids': newUids});
    if (memberName.isNotEmpty) {
      await _postSystemMessage(convId, conv.orgId, 'memberRemoved', memberName);
    }
  }

  Future<void> addMembersToConversation(
      String convId, String orgId, List<String> newMemberUids) async {
    final doc = await _db.getDocument(
        databaseId: _dbId, collectionId: _colConvs, documentId: convId);
    final conv = Conversation.fromAppwrite({r'$id': doc.$id, ...doc.data});

    final newGuardianUids = <String>[];
    final addedNames = <String>[];
    for (final uid in newMemberUids) {
      final memberDoc =
          await _safeGetDocument(_colMembers, '${orgId}_$uid');
      if (memberDoc == null) continue;
      final guardians = List<String>.from(
          memberDoc.data['guardianUids'] as List? ?? []);
      newGuardianUids.addAll(guardians);
      final name = memberDoc.data['displayName'] as String? ?? '';
      if (name.isNotEmpty) addedNames.add(name);
    }

    final updatedUids = {...conv.participantUids, ...newMemberUids}.toList();
    final updatedGuardians =
        {...conv.guardianUids, ...newGuardianUids}.toList();
    await _db.updateDocument(
        databaseId: _dbId,
        collectionId: _colConvs,
        documentId: convId,
        data: {
          'participantUids': updatedUids,
          'guardianUids': updatedGuardians,
        });
    for (final name in addedNames) {
      await _postSystemMessage(convId, orgId, 'memberAdded', name);
    }
  }

  Future<String> uploadGroupImage(String convId, Uint8List bytes) async {
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
          filename: 'avatar.jpg',
          contentType: 'image/jpeg'),
      permissions: [
        Permission.read(Role.any()),
        Permission.delete(Role.user(_uid)),
      ],
    );
    return appwriteFileViewUrl(file.$id);
  }

  Future<void> updateGroupInfo(
    String convId, {
    String? name,
    String? imageUrl,
    bool removeImage = false,
  }) async {
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name.trim();
    if (imageUrl != null) updates['imageUrl'] = imageUrl;
    if (removeImage) updates['imageUrl'] = null;
    if (updates.isNotEmpty) {
      await _db.updateDocument(
          databaseId: _dbId,
          collectionId: _colConvs,
          documentId: convId,
          data: updates);
    }
  }

  // ── Nachrichten ────────────────────────────────────────────────────────────

  Future<String> _getOrgId(String convId) async {
    final doc = await _db.getDocument(
        databaseId: _dbId, collectionId: _colConvs, documentId: convId);
    return doc.data['orgId'] as String? ?? '';
  }

  Stream<List<Message>> watchMessages(String convId, {int limit = 100}) {
    return _watchQuery(
      _colMessages,
      Message.fromAppwrite,
      [
        Query.equal('convId', convId),
        Query.orderDesc('sentAt'),
      ],
      null,
      limit: limit,
    );
  }

  Future<void> sendMessage(
    String convId,
    String text, {
    String? replyToId,
    String? replyToSenderName,
    String? replyToText,
  }) async {
    final msgId = ID.unique();
    final orgId = await _getOrgId(convId);
    final msg = Message(
      id: msgId,
      senderUid: _uid,
      senderName: _displayName,
      text: text,
      sentAt: DateTime.now().toUtc(),
      replyToId: replyToId,
      replyToSenderName: replyToSenderName,
      replyToText: replyToText,
    );
    await _db.createDocument(
      databaseId: _dbId,
      collectionId: _colMessages,
      documentId: msgId,
      data: {...msg.toAppwrite(), 'convId': convId, 'orgId': orgId},
      permissions: _msgPerms(convId),
    );
    await _updateLastMessage(
        convId, text.length > 200 ? '${text.substring(0, 200)}…' : text);
  }

  /// Bearbeitet die EIGENE Nachricht (Autor). Fremd-Moderation läuft über
  /// [moderateMessage] (serverseitig).
  Future<void> editMessage(
      String convId, String messageId, String newText) async {
    await _db.updateDocument(
        databaseId: _dbId,
        collectionId: _colMessages,
        documentId: messageId,
        data: {
          'text': newText,
          'editedAt': DateTime.now().toUtc().toIso8601String(),
        });
  }

  /// Moderation einer FREMDEN Nachricht (nur Admin/Mod): Text ersetzen +
  /// archivieren. Läuft serverseitig über `moderate-message`, weil die
  /// Nachrichten-ACL nur dem Autor Schreibrechte gibt. Eigene Nachrichten
  /// bearbeitet der Autor direkt via [editMessage].
  Future<void> moderateMessage(
    String convId,
    String messageId,
    String newText, {
    required String archivedByName,
  }) async {
    await _functions.createExecution(
      functionId: 'moderate-message',
      body: jsonEncode({
        'convId': convId,
        'msgId': messageId,
        'newText': newText,
        'archivedByName': archivedByName,
      }),
      method: ExecutionMethod.pOST,
    );
  }

  Future<void> softDeleteMessage(String convId, String messageId) async {
    await _db.updateDocument(
        databaseId: _dbId,
        collectionId: _colMessages,
        documentId: messageId,
        data: {
          'deletedAt': DateTime.now().toUtc().toIso8601String(),
          'deletedBy': _uid,
        });
  }

  Future<void> undoDeleteMessage(String convId, String messageId) async {
    await _db.updateDocument(
        databaseId: _dbId,
        collectionId: _colMessages,
        documentId: messageId,
        data: {'deletedAt': null, 'deletedBy': null});
  }

  Future<void> setReaction(
      String convId, String msgId, String? emoji) async {
    final doc = await _db.getDocument(
        databaseId: _dbId, collectionId: _colMessages, documentId: msgId);
    final msg = Message.fromAppwrite({r'$id': doc.$id, ...doc.data});
    final reactions = Map<String, String>.from(msg.reactions);
    if (emoji == null) {
      reactions.remove(_uid);
    } else {
      reactions[_uid] = emoji;
    }
    await _db.updateDocument(
        databaseId: _dbId,
        collectionId: _colMessages,
        documentId: msgId,
        data: {'reactionsJson': jsonEncode(reactions)});
  }

  // ── Medien (Firebase Storage — TODO: Appwrite Storage nach Vuln-6-Fix) ─────

  static const int _maxImageBytes = 2 * 1024 * 1024;

  Future<Uint8List> _prepareImageForUpload(Uint8List bytes) async {
    if (bytes.length <= _maxImageBytes) return bytes;
    if (kIsWeb || _isDesktop) {
      throw Exception(
          'Das Bild ist zu groß (max. ${_maxImageBytes ~/ (1024 * 1024)} MB).');
    }
    for (final quality in [85, 70, 55, 40]) {
      final result = await FlutterImageCompress.compressWithList(
        bytes, minWidth: 4096, minHeight: 4096,
        quality: quality, format: CompressFormat.jpeg,
      );
      if (result.length <= _maxImageBytes) return result;
    }
    for (final quality in [80, 60, 40]) {
      final result = await FlutterImageCompress.compressWithList(
        bytes, minWidth: 1920, minHeight: 1920,
        quality: quality, format: CompressFormat.jpeg,
      );
      if (result.length <= _maxImageBytes) return result;
    }
    throw Exception(
        'Das Bild ist zu groß (max. ${_maxImageBytes ~/ (1024 * 1024)} MB). '
        'Bitte wähle ein kleineres Bild.');
  }

  Future<void> sendVoiceMessage(
      String convId, Uint8List audioBytes, int durationMs,
      {String contentType = 'audio/m4a'}) async {
    final msgId = ID.unique();
    final orgId = await _getOrgId(convId);
    final ext = contentType.contains('webm') ? 'webm' : 'm4a';
    final file = await _storage.createFile(
      bucketId: appwriteMediaBucketId,
      fileId: ID.unique(),
      file: InputFile.fromBytes(
          bytes: audioBytes,
          filename: '${_uid}_$msgId.$ext',
          contentType: contentType),
      permissions: [
        Permission.read(Role.any()),
        Permission.delete(Role.user(_uid)),
      ],
    );
    final audioUrl = appwriteFileViewUrl(file.$id);

    final msg = Message(
      id: msgId,
      senderUid: _uid,
      senderName: _displayName,
      text: '',
      sentAt: DateTime.now().toUtc(),
      audioUrl: audioUrl,
      audioDurationMs: durationMs,
    );
    await _db.createDocument(
      databaseId: _dbId,
      collectionId: _colMessages,
      documentId: msgId,
      data: {...msg.toAppwrite(), 'convId': convId, 'orgId': orgId},
      permissions: _msgPerms(convId),
    );
    await _updateLastMessage(convId, '🎤 Sprachnachricht');
  }

  Future<void> sendImage(String convId, Uint8List imageBytes,
      {String mimeType = 'image/jpeg'}) async {
    final orgId = await _getOrgId(convId);
    const allowedMimeTypes = {
      'image/gif', 'image/jpeg', 'image/jpg', 'image/png', 'image/webp'
    };
    final normalizedMime = mimeType.toLowerCase();
    if (!allowedMimeTypes.any((t) => normalizedMime.startsWith(t))) {
      throw Exception('Nicht unterstützter Dateityp: $mimeType');
    }
    final msgId = ID.unique();
    final isGif = normalizedMime.startsWith('image/gif');
    final Uint8List uploadBytes;
    final String ext;
    final String uploadContentType;

    if (isGif) {
      const maxGifBytes = 5 * 1024 * 1024;
      if (imageBytes.length > maxGifBytes) {
        throw Exception('Das GIF ist zu groß (max. 5 MB).');
      }
      if (imageBytes.length < 6 ||
          imageBytes[0] != 0x47 || imageBytes[1] != 0x49 ||
          imageBytes[2] != 0x46 || imageBytes[3] != 0x38) {
        throw Exception('Ungültiges GIF-Format.');
      }
      uploadBytes = imageBytes;
      ext = 'gif';
      uploadContentType = 'image/gif';
    } else {
      uploadBytes = await _prepareImageForUpload(imageBytes);
      ext = 'jpg';
      uploadContentType = 'image/jpeg';
    }

    final file = await _storage.createFile(
      bucketId: appwriteMediaBucketId,
      fileId: ID.unique(),
      file: InputFile.fromBytes(
          bytes: uploadBytes,
          filename: '${_uid}_$msgId.$ext',
          contentType: uploadContentType),
      permissions: [
        Permission.read(Role.any()),
        Permission.delete(Role.user(_uid)),
      ],
    );
    final imageUrl = appwriteFileViewUrl(file.$id);

    final msg = Message(
      id: msgId,
      senderUid: _uid,
      senderName: _displayName,
      text: '',
      sentAt: DateTime.now().toUtc(),
      imageUrl: imageUrl,
      isGif: isGif,
    );
    await _db.createDocument(
      databaseId: _dbId,
      collectionId: _colMessages,
      documentId: msgId,
      data: {...msg.toAppwrite(), 'convId': convId, 'orgId': orgId},
      permissions: _msgPerms(convId),
    );
    await _updateLastMessage(convId, '[Bild]');
  }

  Future<void> sendFile(
      String convId, Uint8List fileBytes, String fileName, int fileSize) async {
    final orgId = await _getOrgId(convId);
    const maxBytes = 5 * 1024 * 1024;
    if (fileSize > maxBytes) {
      throw Exception('Die Datei ist zu groß (max. 5 MB).');
    }
    final msgId = ID.unique();
    final awFile = await _storage.createFile(
      bucketId: appwriteMediaBucketId,
      fileId: ID.unique(),
      file: InputFile.fromBytes(
          bytes: fileBytes,
          filename: fileName),
      permissions: [
        Permission.read(Role.any()),
        Permission.delete(Role.user(_uid)),
      ],
    );
    final fileUrl = appwriteFileViewUrl(awFile.$id);

    final msg = Message(
      id: msgId,
      senderUid: _uid,
      senderName: _displayName,
      text: '',
      sentAt: DateTime.now().toUtc(),
      fileUrl: fileUrl,
      fileName: fileName,
      fileSizeBytes: fileSize,
    );
    await _db.createDocument(
      databaseId: _dbId,
      collectionId: _colMessages,
      documentId: msgId,
      data: {...msg.toAppwrite(), 'convId': convId, 'orgId': orgId},
      permissions: _msgPerms(convId),
    );
    await _updateLastMessage(convId, '📎 $fileName');
  }

  // ── Abstimmungen ───────────────────────────────────────────────────────────

  Stream<Poll?> watchPoll(String convId, String pollId) {
    return _watchDocument(_colPolls, pollId, Poll.fromAppwrite);
  }

  Future<void> createPoll(
    String convId, {
    required String question,
    required List<String> optionTexts,
    required bool multipleChoice,
    bool isAnonymous = false,
    DateTime? expiresAt,
    required String orgId,
  }) async {
    final pollId = ID.unique();
    final msgId = ID.unique();
    final poll = Poll(
      id: pollId,
      convId: convId,
      question: question,
      options: optionTexts
          .asMap()
          .entries
          .map((e) => PollOption(id: '${e.key}', text: e.value))
          .toList(),
      createdBy: _uid,
      createdByName: _displayName,
      createdAt: DateTime.now().toUtc(),
      multipleChoice: multipleChoice,
      isAnonymous: isAnonymous,
      expiresAt: expiresAt,
    );
    final preview = question.length > 60
        ? '📊 ${question.substring(0, 60)}…'
        : '📊 $question';

    await _db.createDocument(
      databaseId: _dbId,
      collectionId: _colPolls,
      documentId: pollId,
      data: {...poll.toAppwrite(), 'orgId': orgId},
      permissions: _pollPerms(convId),
    );
    final msg = Message(
      id: msgId,
      senderUid: _uid,
      senderName: _displayName,
      text: preview,
      sentAt: DateTime.now().toUtc(),
      pollId: pollId,
    );
    await _db.createDocument(
      databaseId: _dbId,
      collectionId: _colMessages,
      documentId: msgId,
      data: {...msg.toAppwrite(), 'convId': convId, 'orgId': orgId},
      permissions: _msgPerms(convId),
    );
    await _updateLastMessage(convId, preview);
  }

  Future<void> castVote(String convId, String pollId, String optionId) async {
    final doc = await _db.getDocument(
        databaseId: _dbId, collectionId: _colPolls, documentId: pollId);
    final poll = Poll.fromAppwrite({r'$id': doc.$id, ...doc.data});

    final votes = Map<String, List<String>>.from(
      poll.votes.map((k, v) => MapEntry(k, List<String>.from(v))),
    );

    if (poll.multipleChoice) {
      final voters = votes[optionId] ?? [];
      if (voters.contains(_uid)) {
        voters.remove(_uid);
      } else {
        voters.add(_uid);
      }
      votes[optionId] = voters;
    } else {
      final previousOptionId = poll.options
          .map((o) => o.id)
          .where((id) => (votes[id] ?? []).contains(_uid))
          .firstOrNull;
      if (previousOptionId == optionId) {
        votes[optionId] = (votes[optionId] ?? [])..remove(_uid);
      } else {
        if (previousOptionId != null) {
          votes[previousOptionId] =
              (votes[previousOptionId] ?? [])..remove(_uid);
        }
        votes[optionId] = [...(votes[optionId] ?? []), _uid];
      }
    }

    await _db.updateDocument(
        databaseId: _dbId,
        collectionId: _colPolls,
        documentId: pollId,
        data: {'votesJson': jsonEncode(votes)});
  }

  Future<void> closePoll(String convId, String pollId) async {
    await _db.updateDocument(
        databaseId: _dbId,
        collectionId: _colPolls,
        documentId: pollId,
        data: {'isClosed': true});
  }

  // ── Geplante Nachrichten ───────────────────────────────────────────────────

  Stream<List<ScheduledMessage>> watchScheduledMessages(String convId) {
    return _watchQuery(
      _colScheduled,
      ScheduledMessage.fromAppwrite,
      [
        Query.equal('convId', convId),
        Query.equal('senderUid', _uid),
        Query.orderAsc('scheduledFor'),
      ],
      null,
    );
  }

  Future<void> scheduleMessage(
      String convId, String text, DateTime scheduledFor) async {
    final smId = ID.unique();
    final sm = ScheduledMessage(
      id: smId,
      convId: convId,
      text: text,
      senderUid: _uid,
      senderName: _displayName,
      scheduledFor: scheduledFor,
      createdAt: DateTime.now().toUtc(),
    );
    await _db.createDocument(
      databaseId: _dbId,
      collectionId: _colScheduled,
      documentId: smId,
      data: sm.toAppwrite(),
      // Privater Entwurf des Autors bis zum Versand; beim Senden wird daraus
      // eine reguläre Nachricht mit Team-ACL (siehe `sendScheduledMessage`).
      permissions: [
        Permission.read(Role.user(_uid)),
        Permission.update(Role.user(_uid)),
        Permission.delete(Role.user(_uid)),
      ],
    );
  }

  Future<void> deleteScheduledMessage(
      String convId, String scheduledMessageId) async {
    await _db.deleteDocument(
        databaseId: _dbId,
        collectionId: _colScheduled,
        documentId: scheduledMessageId);
  }

  Future<void> sendScheduledMessage(ScheduledMessage sm) async {
    await sendMessage(sm.convId, sm.text);
    await deleteScheduledMessage(sm.convId, sm.id);
  }

  // ── Reports ────────────────────────────────────────────────────────────────

  Future<void> reportMessage({
    required String convId,
    required String orgId,
    required String orgAdminUid,
    required Message message,
  }) async {
    await _db.createDocument(
      databaseId: _dbId,
      collectionId: _colReports,
      documentId: ID.unique(),
      data: {
        'convId': convId,
        'orgId': orgId,
        'orgAdminUid': orgAdminUid,
        'reportedByUid': _uid,
        'msgId': message.id,
        'messageText': message.text,
        'messageSenderName': message.senderName,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'status': 'pending',
      },
      // Nur der Melder — die Function `on-new-report` setzt danach die ACL auf
      // die Aufsicht (Admin/Mods). Der Client kann fremde Aufsichts-Rollen nicht
      // selbst granten.
      permissions: [Permission.read(Role.user(_uid))],
    );
  }

  Stream<List<Map<String, dynamic>>> watchReports(String orgId) {
    return _watchQuery<Map<String, dynamic>>(
      _colReports,
      (data) => {'id': data[r'$id'], ...data},
      [Query.equal('orgId', orgId), Query.orderDesc('createdAt')],
      null,
    );
  }

  Future<void> deleteMessage(String convId, String msgId) async {
    await _db.deleteDocument(
        databaseId: _dbId, collectionId: _colMessages, documentId: msgId);
  }

  Future<void> markReportReviewed(String reportId, String orgId) async {
    await _db.updateDocument(
        databaseId: _dbId,
        collectionId: _colReports,
        documentId: reportId,
        data: {'status': 'reviewed'});
    try {
      final org = await _db.getDocument(
          databaseId: _dbId, collectionId: _colOrgs, documentId: orgId);
      final current = org.data['pendingReportsCount'] as int? ?? 0;
      if (current > 0) {
        await _db.updateDocument(
            databaseId: _dbId,
            collectionId: _colOrgs,
            documentId: orgId,
            data: {'pendingReportsCount': current - 1});
      }
    } catch (_) {}
  }

  // ── Hilfsmethoden ──────────────────────────────────────────────────────────

  Future<void> _updateLastMessage(String convId, String preview) async {
    await _db.updateDocument(
      databaseId: _dbId,
      collectionId: _colConvs,
      documentId: convId,
      data: {
        'lastMessage': preview,
        'lastMessageAt': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }

  Future<void> _postSystemMessage(
      String convId, String orgId, String event, String targetName) async {
    final msgId = ID.unique();
    final msg = Message(
      id: msgId,
      senderUid: 'system',
      senderName: 'system',
      text: '',
      sentAt: DateTime.now().toUtc(),
      type: 'system',
      systemEvent: event,
      systemActorName: _displayName,
      systemTargetName: targetName,
    );
    await _db.createDocument(
      databaseId: _dbId,
      collectionId: _colMessages,
      documentId: msgId,
      data: {...msg.toAppwrite(), 'convId': convId, 'orgId': orgId},
      permissions: _msgPerms(convId),
    );
  }

  Future<({List<String> canApproveUids, List<String> guardianUids})>
      _buildSupervisorUids(String orgId, List<String> participantUids) async {
    final orgDoc = await _db.getDocument(
        databaseId: _dbId, collectionId: _colOrgs, documentId: orgId);
    final orgAdminUid = orgDoc.data['adminUid'] as String;

    final modsResult = await _db.listDocuments(
      databaseId: _dbId,
      collectionId: _colMembers,
      queries: [
        Query.equal('orgId', orgId),
        Query.equal('role', 'moderator'),
        Query.limit(100),
      ],
    );
    final moderatorUids =
        modsResult.documents.map((d) => d.data['uid'] as String).toList();

    final guardianUids = <String>[];
    for (final uid in participantUids) {
      final memberDoc =
          await _safeGetDocument(_colMembers, '${orgId}_$uid');
      if (memberDoc == null) continue;
      final guards = List<String>.from(
          memberDoc.data['guardianUids'] as List? ?? []);
      for (final g in guards) {
        if (!guardianUids.contains(g)) guardianUids.add(g);
      }
    }

    return (
      canApproveUids: {orgAdminUid, ...moderatorUids}.toList(),
      guardianUids: guardianUids,
    );
  }

  Future<dynamic> _safeGetDocument(String col, String docId) async {
    try {
      return await _db.getDocument(
          databaseId: _dbId, collectionId: col, documentId: docId);
    } on AppwriteException catch (e) {
      if (e.code == 404) return null;
      rethrow;
    }
  }
}
