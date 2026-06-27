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
}
