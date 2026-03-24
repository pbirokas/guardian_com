import 'package:cloud_firestore/cloud_firestore.dart';
import 'app_user.dart';

class OrgMember {
  final String uid;
  final String displayName;
  final String email;
  final String? photoUrl;
  final OrgRole role;
  final DateTime joinedAt;

  const OrgMember({
    required this.uid,
    required this.displayName,
    required this.email,
    this.photoUrl,
    required this.role,
    required this.joinedAt,
  });

  factory OrgMember.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return OrgMember(
      uid: doc.id,
      displayName: data['displayName'] as String,
      email: data['email'] as String,
      photoUrl: data['photoUrl'] as String?,
      role: OrgRole.values.byName(data['role'] as String),
      joinedAt: (data['joinedAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'displayName': displayName,
        'email': email,
        if (photoUrl != null) 'photoUrl': photoUrl,
        'role': role.name,
        'joinedAt': Timestamp.fromDate(joinedAt),
      };
}
