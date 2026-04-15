import 'package:cloud_firestore/cloud_firestore.dart';

/// Verfügbare Aktionen im Änderungsprotokoll.
enum AuditAction {
  invitationSent,
  memberConfirmed,
  memberRemoved,
  settingsChanged,
  roleChanged,
  adminTransferred,
  keywordsChanged,
}

class OrgAuditEntry {
  final String id;
  final String actorUid;
  final String actorName;
  final AuditAction action;
  final Map<String, dynamic> details;
  final DateTime timestamp;

  const OrgAuditEntry({
    required this.id,
    required this.actorUid,
    required this.actorName,
    required this.action,
    required this.details,
    required this.timestamp,
  });

  factory OrgAuditEntry.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return OrgAuditEntry(
      id: doc.id,
      actorUid: data['actorUid'] as String? ?? '',
      actorName: data['actorName'] as String? ?? '',
      action: AuditAction.values.byName(
          data['action'] as String? ?? AuditAction.settingsChanged.name),
      details: Map<String, dynamic>.from(data['details'] as Map? ?? {}),
      timestamp: (data['timestamp'] as Timestamp).toDate(),
    );
  }
}
