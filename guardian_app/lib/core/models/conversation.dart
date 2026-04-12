import 'package:cloud_firestore/cloud_firestore.dart';

enum ConversationStatus { pending, approved, rejected, archived }

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
  final String? requestorGuardianUid;
  final List<String> canApproveUids;
  final List<String> guardianUids;
  final Map<String, DateTime> lastReadAt;
  final Map<String, DateTime> typingUsers;
  final String? pinnedMessageId;
  final String? pinnedMessageText;

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
    this.requestorGuardianUid,
    this.canApproveUids = const [],
    this.guardianUids = const [],
    this.lastReadAt = const {},
    this.typingUsers = const {},
    this.pinnedMessageId,
    this.pinnedMessageText,
  });

  bool hasUnread(String uid) {
    if (lastMessageAt == null) return false;
    final lastRead = lastReadAt[uid];
    if (lastRead == null) return true;
    return lastMessageAt!.isAfter(lastRead);
  }

  factory Conversation.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final rawLastRead = data['lastReadAt'];
    final lastReadAt = rawLastRead == null
        ? <String, DateTime>{}
        : Map<String, dynamic>.from(rawLastRead as Map).map(
            (uid, ts) => MapEntry<String, DateTime>(
                uid, (ts as Timestamp).toDate()),
          );
    final rawTyping = data['typingUsers'];
    final typingUsers = rawTyping == null
        ? <String, DateTime>{}
        : Map<String, dynamic>.from(rawTyping as Map).map(
            (uid, ts) => MapEntry<String, DateTime>(
                uid, (ts as Timestamp).toDate()),
          );
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
      requestorGuardianUid: data['requestorGuardianUid'] as String?,
      canApproveUids: List<String>.from(data['canApproveUids'] as List? ?? []),
      guardianUids: List<String>.from(data['guardianUids'] as List? ?? []),
      lastReadAt: lastReadAt,
      typingUsers: typingUsers,
      pinnedMessageId: data['pinnedMessageId'] as String?,
      pinnedMessageText: data['pinnedMessageText'] as String?,
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
        'canApproveUids': canApproveUids,
        'guardianUids': guardianUids,
        'lastReadAt': lastReadAt.map((uid, dt) => MapEntry(uid, Timestamp.fromDate(dt))),
        if (requestorGuardianUid != null)
          'requestorGuardianUid': requestorGuardianUid,
        if (name != null) 'name': name,
        if (approvedBy != null) 'approvedBy': approvedBy,
        if (approvedAt != null) 'approvedAt': Timestamp.fromDate(approvedAt!),
        if (lastMessage != null) 'lastMessage': lastMessage,
        if (lastMessageAt != null)
          'lastMessageAt': Timestamp.fromDate(lastMessageAt!),
        if (pinnedMessageId != null) 'pinnedMessageId': pinnedMessageId,
        if (pinnedMessageText != null) 'pinnedMessageText': pinnedMessageText,
      };

  String otherUid(String myUid) =>
      participantUids.firstWhere((uid) => uid != myUid);
}
