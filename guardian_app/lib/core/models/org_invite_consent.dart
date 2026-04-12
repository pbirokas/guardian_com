import 'package:cloud_firestore/cloud_firestore.dart';

enum OrgInviteConsentStatus { pending, approved, vetoed, expired }

/// Represents a pending parental-consent request created when a child
/// with verified parents is invited to an organisation.
///
/// Firestore collection: /orgInviteConsents/{consentId}
class OrgInviteConsent {
  final String id;

  /// UID of the child being invited.
  final String childUid;
  final String childName;

  /// Target organisation.
  final String orgId;
  final String orgName;

  /// Who sent the invitation.
  final String invitedByUid;
  final String invitedByName;

  /// In-org guardian UIDs proposed by the inviting admin.
  final List<String> proposedGuardianUids;

  /// All verified parents of the child — they all receive a consent request.
  final List<String> parentUids;

  /// UID of the parent who approved (if any).
  final String? approvedBy;

  /// UID of the parent who vetoed (if any).
  final String? vetoedBy;

  final OrgInviteConsentStatus status;
  final DateTime createdAt;

  /// Consent expires 7 days after creation.
  final DateTime expiresAt;

  const OrgInviteConsent({
    required this.id,
    required this.childUid,
    required this.childName,
    required this.orgId,
    required this.orgName,
    required this.invitedByUid,
    required this.invitedByName,
    required this.proposedGuardianUids,
    required this.parentUids,
    this.approvedBy,
    this.vetoedBy,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
  });

  bool get isPending =>
      status == OrgInviteConsentStatus.pending &&
      DateTime.now().isBefore(expiresAt);

  bool get isExpired =>
      status == OrgInviteConsentStatus.pending &&
      DateTime.now().isAfter(expiresAt);

  factory OrgInviteConsent.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return OrgInviteConsent(
      id: doc.id,
      childUid: d['childUid'] as String,
      childName: d['childName'] as String? ?? '',
      orgId: d['orgId'] as String,
      orgName: d['orgName'] as String? ?? '',
      invitedByUid: d['invitedByUid'] as String,
      invitedByName: d['invitedByName'] as String? ?? '',
      proposedGuardianUids:
          List<String>.from(d['proposedGuardianUids'] as List? ?? []),
      parentUids: List<String>.from(d['parentUids'] as List? ?? []),
      approvedBy: d['approvedBy'] as String?,
      vetoedBy: d['vetoedBy'] as String?,
      status: OrgInviteConsentStatus.values
          .byName(d['status'] as String? ?? 'pending'),
      createdAt: (d['createdAt'] as Timestamp).toDate(),
      expiresAt: (d['expiresAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'childUid': childUid,
        'childName': childName,
        'orgId': orgId,
        'orgName': orgName,
        'invitedByUid': invitedByUid,
        'invitedByName': invitedByName,
        'proposedGuardianUids': proposedGuardianUids,
        'parentUids': parentUids,
        if (approvedBy != null) 'approvedBy': approvedBy,
        if (vetoedBy != null) 'vetoedBy': vetoedBy,
        'status': status.name,
        'createdAt': Timestamp.fromDate(createdAt),
        'expiresAt': Timestamp.fromDate(expiresAt),
      };
}
