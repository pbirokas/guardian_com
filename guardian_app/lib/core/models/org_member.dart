import 'package:cloud_firestore/cloud_firestore.dart';
import 'app_user.dart';

enum MemberStatus { active, pending }

enum ChildAlertInterval {
  always,
  hourly,
  daily,
  never;

  String get label => switch (this) {
        ChildAlertInterval.always => 'Jede Nachricht',
        ChildAlertInterval.hourly => 'Max. 1x pro Stunde',
        ChildAlertInterval.daily => 'Max. 1x pro Tag',
        ChildAlertInterval.never => 'Nie',
      };
}

class OrgMember {
  final String uid;
  final String displayName;
  final String email;
  final String? photoUrl;
  final OrgRole role;
  final DateTime joinedAt;
  final List<String> guardianUids; // nur für Kinder
  final MemberStatus status;
  final ChildAlertInterval childAlertInterval; // nur für Guardians
  final Map<String, DateTime> lastChildAlertAt; // childUid -> last alert time

  const OrgMember({
    required this.uid,
    required this.displayName,
    required this.email,
    this.photoUrl,
    required this.role,
    required this.joinedAt,
    this.guardianUids = const [],
    this.status = MemberStatus.active,
    this.childAlertInterval = ChildAlertInterval.hourly,
    this.lastChildAlertAt = const {},
  });

  factory OrgMember.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return OrgMember(
      uid: doc.id,
      displayName: (data['displayName'] as String? ?? '').isNotEmpty
          ? data['displayName'] as String
          : (data['email'] as String? ?? '?'),
      email: data['email'] as String? ?? '',
      photoUrl: data['photoUrl'] as String?,
      role: OrgRole.values.byName(data['role'] as String),
      joinedAt: (data['joinedAt'] as Timestamp).toDate(),
      guardianUids: <String>{
        // Migrate: support old single guardianUid field
        if (data['guardianUid'] != null) data['guardianUid'] as String,
        for (final g in (data['guardianUids'] as List? ?? [])) g as String,
      }.toList(),
      status: MemberStatus.values.byName(data['status'] as String? ?? 'active'),
      childAlertInterval: ChildAlertInterval.values
          .where((e) => e.name == (data['childAlertInterval'] as String?))
          .firstOrNull ?? ChildAlertInterval.hourly,
      lastChildAlertAt: data['lastChildAlertAt'] == null
          ? {}
          : Map<String, dynamic>.from(data['lastChildAlertAt'] as Map)
              .map((k, v) => MapEntry(k, (v as Timestamp).toDate())),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'displayName': displayName,
        'email': email,
        if (photoUrl != null) 'photoUrl': photoUrl,
        'role': role.name,
        'joinedAt': Timestamp.fromDate(joinedAt),
        'guardianUids': guardianUids,
        'status': status.name,
        'childAlertInterval': childAlertInterval.name,
      };
}
