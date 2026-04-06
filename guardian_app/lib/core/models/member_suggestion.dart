import 'package:cloud_firestore/cloud_firestore.dart';
import 'app_user.dart';

class MemberSuggestion {
  final String id;
  final String orgId;
  final String email;
  final OrgRole role;
  final List<String> guardianUids;
  final String suggestedByUid;
  final String suggestedByName;
  final DateTime createdAt;

  const MemberSuggestion({
    required this.id,
    required this.orgId,
    required this.email,
    required this.role,
    required this.guardianUids,
    required this.suggestedByUid,
    required this.suggestedByName,
    required this.createdAt,
  });

  factory MemberSuggestion.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MemberSuggestion(
      id: doc.id,
      orgId: data['orgId'] as String,
      email: data['email'] as String,
      role: OrgRole.values.byName(data['role'] as String),
      guardianUids: List<String>.from(data['guardianUids'] as List? ?? []),
      suggestedByUid: data['suggestedByUid'] as String,
      suggestedByName: data['suggestedByName'] as String? ?? '',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    );
  }
}
