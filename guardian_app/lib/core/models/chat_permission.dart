import 'package:cloud_firestore/cloud_firestore.dart';

class ChatPermission {
  final String id;
  final String orgId;
  final String fromUid;
  final String toUid;
  final String grantedBy; // uid of admin/moderator who approved
  final DateTime grantedAt;
  final bool active;

  const ChatPermission({
    required this.id,
    required this.orgId,
    required this.fromUid,
    required this.toUid,
    required this.grantedBy,
    required this.grantedAt,
    required this.active,
  });

  factory ChatPermission.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ChatPermission(
      id: doc.id,
      orgId: data['orgId'] as String,
      fromUid: data['fromUid'] as String,
      toUid: data['toUid'] as String,
      grantedBy: data['grantedBy'] as String,
      grantedAt: (data['grantedAt'] as Timestamp).toDate(),
      active: data['active'] as bool,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'orgId': orgId,
        'fromUid': fromUid,
        'toUid': toUid,
        'grantedBy': grantedBy,
        'grantedAt': Timestamp.fromDate(grantedAt),
        'active': active,
      };
}
