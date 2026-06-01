import 'dart:convert';

enum AuditAction {
  invitationSent,
  memberConfirmed,
  memberRemoved,
  settingsChanged,
  roleChanged,
  adminTransferred,
  keywordsChanged,
  guardiansChanged,
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

  factory OrgAuditEntry.fromAppwrite(Map<String, dynamic> data) {
    return OrgAuditEntry(
      id: data[r'$id'] as String,
      actorUid: data['actorUid'] as String? ?? '',
      actorName: data['actorName'] as String? ?? '',
      action: AuditAction.values.byName(
          data['action'] as String? ?? AuditAction.settingsChanged.name),
      details: data['detailsJson'] != null
          ? Map<String, dynamic>.from(
              jsonDecode(data['detailsJson'] as String) as Map)
          : {},
      timestamp: DateTime.parse(data['timestamp'] as String).toLocal(),
    );
  }

  Map<String, dynamic> toAppwrite(String orgId) => {
        'orgId': orgId,
        'actorUid': actorUid,
        'actorName': actorName,
        'action': action.name,
        'detailsJson': jsonEncode(details),
        'timestamp': timestamp.toUtc().toIso8601String(),
      };
}
