import 'dart:convert';

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
  final String? imageUrl;
  final bool isGroup;
  final String? requestorGuardianUid;
  final List<String> canApproveUids;
  final List<String> guardianUids;
  final Map<String, DateTime> lastReadAt;
  final Map<String, DateTime> typingUsers;
  final String? pinnedMessageId;
  final String? pinnedMessageText;
  // Per-user display names for direct chats (key = uid, value = custom name)
  final Map<String, String> personalNames;

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
    this.imageUrl,
    this.isGroup = false,
    this.requestorGuardianUid,
    this.canApproveUids = const [],
    this.guardianUids = const [],
    this.lastReadAt = const {},
    this.typingUsers = const {},
    this.pinnedMessageId,
    this.pinnedMessageText,
    this.personalNames = const {},
  });

  bool hasUnread(String uid) {
    if (lastMessageAt == null) return false;
    final lastRead = lastReadAt[uid];
    if (lastRead == null) return true;
    return lastMessageAt!.isAfter(lastRead);
  }

  /// Wie [hasUnread], aber nutzt die separate read_receipts-Collection statt lastReadAt.
  /// [allReceipts] ist eine Map<convId, readAt> des angemeldeten Nutzers.
  bool hasUnreadWith(String uid, Map<String, DateTime> allReceipts) {
    if (lastMessageAt == null) return false;
    final lastRead = allReceipts[id];
    if (lastRead == null) return true;
    return lastMessageAt!.isAfter(lastRead);
  }


  String otherUid(String myUid) =>
      participantUids.firstWhere((uid) => uid != myUid);

  factory Conversation.fromAppwrite(Map<String, dynamic> data) {
    final namesJson = data['personalNamesJson'] as String?;
    final personalNames = (namesJson != null && namesJson.isNotEmpty)
        ? Map<String, String>.from(jsonDecode(namesJson) as Map)
        : <String, String>{};
    return Conversation(
      id: data[r'$id'] as String,
      orgId: data['orgId'] as String,
      orgAdminUid: data['orgAdminUid'] as String? ?? '',
      participantUids:
          List<String>.from(data['participantUids'] as List? ?? []),
      requestedBy: data['requestedBy'] as String,
      status: ConversationStatus.values
          .byName(data['status'] as String? ?? 'pending'),
      createdAt: DateTime.parse(data['createdAt'] as String).toLocal(),
      approvedBy: data['approvedBy'] as String?,
      approvedAt: data['approvedAt'] != null
          ? DateTime.parse(data['approvedAt'] as String).toLocal()
          : null,
      lastMessage: data['lastMessage'] as String?,
      lastMessageAt: data['lastMessageAt'] != null
          ? DateTime.parse(data['lastMessageAt'] as String).toLocal()
          : null,
      name: data['name'] as String?,
      imageUrl: data['imageUrl'] as String?,
      isGroup: data['isGroup'] as bool? ?? false,
      requestorGuardianUid: data['requestorGuardianUid'] as String?,
      canApproveUids: List<String>.from(data['canApproveUids'] as List? ?? []),
      guardianUids: List<String>.from(data['guardianUids'] as List? ?? []),
      lastReadAt: const {},
      typingUsers: const {},
      pinnedMessageId: data['pinnedMessageId'] as String?,
      pinnedMessageText: data['pinnedMessageText'] as String?,
      personalNames: personalNames,
    );
  }

  Map<String, dynamic> toAppwrite() => {
        'orgId': orgId,
        'orgAdminUid': orgAdminUid,
        'participantUids': participantUids,
        'requestedBy': requestedBy,
        'status': status.name,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'isGroup': isGroup,
        'canApproveUids': canApproveUids,
        'guardianUids': guardianUids,
        'personalNamesJson': jsonEncode(personalNames),
        if (requestorGuardianUid != null)
          'requestorGuardianUid': requestorGuardianUid,
        if (name != null) 'name': name,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (approvedBy != null) 'approvedBy': approvedBy,
        if (approvedAt != null) 'approvedAt': approvedAt!.toUtc().toIso8601String(),
        if (lastMessage != null) 'lastMessage': lastMessage,
        if (lastMessageAt != null)
          'lastMessageAt': lastMessageAt!.toUtc().toIso8601String(),
        if (pinnedMessageId != null) 'pinnedMessageId': pinnedMessageId,
        if (pinnedMessageText != null) 'pinnedMessageText': pinnedMessageText,
      };
}
