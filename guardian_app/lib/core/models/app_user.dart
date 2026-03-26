import 'package:cloud_firestore/cloud_firestore.dart';

enum OrgRole { admin, moderator, member, child }

class OrgMembership {
  final String orgId;
  final OrgRole role;
  final String? supervisorId; // only for child role

  const OrgMembership({
    required this.orgId,
    required this.role,
    this.supervisorId,
  });

  factory OrgMembership.fromMap(Map<String, dynamic> map) {
    return OrgMembership(
      orgId: map['orgId'] as String,
      role: OrgRole.values.byName(map['role'] as String),
      supervisorId: map['supervisorId'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'orgId': orgId,
        'role': role.name,
        if (supervisorId != null) 'supervisorId': supervisorId,
      };
}

class AppUser {
  final String uid;
  final String email;
  final String displayName;
  final String? photoUrl;
  final List<OrgMembership> memberships;
  final DateTime createdAt;
  final bool isChild;

  const AppUser({
    required this.uid,
    required this.email,
    required this.displayName,
    this.photoUrl,
    required this.memberships,
    required this.createdAt,
    this.isChild = false,
  });

  factory AppUser.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AppUser(
      uid: doc.id,
      email: data['email'] as String,
      displayName: data['displayName'] as String,
      photoUrl: data['photoUrl'] as String?,
      memberships: (data['memberships'] as List<dynamic>? ?? [])
          .map((m) => OrgMembership.fromMap(m as Map<String, dynamic>))
          .toList(),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      isChild: data['isChild'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'email': email,
        'displayName': displayName,
        if (photoUrl != null) 'photoUrl': photoUrl,
        'memberships': memberships.map((m) => m.toMap()).toList(),
        'createdAt': Timestamp.fromDate(createdAt),
      };

  OrgRole? roleInOrg(String orgId) {
    try {
      return memberships.firstWhere((m) => m.orgId == orgId).role;
    } catch (_) {
      return null;
    }
  }
}
