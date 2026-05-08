int _toInt(dynamic v, [int d = 0]) => (v as num?)?.toInt() ?? d;
DateTime? _toDateTime(dynamic v) =>
    v == null ? null : DateTime.fromMillisecondsSinceEpoch((v as num).toInt());

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
        sentCount: _toInt(map['sentCount']),
        receivedCount: _toInt(map['receivedCount']),
        lastActive: _toDateTime(map['lastActive']),
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
        sentCount: _toInt(map['sentCount']),
        receivedCount: _toInt(map['receivedCount']),
        lastActive: _toDateTime(map['lastActive']),
        chats: (map['chats'] as List<dynamic>)
            .map((c) => ChildSummaryChat.fromMap(Map<String, dynamic>.from(c as Map)))
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
        generatedAt: DateTime.fromMillisecondsSinceEpoch((map['generatedAt'] as num).toInt()),
        orgs: (map['orgs'] as List<dynamic>)
            .map((o) => ChildSummaryOrg.fromMap(Map<String, dynamic>.from(o as Map)))
            .toList(),
      );
}
