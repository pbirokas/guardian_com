import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/claim_request.dart';
import '../models/org_invite_consent.dart';

/// Manages the verified parent-child relationship lifecycle:
///   - Parent initiates a ClaimRequest by the child's email.
///   - Child confirms or rejects.
///   - Cloud Function handles both user-doc updates on confirmation.
///
/// Also exposes org-invite consent management:
///   - Parents watch pending OrgInviteConsents for their children.
///   - Parents can approve or veto an org invitation.
class ParentClaimService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _uid => _auth.currentUser!.uid;

  // ──────────────────────────────────────────────────────────────────────────
  // Outgoing claim requests (parent perspective)
  // ──────────────────────────────────────────────────────────────────────────

  /// Sends a ClaimRequest from the current user (parent) to the child with
  /// the given email.  Throws if:
  ///   - no registered user found for [childEmail]
  ///   - the target user is the current user
  ///   - a pending request already exists
  Future<void> sendClaimRequest(String childEmail) async {
    final normalizedEmail = childEmail.toLowerCase().trim();
    final currentUser = _auth.currentUser!;

    // Resolve child UID from email
    final query = await _db
        .collection('users')
        .where('email', isEqualTo: normalizedEmail)
        .limit(1)
        .get();
    if (query.docs.isEmpty) {
      throw const _ClaimException('user_not_found');
    }

    final childDoc = query.docs.first;
    final childUid = childDoc.id;

    if (childUid == _uid) {
      throw const _ClaimException('cannot_claim_self');
    }

    // Duplicate check
    final existing = await _db
        .collection('claimRequests')
        .where('fromUid', isEqualTo: _uid)
        .where('toUid', isEqualTo: childUid)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) {
      throw const _ClaimException('already_exists');
    }

    final now = DateTime.now();
    await _db.collection('claimRequests').add({
      'fromUid': _uid,
      'fromName': currentUser.displayName ?? currentUser.email!,
      'fromEmail': currentUser.email!,
      'toUid': childUid,
      'toEmail': normalizedEmail,
      'status': 'pending',
      'createdAt': Timestamp.fromDate(now),
      'expiresAt': Timestamp.fromDate(now.add(const Duration(days: 7))),
    });
  }

  /// Cancels an outgoing pending ClaimRequest.
  Future<void> cancelClaimRequest(String requestId) async {
    await _db.collection('claimRequests').doc(requestId).update({
      'status': ClaimRequestStatus.cancelled.name,
    });
  }

  /// Stream of ClaimRequests sent by the current user (parent perspective).
  Stream<List<ClaimRequest>> watchOutgoingClaims() {
    return _db
        .collection('claimRequests')
        .where('fromUid', isEqualTo: _uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(ClaimRequest.fromFirestore).toList());
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Incoming claim requests (child perspective)
  // ──────────────────────────────────────────────────────────────────────────

  /// Stream of pending ClaimRequests addressed to the current user (child).
  Stream<List<ClaimRequest>> watchIncomingClaims() {
    return _db
        .collection('claimRequests')
        .where('toUid', isEqualTo: _uid)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(ClaimRequest.fromFirestore).toList());
  }

  /// Confirms an incoming ClaimRequest.
  /// The Cloud Function `onClaimConfirmed` handles updating both user docs.
  Future<void> confirmClaimRequest(String requestId) async {
    await _db.collection('claimRequests').doc(requestId).update({
      'status': ClaimRequestStatus.confirmed.name,
    });
  }

  /// Rejects an incoming ClaimRequest.
  Future<void> rejectClaimRequest(String requestId) async {
    await _db.collection('claimRequests').doc(requestId).update({
      'status': ClaimRequestStatus.rejected.name,
    });
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Verified relationships
  // ──────────────────────────────────────────────────────────────────────────

  /// Stream of AppUser-like maps for the current user's verified children.
  Stream<List<Map<String, dynamic>>> watchMyChildren() {
    return _db
        .collection('users')
        .doc(_uid)
        .snapshots()
        .asyncMap((snap) async {
      final data = snap.data();
      if (data == null) return [];
      final uids =
          List<String>.from(data['verifiedChildUids'] as List? ?? []);
      if (uids.isEmpty) return [];
      final docs = await Future.wait(
          uids.map((u) => _db.collection('users').doc(u).get()));
      return docs
          .where((d) => d.exists)
          .map((d) => {'uid': d.id, ...d.data()!})
          .toList();
    });
  }

  /// Stream of AppUser-like maps for the current user's verified parents.
  Stream<List<Map<String, dynamic>>> watchMyParents() {
    return _db
        .collection('users')
        .doc(_uid)
        .snapshots()
        .asyncMap((snap) async {
      final data = snap.data();
      if (data == null) return [];
      final uids =
          List<String>.from(data['verifiedParentUids'] as List? ?? []);
      if (uids.isEmpty) return [];
      final docs = await Future.wait(
          uids.map((u) => _db.collection('users').doc(u).get()));
      return docs
          .where((d) => d.exists)
          .map((d) => {'uid': d.id, ...d.data()!})
          .toList();
    });
  }

  /// Revokes a verified parent-child connection from both sides.
  Future<void> revokeConnection(String otherUid) async {
    final batch = _db.batch();
    batch.update(_db.collection('users').doc(_uid), {
      'verifiedParentUids': FieldValue.arrayRemove([otherUid]),
      'verifiedChildUids': FieldValue.arrayRemove([otherUid]),
    });
    batch.update(_db.collection('users').doc(otherUid), {
      'verifiedParentUids': FieldValue.arrayRemove([_uid]),
      'verifiedChildUids': FieldValue.arrayRemove([_uid]),
    });
    await batch.commit();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Org-invite consent (parent perspective)
  // ──────────────────────────────────────────────────────────────────────────

  /// Stream of pending OrgInviteConsents where the current user is listed
  /// as one of the parents who must consent.
  Stream<List<OrgInviteConsent>> watchPendingConsentsForMe() {
    return _db
        .collection('orgInviteConsents')
        .where('parentUids', arrayContains: _uid)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(OrgInviteConsent.fromFirestore).toList());
  }

  /// Approves a pending OrgInviteConsent.
  /// The Cloud Function `onParentConsent` will process the invitation.
  Future<void> approveOrgConsent(String consentId) async {
    await _db.collection('orgInviteConsents').doc(consentId).update({
      'status': OrgInviteConsentStatus.approved.name,
      'approvedBy': _uid,
    });
  }

  /// Vetoes a pending OrgInviteConsent (child will NOT be added).
  Future<void> vetoOrgConsent(String consentId) async {
    await _db.collection('orgInviteConsents').doc(consentId).update({
      'status': OrgInviteConsentStatus.vetoed.name,
      'vetoedBy': _uid,
    });
  }
}

/// Internal exception type for claim operations.
/// [code] values: 'user_not_found' | 'cannot_claim_self' | 'already_exists'
class _ClaimException implements Exception {
  final String code;
  const _ClaimException(this.code);
  @override
  String toString() => 'ClaimException($code)';
}

/// Public helper so callers can inspect the error code.
extension ClaimExceptionCode on Exception {
  String? get claimCode {
    if (this is _ClaimException) return (this as _ClaimException).code;
    return null;
  }
}
