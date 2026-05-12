import 'dart:convert';

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

  /// UIDs der verifizierten Elternteile (global, orgs-übergreifend).
  /// Wird durch gegenseitig bestätigte ClaimRequests befüllt.
  final List<String> verifiedParentUids;

  /// UIDs der verifizierten Kinder (Gegenstück zu verifiedParentUids).
  final List<String> verifiedChildUids;

  /// E-Mail vor anderen Mitgliedern verstecken (nur UI-Ebene).
  final bool hideEmail;

  const AppUser({
    required this.uid,
    required this.email,
    required this.displayName,
    this.photoUrl,
    required this.memberships,
    required this.createdAt,
    this.isChild = false,
    this.verifiedParentUids = const [],
    this.verifiedChildUids = const [],
    this.hideEmail = false,
  });

  bool get hasVerifiedParents => verifiedParentUids.isNotEmpty;
  bool get hasVerifiedChildren => verifiedChildUids.isNotEmpty;

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
      verifiedParentUids: List<String>.from(
          data['verifiedParentUids'] as List? ?? []),
      verifiedChildUids: List<String>.from(
          data['verifiedChildUids'] as List? ?? []),
      hideEmail: data['hideEmail'] as bool? ?? false,
    );
  }

  factory AppUser.fromAppwrite(Map<String, dynamic> data) {
    final membershipsRaw = data['membershipsJson'] as String? ?? '[]';
    final List<dynamic> decoded = jsonDecode(membershipsRaw);
    return AppUser(
      uid: data[r'$id'] as String,
      email: data['email'] as String,
      displayName: data['displayName'] as String,
      photoUrl: data['photoUrl'] as String?,
      memberships:
          decoded.map((m) => OrgMembership.fromMap(m as Map<String, dynamic>)).toList(),
      createdAt: DateTime.parse(data['createdAt'] as String),
      isChild: data['isChild'] as bool? ?? false,
      verifiedParentUids:
          List<String>.from(data['verifiedParentUids'] as List? ?? []),
      verifiedChildUids:
          List<String>.from(data['verifiedChildUids'] as List? ?? []),
      hideEmail: data['hideEmail'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toAppwrite() => {
        'email': email,
        'displayName': displayName,
        if (photoUrl != null) 'photoUrl': photoUrl,
        'membershipsJson':
            jsonEncode(memberships.map((m) => m.toMap()).toList()),
        'createdAt': createdAt.toIso8601String(),
        'isChild': isChild,
        'verifiedParentUids': verifiedParentUids,
        'verifiedChildUids': verifiedChildUids,
        'hideEmail': hideEmail,
      };

  Map<String, dynamic> toFirestore() => {
        'email': email,
        'displayName': displayName,
        if (photoUrl != null) 'photoUrl': photoUrl,
        'memberships': memberships.map((m) => m.toMap()).toList(),
        'createdAt': Timestamp.fromDate(createdAt),
        'isChild': isChild,
        'verifiedParentUids': verifiedParentUids,
        'verifiedChildUids': verifiedChildUids,
        'hideEmail': hideEmail,
      };

  OrgRole? roleInOrg(String orgId) {
    try {
      return memberships.firstWhere((m) => m.orgId == orgId).role;
    } catch (_) {
      return null;
    }
  }
}
