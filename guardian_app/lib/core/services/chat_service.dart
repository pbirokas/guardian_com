import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

    final orgAdminUid = await _getOrgAdminUid(orgId);
    final ref = _db.collection('conversations').doc();
    final conv = Conversation(
      id: ref.id,
      orgId: orgId,
      orgAdminUid: orgAdminUid,
      participantUids: [_uid, targetUid],
      requestedBy: _uid,
      status: ConversationStatus.pending,
      createdAt: DateTime.now(),
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

  Future<Conversation> createGroupChat(
      String orgId, String name, List<String> memberUids) async {
    final orgAdminUid = await _getOrgAdminUid(orgId);
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
    );
    await ref.set(conv.toFirestore());
    return conv;
  }

  Stream<List<Message>> watchMessages(String convId) {
    return _db
        .collection('conversations')
        .doc(convId)
        .collection('messages')
        .orderBy('sentAt')
        .snapshots()
        .map((s) => s.docs.map(Message.fromFirestore).toList());
  }
}
