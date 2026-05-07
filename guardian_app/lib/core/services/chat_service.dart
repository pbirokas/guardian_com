import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/poll.dart';
import '../models/scheduled_message.dart';

class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _uid => _auth.currentUser!.uid;

  static bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  String get _senderName =>
      _auth.currentUser!.displayName ?? 'Unbekannt';

  static int _byLastMessageDesc(Conversation a, Conversation b) {
    if (a.lastMessageAt == null) return 1;
    if (b.lastMessageAt == null) return -1;
    return b.lastMessageAt!.compareTo(a.lastMessageAt!);
  }

  /// Swallows Firestore permission-denied errors on a stream so non-admins
  /// get an empty list instead of an exception propagating to the UI.
  Stream<T> _swallowPermissionDenied<T>(Stream<T> stream) =>
      stream.handleError(
        (_) {},
        test: (e) => e is FirebaseException && e.code == 'permission-denied',
      );

  void _updateLastMessage(WriteBatch batch, String convId, String preview) {
    batch.update(_db.collection('conversations').doc(convId), {
      'lastMessage': preview,
      'lastMessageAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  Future<String> _getOrgAdminUid(String orgId) async {
    final doc = await _db.collection('organizations').doc(orgId).get();
    return doc.data()!['adminUid'] as String;
  }

  /// Erstellt die Listen für canApproveUids (Admin + Moderatoren) und guardianUids (Guardians der Kind-Teilnehmer)
  Future<({List<String> canApproveUids, List<String> guardianUids})>
      _buildSupervisorUids(
          String orgId, List<String> participantUids) async {
    final orgAdminUid = await _getOrgAdminUid(orgId);

    final moderatorsSnap = await _db
        .collection('organizations')
        .doc(orgId)
        .collection('members')
        .where('role', isEqualTo: 'moderator')
        .get();
    final moderatorUids = moderatorsSnap.docs.map((d) => d.id).toList();

    // Guardians aller Kind-Teilnehmer ermitteln
    final guardianUids = <String>[];
    for (final uid in participantUids) {
      final memberDoc = await _db
          .collection('organizations')
          .doc(orgId)
          .collection('members')
          .doc(uid)
          .get();
      final data = memberDoc.data();
      if (data == null) continue;
      // Support both legacy singular field and current plural list
      final singular = data['guardianUid'] as String?;
      final plural = List<String>.from(data['guardianUids'] as List? ?? []);
      final allGuardians = {singular, ...plural}.whereType<String>();
      for (final g in allGuardians) {
        if (!guardianUids.contains(g)) guardianUids.add(g);
      }
    }

    return (
      canApproveUids: {orgAdminUid, ...moderatorUids}.toList(),
      guardianUids: guardianUids,
    );
  }

  /// Guardian-Modus: Anfrage stellen
  Future<Conversation> requestConversation(
      String orgId, String targetUid) async {
    final existing = await _db
        .collection('conversations')
        .where('participantUids', arrayContains: _uid)
        .get();

    for (final doc in existing.docs) {
      final conv = Conversation.fromFirestore(doc);
      if (conv.orgId == orgId && conv.participantUids.contains(targetUid)) {
        // Abgelehnte oder archivierte Einträge ignorieren — neue Anfrage erlauben
        if (conv.status == ConversationStatus.rejected ||
            conv.status == ConversationStatus.archived) {
          continue;
        }
        throw Exception('Eine Konversation mit dieser Person existiert bereits.');
      }
    }

    // Guardian des Antragstellers ermitteln (für requestorGuardianUid)
    final memberDoc = await _db
        .collection('organizations')
        .doc(orgId)
        .collection('members')
        .doc(_uid)
        .get();
    final guardianUid = memberDoc.data()?['guardianUid'] as String?;

    final orgAdminUid = await _getOrgAdminUid(orgId);
    final supervisors =
        await _buildSupervisorUids(orgId, [_uid, targetUid]);

    final ref = _db.collection('conversations').doc();
    final conv = Conversation(
      id: ref.id,
      orgId: orgId,
      orgAdminUid: orgAdminUid,
      participantUids: [_uid, targetUid],
      requestedBy: _uid,
      status: ConversationStatus.pending,
      createdAt: DateTime.now(),
      requestorGuardianUid: guardianUid,
      canApproveUids: supervisors.canApproveUids,
      guardianUids: supervisors.guardianUids,
    );
    await ref.set(conv.toFirestore());
    return conv;
  }

  /// Sheltered-Modus: Admin erstellt Verbindung direkt (sofort approved)
  Future<Conversation> createApprovedConversation(
      String orgId, String targetUid) async {
    final existing = await _db
        .collection('conversations')
        .where('participantUids', arrayContains: _uid)
        .get();

    for (final doc in existing.docs) {
      final conv = Conversation.fromFirestore(doc);
      if (conv.orgId == orgId &&
          conv.participantUids.contains(targetUid) &&
          !conv.isGroup) {
        return conv;
      }
    }

    final orgAdminUid = await _getOrgAdminUid(orgId);
    final supervisors =
        await _buildSupervisorUids(orgId, [_uid, targetUid]);
    final ref = _db.collection('conversations').doc();
    final conv = Conversation(
      id: ref.id,
      orgId: orgId,
      orgAdminUid: orgAdminUid,
      participantUids: [_uid, targetUid],
      requestedBy: _uid,
      status: ConversationStatus.approved,
      createdAt: DateTime.now(),
      approvedBy: _uid,
      approvedAt: DateTime.now(),
      canApproveUids: supervisors.canApproveUids,
      guardianUids: supervisors.guardianUids,
    );
    await ref.set(conv.toFirestore());
    return conv;
  }

  Future<void> renameConversation(String convId, String name) async {
    await _db.collection('conversations').doc(convId).update({'name': name.trim()});
  }

  Future<void> setPersonalName(String convId, String name) async {
    final trimmed = name.trim();
    await _db.collection('conversations').doc(convId).update({
      'personalNames.$_uid': trimmed.isEmpty ? FieldValue.delete() : trimmed,
    });
  }

  Future<void> approveConversation(String convId) async {
    await _db.collection('conversations').doc(convId).update({
      'status': ConversationStatus.approved.name,
      'approvedBy': _uid,
      'approvedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  Future<void> markAsRead(String convId) async {
    await _db.collection('conversations').doc(convId).update({
      'lastReadAt.$_uid': Timestamp.fromDate(DateTime.now()),
    });
  }

  Future<void> archiveConversation(String convId) async {
    await _db.collection('conversations').doc(convId).update({
      'status': ConversationStatus.archived.name,
    });
  }

  Future<void> deleteConversation(String convId) async {
    final messagesRef = _db
        .collection('conversations')
        .doc(convId)
        .collection('messages');

    // Nachrichten in Batches à 400 löschen (Firestore-Limit: 500 ops/batch)
    while (true) {
      final snap = await messagesRef.limit(400).get();
      if (snap.docs.isEmpty) break;
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }

    await _db.collection('conversations').doc(convId).delete();
  }

  Stream<Conversation?> watchConversation(String convId) {
    return _db
        .collection('conversations')
        .doc(convId)
        .snapshots()
        .map((s) => s.exists ? Conversation.fromFirestore(s) : null);
  }

  Future<void> rejectConversation(String convId) async {
    // Abgelehnte Anfragen werden gelöscht, damit dieselbe Anfrage später
    // erneut gestellt werden kann.
    await _db.collection('conversations').doc(convId).delete();
  }

  Future<void> sendMessage(
    String convId,
    String text, {
    String? replyToId,
    String? replyToSenderName,
    String? replyToText,
  }) async {
    final msgRef =
        _db.collection('conversations').doc(convId).collection('messages').doc();
    final batch = _db.batch();

    batch.set(msgRef, Message(
      id: msgRef.id,
      senderUid: _uid,
      senderName: _senderName,
      text: text,
      sentAt: DateTime.now(),
      replyToId: replyToId,
      replyToSenderName: replyToSenderName,
      replyToText: replyToText,
    ).toFirestore());

    _updateLastMessage(
        batch, convId, text.length > 200 ? '${text.substring(0, 200)}…' : text);

    await batch.commit();
  }

  DocumentReference _msgRef(String convId, String messageId) => _db
      .collection('conversations')
      .doc(convId)
      .collection('messages')
      .doc(messageId);

  Future<void> editMessage(
    String convId,
    String messageId,
    String newText, {
    bool archive = false,
    String? archivedByUid,
    String? archivedByName,
  }) async {
    await _msgRef(convId, messageId).update({
      'text': newText,
      'editedAt': Timestamp.now(),
      if (archive) 'isArchived': true,
      if (archive && archivedByUid != null) 'archivedByUid': archivedByUid,
      if (archive && archivedByName != null) 'archivedByName': archivedByName,
    });
  }

  Future<void> softDeleteMessage(String convId, String messageId) async {
    await _msgRef(convId, messageId).update({
      'deletedAt': Timestamp.now(),
      'deletedBy': _uid,
    });
  }

  Future<void> undoDeleteMessage(String convId, String messageId) async {
    await _msgRef(convId, messageId).update({
      'deletedAt': FieldValue.delete(),
      'deletedBy': FieldValue.delete(),
    });
  }

  // Maximale Dateigröße für Chat-Bilder: 2 MB
  static const int _maxImageBytes = 2 * 1024 * 1024;

  /// Gibt komprimierte JPEG-Bytes zurück (auf Web: Bytes unverändert).
  /// Verringert Qualität schrittweise bis das Bild unter [_maxImageBytes] liegt.
  /// Wirft eine Exception wenn das Bild auch bei minimaler Qualität zu groß ist.
  Future<Uint8List> _prepareImageForUpload(Uint8List bytes) async {
    // flutter_image_compress unterstützt kein Web und kein Windows → Bytes direkt verwenden
    if (kIsWeb || _isDesktop) {
      if (bytes.length > _maxImageBytes) {
        throw Exception(
            'Das Bild ist zu groß (max. ${_maxImageBytes ~/ (1024 * 1024)} MB).');
      }
      return bytes;
    }

    const maxDimension = 1024;
    final qualities = [80, 65, 50, 35];

    for (final quality in qualities) {
      final result = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: maxDimension,
        minHeight: maxDimension,
        quality: quality,
        format: CompressFormat.jpeg,
      );
      if (result.length <= _maxImageBytes) return result;
    }

    // Letzte Chance: sehr kleine Auflösung
    final fallback = await FlutterImageCompress.compressWithList(
      bytes,
      minWidth: 512,
      minHeight: 512,
      quality: 25,
      format: CompressFormat.jpeg,
    );
    if (fallback.length <= _maxImageBytes) return fallback;

    throw Exception(
        'Das Bild ist zu groß (max. ${_maxImageBytes ~/ (1024 * 1024)} MB). '
        'Bitte wähle ein kleineres Bild.');
  }

  Future<void> sendVoiceMessage(
      String convId, Uint8List audioBytes, int durationMs,
      {String contentType = 'audio/m4a'}) async {
    final msgRef =
        _db.collection('conversations').doc(convId).collection('messages').doc();

    final ext = contentType.contains('webm') ? 'webm' : 'm4a';
    final storageRef = FirebaseStorage.instance
        .ref()
        .child('voiceMessages/$convId/${_uid}_${msgRef.id}.$ext');
    await storageRef.putData(
      audioBytes,
      SettableMetadata(contentType: contentType),
    );
    final audioUrl = await storageRef.getDownloadURL();

    final batch = _db.batch();
    batch.set(
        msgRef,
        Message(
          id: msgRef.id,
          senderUid: _uid,
          senderName: _senderName,
          text: '',
          sentAt: DateTime.now(),
          audioUrl: audioUrl,
          audioDurationMs: durationMs,
        ).toFirestore());
    _updateLastMessage(batch, convId, '🎤 Sprachnachricht');
    await batch.commit();
  }

  Future<void> sendImage(String convId, Uint8List imageBytes,
      {String mimeType = 'image/jpeg'}) async {
    const allowedMimeTypes = {
      'image/gif', 'image/jpeg', 'image/jpg', 'image/png', 'image/webp'
    };
    final normalizedMime = mimeType.toLowerCase();
    if (!allowedMimeTypes.any((t) => normalizedMime.startsWith(t))) {
      throw Exception('Nicht unterstützter Dateityp: $mimeType');
    }

    final msgRef =
        _db.collection('conversations').doc(convId).collection('messages').doc();

    final isGif = normalizedMime.startsWith('image/gif');
    final Uint8List uploadBytes;
    final String ext;
    final String uploadContentType;

    if (isGif) {
      // GIFs nicht komprimieren — JPEG-Konvertierung würde Animation zerstören
      const maxGifBytes = 5 * 1024 * 1024;
      if (imageBytes.length > maxGifBytes) {
        throw Exception('Das GIF ist zu groß (max. 5 MB).');
      }
      // Magic-Byte-Check: GIF87a = 47 49 46 38 37 61 / GIF89a = 47 49 46 38 39 61
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

    final storageRef = FirebaseStorage.instance
        .ref()
        .child('chatImages/$convId/${_uid}_${msgRef.id}.$ext');
    await storageRef.putData(
      uploadBytes,
      SettableMetadata(contentType: uploadContentType),
    );
    final imageUrl = await storageRef.getDownloadURL();

    final batch = _db.batch();
    batch.set(msgRef, Message(
      id: msgRef.id,
      senderUid: _uid,
      senderName: _senderName,
      text: '',
      sentAt: DateTime.now(),
      imageUrl: imageUrl,
      isGif: isGif,
    ).toFirestore());
    _updateLastMessage(batch, convId, '[Bild]');
    await batch.commit();
  }

  /// Datei (max. 5 MB) in den Chat senden.
  Future<void> sendFile(
      String convId, Uint8List fileBytes, String fileName, int fileSize) async {
    const maxBytes = 5 * 1024 * 1024; // 5 MB
    if (fileSize > maxBytes) {
      throw Exception('Die Datei ist zu groß (max. 5 MB).');
    }

    final msgRef =
        _db.collection('conversations').doc(convId).collection('messages').doc();

    final ext = fileName.contains('.') ? fileName.split('.').last : '';
    final storageRef = FirebaseStorage.instance
        .ref()
        .child('chatFiles/$convId/${_uid}_${msgRef.id}${ext.isNotEmpty ? '.$ext' : ''}');
    await storageRef.putData(fileBytes);
    final fileUrl = await storageRef.getDownloadURL();

    final batch = _db.batch();
    batch.set(msgRef, Message(
      id: msgRef.id,
      senderUid: _uid,
      senderName: _senderName,
      text: '',
      sentAt: DateTime.now(),
      fileUrl: fileUrl,
      fileName: fileName,
      fileSizeBytes: fileSize,
    ).toFirestore());
    _updateLastMessage(batch, convId, '📎 $fileName');
    await batch.commit();
  }

  Stream<List<Conversation>> watchOrgConversations(String orgId) {
    return _db
        .collection('conversations')
        .where('participantUids', arrayContains: _uid)
        .snapshots()
        .map((s) {
      final all = s.docs.map(Conversation.fromFirestore).toList();
      // Client-seitig nach Org filtern und nach letzter Nachricht sortieren
      final filtered =
          all.where((c) => c.orgId == orgId).toList();
      filtered.sort(_byLastMessageDesc);
      return filtered;
    });
  }

  /// Alle genehmigten Konversationen des aktuellen Nutzers (org-übergreifend, für Share-Target)
  Stream<List<Conversation>> watchAllMyApprovedConversations() {
    return _db
        .collection('conversations')
        .where('participantUids', arrayContains: _uid)
        .snapshots()
        .map((s) {
      final all = s.docs.map(Conversation.fromFirestore).toList();
      final filtered = all
          .where((c) => c.status == ConversationStatus.approved)
          .toList()
        ..sort(_byLastMessageDesc);
      return filtered;
    });
  }

  /// Alle Konversationen einer Org — nur für Admins.
  /// Queried by orgId (not orgAdminUid) so that conversations created before
  /// an admin transfer are also visible to the current admin.
  /// Non-admins get an empty list (permission denied is swallowed).
  Stream<List<Conversation>> watchAdminConversations(String orgId) {
    final raw = _db
        .collection('conversations')
        .where('orgId', isEqualTo: orgId)
        .snapshots()
        .map((s) {
      final all = s.docs.map(Conversation.fromFirestore).toList();
      all.sort(_byLastMessageDesc);
      return all;
    });
    return _swallowPermissionDenied(raw);
  }

  Stream<List<Conversation>> watchPendingRequests(String orgId) {
    final raw = _db
        .collection('conversations')
        .where('orgId', isEqualTo: orgId)
        .snapshots()
        .map((s) {
      final all = s.docs.map(Conversation.fromFirestore).toList();
      return all
          .where((c) => c.status == ConversationStatus.pending)
          .toList();
    });
    return _swallowPermissionDenied(raw);
  }

  /// Ausstehende Anfragen für Moderatoren (canApproveUids enthält ihre UID)
  Stream<List<Conversation>> watchModeratorPendingRequests(String orgId) {
    return _db
        .collection('conversations')
        .where('canApproveUids', arrayContains: _uid)
        .snapshots()
        .map((s) {
      final all = s.docs.map(Conversation.fromFirestore).toList();
      return all
          .where((c) =>
              c.orgId == orgId && c.status == ConversationStatus.pending)
          .toList();
    });
  }

  /// Ausstehende Anfragen für Guardians (via guardianUids, pending only)
  Stream<List<Conversation>> watchGuardianPendingRequests(String orgId) {
    return _db
        .collection('conversations')
        .where('guardianUids', arrayContains: _uid)
        .snapshots()
        .map((s) {
      final all = s.docs.map(Conversation.fromFirestore).toList();
      // Nur Konversationen wo der Guardian nicht auch Admin/Moderator ist
      // und status pending ist
      return all
          .where((c) =>
              c.orgId == orgId &&
              c.status == ConversationStatus.pending &&
              c.orgAdminUid != _uid)
          .toList();
    });
  }

  /// Alle überwachten Konversationen (für Moderatoren + Guardians, approved)
  Stream<List<Conversation>> watchSupervisorConversations(String orgId) {
    return _db
        .collection('conversations')
        .where('canApproveUids', arrayContains: _uid)
        .snapshots()
        .map((s) {
      final all = s.docs.map(Conversation.fromFirestore).toList();
      final filtered = all
          .where((c) =>
              c.orgId == orgId &&
              c.status == ConversationStatus.approved &&
              !c.participantUids.contains(_uid))
          .toList();
      filtered.sort(_byLastMessageDesc);
      return filtered;
    });
  }

  Future<Conversation> createGroupChat(
      String orgId, String name, List<String> memberUids) async {
    final orgAdminUid = await _getOrgAdminUid(orgId);
    final supervisors = await _buildSupervisorUids(orgId, memberUids);
    final ref = _db.collection('conversations').doc();
    final conv = Conversation(
      id: ref.id,
      orgId: orgId,
      orgAdminUid: orgAdminUid,
      participantUids: memberUids,
      requestedBy: _uid,
      status: ConversationStatus.approved,
      createdAt: DateTime.now(),
      approvedBy: _uid,
      approvedAt: DateTime.now(),
      name: name,
      isGroup: true,
      canApproveUids: supervisors.canApproveUids,
      guardianUids: supervisors.guardianUids,
    );
    await ref.set(conv.toFirestore());
    return conv;
  }

  /// Postet eine System-Nachricht (z.B. Mitglied hinzugefügt/entfernt) in den Chat.
  Future<void> _postSystemMessage(
      String convId, String event, String targetName) async {
    final msgRef =
        _db.collection('conversations').doc(convId).collection('messages').doc();
    final actor = _auth.currentUser;
    await msgRef.set({
      'type': 'system',
      'systemEvent': event,
      'systemActorName': actor?.displayName ?? actor?.email ?? '',
      'systemTargetName': targetName,
      'senderUid': 'system',
      'senderName': 'system',
      'text': '',
      'sentAt': Timestamp.fromDate(DateTime.now()),
      'isArchived': false,
    });
  }

  /// Entfernt ein Mitglied aus einem Gruppen-Chat (Sheltered-Modus).
  Future<void> removeMemberFromConversation(
      String convId, String memberUid, {String memberName = ''}) async {
    await _db.collection('conversations').doc(convId).update({
      'participantUids': FieldValue.arrayRemove([memberUid]),
    });
    if (memberName.isNotEmpty) {
      await _postSystemMessage(convId, 'memberRemoved', memberName);
    }
  }

  /// Fügt neue Mitglieder zu einem bestehenden Gruppen-Chat hinzu (Sheltered-Modus).
  /// Aktualisiert participantUids und guardianUids der Konversation.
  Future<void> addMembersToConversation(
      String convId, String orgId, List<String> newMemberUids) async {
    final newGuardianUids = <String>[];
    final addedNames = <String>[];
    for (final uid in newMemberUids) {
      final memberDoc = await _db
          .collection('organizations')
          .doc(orgId)
          .collection('members')
          .doc(uid)
          .get();
      final data = memberDoc.data();
      if (data == null) continue;
      final singular = data['guardianUid'] as String?;
      final plural = List<String>.from(data['guardianUids'] as List? ?? []);
      newGuardianUids.addAll({singular, ...plural}.whereType<String>());
      final name = data['displayName'] as String? ?? '';
      if (name.isNotEmpty) addedNames.add(name);
    }

    await _db.collection('conversations').doc(convId).update({
      'participantUids': FieldValue.arrayUnion(newMemberUids),
      if (newGuardianUids.isNotEmpty)
        'guardianUids': FieldValue.arrayUnion(newGuardianUids),
    });

    for (final name in addedNames) {
      await _postSystemMessage(convId, 'memberAdded', name);
    }
  }

  /// Überwachte Konversationen für Guardians (via guardianUids, approved)
  Stream<List<Conversation>> watchGuardianSupervisorConversations(
      String orgId) {
    return _db
        .collection('conversations')
        .where('guardianUids', arrayContains: _uid)
        .where('status', isEqualTo: 'approved')
        .snapshots()
        .map((s) {
      final all = s.docs.map(Conversation.fromFirestore).toList();
      // UI deduplicates against participantUids-based approved list,
      // so we don't filter by !participantUids here — otherwise a guardian
      // who was removed from a group (but child still in it) would lose
      // the supervised view.
      final filtered = all.where((c) => c.orgId == orgId).toList();
      filtered.sort(_byLastMessageDesc);
      return filtered;
    });
  }

  /// Sheltered-Modus: Moderator sieht alle Chats der Org (via Admin-UID)
  Stream<List<Conversation>> watchShelteredModeratorConversations(
      String orgId, String adminUid) {
    return _db
        .collection('conversations')
        .where('orgId', isEqualTo: orgId)
        .where('orgAdminUid', isEqualTo: adminUid)
        .snapshots()
        .map((s) {
      final all = s.docs.map(Conversation.fromFirestore).toList();
      final filtered = all
          .where((c) =>
              c.status == ConversationStatus.approved &&
              !c.participantUids.contains(_uid))
          .toList();
      filtered.sort(_byLastMessageDesc);
      return filtered;
    });
  }

  Stream<List<Message>> watchMessages(String convId, {int limit = 30}) {
    return _db
        .collection('conversations')
        .doc(convId)
        .collection('messages')
        .orderBy('sentAt')
        .limitToLast(limit)
        .snapshots()
        .map((s) => s.docs.map(Message.fromFirestore).toList());
  }

  Future<void> reportMessage({
    required String convId,
    required String orgId,
    required String orgAdminUid,
    required Message message,
  }) async {
    await _db.collection('reports').add({
      'convId': convId,
      'msgId': message.id,
      'orgId': orgId,
      'orgAdminUid': orgAdminUid,
      'reportedBy': _uid,
      'reportedAt': Timestamp.now(),
      'messageText': message.text,
      'messageSenderUid': message.senderUid,
      'messageSenderName': message.senderName,
      'status': 'pending',
    });
  }

  Stream<List<Map<String, dynamic>>> watchReports(String orgId) {
    return _db
        .collection('reports')
        .where('orgId', isEqualTo: orgId)
        .orderBy('reportedAt', descending: true)
        .snapshots()
        .map((s) => s.docs
            .map((d) => {'id': d.id, ...d.data()})
            .toList());
  }

  Future<void> markReportReviewed(String reportId) async {
    await _db.collection('reports').doc(reportId).update({'status': 'reviewed'});
  }

  // ── Polls ──────────────────────────────────────────────────────────────────

  // ── Angepinnte Nachricht ──────────────────────────────────────────────────

  Future<void> pinMessage(
      String convId, String msgId, String text) async {
    await _db.collection('conversations').doc(convId).update({
      'pinnedMessageId': msgId,
      'pinnedMessageText':
          text.length > 120 ? '${text.substring(0, 120)}…' : text,
    });
  }

  Future<void> unpinMessage(String convId) async {
    await _db.collection('conversations').doc(convId).update({
      'pinnedMessageId': FieldValue.delete(),
      'pinnedMessageText': FieldValue.delete(),
    });
  }

  Future<void> createPoll(
    String convId, {
    required String question,
    required List<String> optionTexts,
    required bool multipleChoice,
    bool isAnonymous = false,
    DateTime? expiresAt,
  }) async {
    final pollRef = _db
        .collection('conversations')
        .doc(convId)
        .collection('polls')
        .doc();
    final msgRef = _db
        .collection('conversations')
        .doc(convId)
        .collection('messages')
        .doc();

    final poll = Poll(
      id: pollRef.id,
      convId: convId,
      question: question,
      options: optionTexts
          .asMap()
          .entries
          .map((e) => PollOption(id: '${e.key}', text: e.value))
          .toList(),
      createdBy: _uid,
      createdByName: _senderName,
      createdAt: DateTime.now(),
      multipleChoice: multipleChoice,
      isAnonymous: isAnonymous,
      expiresAt: expiresAt,
    );

    final preview = question.length > 60
        ? '📊 ${question.substring(0, 60)}…'
        : '📊 $question';

    final batch = _db.batch();
    batch.set(pollRef, poll.toFirestore());
    batch.set(
      msgRef,
      Message(
        id: msgRef.id,
        senderUid: _uid,
        senderName: _senderName,
        text: preview,
        sentAt: DateTime.now(),
        pollId: pollRef.id,
      ).toFirestore(),
    );
    _updateLastMessage(batch, convId, preview);
    await batch.commit();
  }

  Future<void> castVote(
      String convId, String pollId, String optionId) async {
    final pollRef = _db
        .collection('conversations')
        .doc(convId)
        .collection('polls')
        .doc(pollId);

    final snap = await pollRef.get();
    if (!snap.exists) return;
    final data = snap.data() as Map<String, dynamic>;
    final multipleChoice = data['multipleChoice'] as bool? ?? false;
    final rawVotes =
        Map<String, dynamic>.from(data['votes'] as Map? ?? {});
    final optionIds = (data['options'] as List)
        .map((o) => (o as Map)['id'] as String)
        .toList();

    final updates = <String, dynamic>{};

    if (multipleChoice) {
      final voters =
          List<String>.from(rawVotes[optionId] as List? ?? []);
      if (voters.contains(_uid)) {
        updates['votes.$optionId'] = FieldValue.arrayRemove([_uid]);
      } else {
        updates['votes.$optionId'] = FieldValue.arrayUnion([_uid]);
      }
    } else {
      // Find which option (if any) the user previously voted for
      final previousOptionId = optionIds.where((id) {
        final voters = List<String>.from(rawVotes[id] as List? ?? []);
        return voters.contains(_uid);
      }).firstOrNull;

      if (previousOptionId == optionId) {
        // Same option tapped again → toggle off (remove vote)
        updates['votes.$optionId'] = FieldValue.arrayRemove([_uid]);
      } else {
        // Different option → move vote
        if (previousOptionId != null) {
          updates['votes.$previousOptionId'] = FieldValue.arrayRemove([_uid]);
        }
        updates['votes.$optionId'] = FieldValue.arrayUnion([_uid]);
      }
    }

    if (updates.isNotEmpty) await pollRef.update(updates);
  }

  Future<void> closePoll(String convId, String pollId) async {
    await _db
        .collection('conversations')
        .doc(convId)
        .collection('polls')
        .doc(pollId)
        .update({'isClosed': true});
  }

  Stream<Poll?> watchPoll(String convId, String pollId) {
    return _db
        .collection('conversations')
        .doc(convId)
        .collection('polls')
        .doc(pollId)
        .snapshots()
        .map((s) => s.exists ? Poll.fromFirestore(s) : null);
  }

  // ── Geplante Nachrichten ───────────────────────────────────────────────────

  Stream<List<ScheduledMessage>> watchScheduledMessages(String convId) {
    return _db
        .collection('conversations')
        .doc(convId)
        .collection('scheduledMessages')
        .where('senderUid', isEqualTo: _uid)
        .orderBy('scheduledFor')
        .snapshots()
        .map((s) => s.docs.map(ScheduledMessage.fromFirestore).toList());
  }

  Future<void> scheduleMessage(
      String convId, String text, DateTime scheduledFor) async {
    final user = _auth.currentUser!;
    final ref = _db
        .collection('conversations')
        .doc(convId)
        .collection('scheduledMessages')
        .doc();
    await ref.set(ScheduledMessage(
      id: ref.id,
      convId: convId,
      text: text,
      senderUid: user.uid,
      senderName: user.displayName ?? user.email ?? '',
      scheduledFor: scheduledFor,
      createdAt: DateTime.now(),
    ).toFirestore());
  }

  Future<void> deleteScheduledMessage(
      String convId, String scheduledMessageId) async {
    await _db
        .collection('conversations')
        .doc(convId)
        .collection('scheduledMessages')
        .doc(scheduledMessageId)
        .delete();
  }

  /// Sendet eine geplante Nachricht und löscht den Eintrag danach.
  Future<void> sendScheduledMessage(ScheduledMessage sm) async {
    await sendMessage(sm.convId, sm.text);
    await deleteScheduledMessage(sm.convId, sm.id);
  }

  // ── Tipp-Indikator ────────────────────────────────────────────────────────

  /// Setzt oder löscht den Tipp-Indikator für den aktuellen Benutzer.
  Future<void> setTyping(String convId, bool isTyping) async {
    await _db.collection('conversations').doc(convId).update({
      'typingUsers.$_uid': isTyping
          ? Timestamp.fromDate(DateTime.now())
          : FieldValue.delete(),
    });
  }

  // ── Nachrichten-Reaktionen ────────────────────────────────────────────────

  /// Setzt oder entfernt eine Reaktion (Emoji) des aktuellen Benutzers.
  /// [emoji] == null → Reaktion entfernen.
  Future<void> setReaction(
      String convId, String msgId, String? emoji) async {
    final msgRef = _msgRef(convId, msgId);
    if (emoji == null) {
      await msgRef.update({'reactions.$_uid': FieldValue.delete()});
    } else {
      await msgRef.update({'reactions.$_uid': emoji});
    }
  }
}
