import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/conversation.dart';
import '../models/message.dart';

class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _uid => _auth.currentUser!.uid;

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
      if (conv.orgId == orgId && conv.participantUids.contains(targetUid)) {
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
    final messagesSnap = await _db
        .collection('conversations')
        .doc(convId)
        .collection('messages')
        .limit(500)
        .get();
    final batch = _db.batch();
    for (final doc in messagesSnap.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(_db.collection('conversations').doc(convId));
    await batch.commit();
  }

  Stream<Conversation?> watchConversation(String convId) {
    return _db
        .collection('conversations')
        .doc(convId)
        .snapshots()
        .map((s) => s.exists ? Conversation.fromFirestore(s) : null);
  }

  Future<void> rejectConversation(String convId) async {
    await _db.collection('conversations').doc(convId).update({
      'status': ConversationStatus.rejected.name,
    });
  }

  Future<void> sendMessage(String convId, String text) async {
    final msgRef =
        _db.collection('conversations').doc(convId).collection('messages').doc();
    final batch = _db.batch();
    final user = _auth.currentUser!;

    batch.set(msgRef, Message(
      id: msgRef.id,
      senderUid: _uid,
      senderName: user.displayName ?? user.email ?? 'Unbekannt',
      text: text,
      sentAt: DateTime.now(),
    ).toFirestore());

    batch.update(_db.collection('conversations').doc(convId), {
      'lastMessage': text,
      'lastMessageAt': Timestamp.fromDate(DateTime.now()),
    });

    await batch.commit();
  }

  Future<void> sendImage(String convId, File imageFile) async {
    final user = _auth.currentUser!;
    final msgRef =
        _db.collection('conversations').doc(convId).collection('messages').doc();

    // Bild in Firebase Storage hochladen
    final storageRef = FirebaseStorage.instance
        .ref()
        .child('chatImages/$convId/${msgRef.id}.jpg');
    await storageRef.putFile(imageFile);
    final imageUrl = await storageRef.getDownloadURL();

    final batch = _db.batch();
    batch.set(msgRef, Message(
      id: msgRef.id,
      senderUid: _uid,
      senderName: user.displayName ?? user.email ?? 'Unbekannt',
      text: '',
      sentAt: DateTime.now(),
      imageUrl: imageUrl,
    ).toFirestore());
    batch.update(_db.collection('conversations').doc(convId), {
      'lastMessage': '[Bild]',
      'lastMessageAt': Timestamp.fromDate(DateTime.now()),
    });
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
      filtered.sort((a, b) {
        if (a.lastMessageAt == null) return 1;
        if (b.lastMessageAt == null) return -1;
        return b.lastMessageAt!.compareTo(a.lastMessageAt!);
      });
      return filtered;
    });
  }

  /// Alle Konversationen einer Org — nur für Admins (query by orgAdminUid)
  Stream<List<Conversation>> watchAdminConversations(String orgId) {
    return _db
        .collection('conversations')
        .where('orgAdminUid', isEqualTo: _uid)
        .snapshots()
        .map((s) {
      final all = s.docs.map(Conversation.fromFirestore).toList();
      final filtered = all.where((c) => c.orgId == orgId).toList();
      filtered.sort((a, b) {
        if (a.lastMessageAt == null) return 1;
        if (b.lastMessageAt == null) return -1;
        return b.lastMessageAt!.compareTo(a.lastMessageAt!);
      });
      return filtered;
    });
  }

  Stream<List<Conversation>> watchPendingRequests(String orgId) {
    return _db
        .collection('conversations')
        .where('orgAdminUid', isEqualTo: _uid)
        .snapshots()
        .map((s) {
      final all = s.docs.map(Conversation.fromFirestore).toList();
      return all
          .where((c) => c.orgId == orgId && c.status == ConversationStatus.pending)
          .toList();
    });
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
      filtered.sort((a, b) {
        if (a.lastMessageAt == null) return 1;
        if (b.lastMessageAt == null) return -1;
        return b.lastMessageAt!.compareTo(a.lastMessageAt!);
      });
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

  /// Entfernt ein Mitglied aus einem Gruppen-Chat (Sheltered-Modus).
  Future<void> removeMemberFromConversation(
      String convId, String memberUid) async {
    await _db.collection('conversations').doc(convId).update({
      'participantUids': FieldValue.arrayRemove([memberUid]),
    });
  }

  /// Fügt neue Mitglieder zu einem bestehenden Gruppen-Chat hinzu (Sheltered-Modus).
  /// Aktualisiert participantUids und guardianUids der Konversation.
  Future<void> addMembersToConversation(
      String convId, String orgId, List<String> newMemberUids) async {
    final newGuardianUids = <String>[];
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
    }

    await _db.collection('conversations').doc(convId).update({
      'participantUids': FieldValue.arrayUnion(newMemberUids),
      if (newGuardianUids.isNotEmpty)
        'guardianUids': FieldValue.arrayUnion(newGuardianUids),
    });
  }

  /// Überwachte Konversationen für Guardians (via guardianUids, approved, kein Teilnehmer)
  Stream<List<Conversation>> watchGuardianSupervisorConversations(
      String orgId) {
    return _db
        .collection('conversations')
        .where('guardianUids', arrayContains: _uid)
        .snapshots()
        .map((s) {
      final all = s.docs.map(Conversation.fromFirestore).toList();
      final filtered = all
          .where((c) =>
              c.orgId == orgId &&
              c.status == ConversationStatus.approved &&
              !c.participantUids.contains(_uid))
          .toList();
      filtered.sort((a, b) {
        if (a.lastMessageAt == null) return 1;
        if (b.lastMessageAt == null) return -1;
        return b.lastMessageAt!.compareTo(a.lastMessageAt!);
      });
      return filtered;
    });
  }

  /// Sheltered-Modus: Moderator sieht alle Chats der Org (via Admin-UID)
  Stream<List<Conversation>> watchShelteredModeratorConversations(
      String orgId, String adminUid) {
    return _db
        .collection('conversations')
        .where('orgAdminUid', isEqualTo: adminUid)
        .snapshots()
        .map((s) {
      final all = s.docs.map(Conversation.fromFirestore).toList();
      final filtered = all
          .where((c) =>
              c.orgId == orgId &&
              c.status == ConversationStatus.approved &&
              !c.participantUids.contains(_uid))
          .toList();
      filtered.sort((a, b) {
        if (a.lastMessageAt == null) return 1;
        if (b.lastMessageAt == null) return -1;
        return b.lastMessageAt!.compareTo(a.lastMessageAt!);
      });
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
}
