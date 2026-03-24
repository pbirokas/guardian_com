import 'package:cloud_firestore/cloud_firestore.dart';

enum ConversationStatus { pending, approved, rejected }

class Conversation {
  final String id;
  final String orgId;
  final String orgAdminUid;
  final List<String> participantUids;
  final String requestedBy;
  final ConversationStatus status;
  final DateTime createdAt;
  final String? approvedBy;
  final DateTime? approvedAt;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final String? name;
  final bool isGroup;

  const Conversation({
    required this.id,
    required this.orgId,
    required this.orgAdminUid,
    required this.participantUids,
    required this.requestedBy,
    required this.status,
    required this.createdAt,
    this.approvedBy,
    this.approvedAt,
    this.lastMessage,
    this.lastMessageAt,
    this.name,
    this.isGroup = false,
  });

  factory Conversation.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Conversation(
      id: doc.id,
      orgId: data['orgId'] as String,
      orgAdminUid: data['orgAdminUid'] as String? ?? '',
      participantUids: List<String>.from(data['participantUids'] as List),
      requestedBy: data['requestedBy'] as String,
      status: ConversationStatus.values
          .byName(data['status'] as String? ?? 'pending'),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      approvedBy: data['approvedBy'] as String?,
      approvedAt: data['approvedAt'] != null
          ? (data['approvedAt'] as Timestamp).toDate()
          : null,
      lastMessage: data['lastMessage'] as String?,
      lastMessageAt: data['lastMessageAt'] != null
          ? (data['lastMessageAt'] as Timestamp).toDate()
          : null,
      name: data['name'] as String?,
      isGroup: data['isGroup'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'orgId': orgId,
        'orgAdminUid': orgAdminUid,
        'participantUids': participantUids,
        'requestedBy': requestedBy,
        'status': status.name,
        'createdAt': Timestamp.fromDate(createdAt),
        'isGroup': isGroup,
        if (name != null) 'name': name,
        if (approvedBy != null) 'approvedBy': approvedBy,
        if (approvedAt != null) 'approvedAt': Timestamp.fromDate(approvedAt!),
        if (lastMessage != null) 'lastMessage': lastMessage,
        if (lastMessageAt != null)
          'lastMessageAt': Timestamp.fromDate(lastMessageAt!),
      };

  String otherUid(String myUid) =>
      participantUids.firstWhere((uid) => uid != myUid);
}
