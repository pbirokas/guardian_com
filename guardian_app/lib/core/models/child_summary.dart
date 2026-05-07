class ChildSummaryChat {
  final String convId;
  final String chatName;
  final bool isGroup;
  final int sentCount;
  final int receivedCount;
  final DateTime? lastActive;

  const ChildSummaryChat({
    required this.convId,
    required this.chatName,
    required this.isGroup,
    required this.sentCount,
    required this.receivedCount,
    this.lastActive,
  });

  factory ChildSummaryChat.fromMap(Map<String, dynamic> map) => ChildSummaryChat(
        convId: map['convId'] as String,
        chatName: map['chatName'] as String,
        isGroup: map['isGroup'] as bool? ?? false,
        sentCount: map['sentCount'] as int? ?? 0,
        receivedCount: map['receivedCount'] as int? ?? 0,
        lastActive: map['lastActive'] != null
            ? DateTime.fromMillisecondsSinceEpoch(map['lastActive'] as int)
            : null,
      );
}

class ChildSummaryOrg {
  final String orgId;
  final String orgName;
  final int sentCount;
  final int receivedCount;
  final DateTime? lastActive;
  final List<ChildSummaryChat> chats;

  const ChildSummaryOrg({
    required this.orgId,
    required this.orgName,
    required this.sentCount,
    required this.receivedCount,
    this.lastActive,
    required this.chats,
  });

  factory ChildSummaryOrg.fromMap(Map<String, dynamic> map) => ChildSummaryOrg(
        orgId: map['orgId'] as String,
        orgName: map['orgName'] as String,
        sentCount: map['sentCount'] as int? ?? 0,
        receivedCount: map['receivedCount'] as int? ?? 0,
        lastActive: map['lastActive'] != null
            ? DateTime.fromMillisecondsSinceEpoch(map['lastActive'] as int)
            : null,
        chats: (map['chats'] as List<dynamic>)
            .map((c) => ChildSummaryChat.fromMap(c as Map<String, dynamic>))
            .toList(),
      );
}

class ChildSummary {
  final String childUid;
  final String childName;
  final String period;
  final DateTime generatedAt;
  final List<ChildSummaryOrg> orgs;

  const ChildSummary({
    required this.childUid,
    required this.childName,
    required this.period,
    required this.generatedAt,
    required this.orgs,
  });

  factory ChildSummary.fromMap(Map<String, dynamic> map) => ChildSummary(
        childUid: map['childUid'] as String,
        childName: map['childName'] as String,
        period: map['period'] as String,
        generatedAt:
            DateTime.fromMillisecondsSinceEpoch(map['generatedAt'] as int),
        orgs: (map['orgs'] as List<dynamic>)
            .map((o) => ChildSummaryOrg.fromMap(o as Map<String, dynamic>))
            .toList(),
      );
}
