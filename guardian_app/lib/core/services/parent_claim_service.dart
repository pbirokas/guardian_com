import 'dart:async';
import 'dart:convert';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/enums.dart';
import '../models/child_summary.dart';
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
  ParentClaimService({
    required Client client,
    required String uid,
    required String displayName,
    required String email,
  })  : _db = Databases(client),
        _realtime = Realtime(client),
        _functions = Functions(client),
        _uid = uid,
        _displayName = displayName,
        _email = email;

  final Databases _db;
  final Realtime _realtime;
  final Functions _functions;
  final String _uid;
  final String _displayName;
  final String _email;

  static const _dbId = 'guardian';
  static const _colUsers = 'users';
  static const _colClaims = 'claim_requests';
  static const _colConsents = 'org_invite_consents';

  // ── Realtime helper ────────────────────────────────────────────────────────

  Stream<List<T>> _watchQuery<T>(
    String collectionId,
    T Function(Map<String, dynamic>) fromDoc,
    List<String> queries,
  ) {
    late StreamController<List<T>> ctrl;
    RealtimeSubscription? sub;

    Future<void> reload() async {
      if (ctrl.isClosed) return;
      try {
        final result = await _db.listDocuments(
          databaseId: _dbId,
          collectionId: collectionId,
          queries: [...queries, Query.limit(200)],
        );
        final items = result.documents
            .map((d) => fromDoc({r'$id': d.$id, ...d.data}))
            .toList();
        if (!ctrl.isClosed) ctrl.add(items);
      } catch (e) {
        if (!ctrl.isClosed) ctrl.addError(e);
      }
    }

    void dispose() {
      sub?.close();
      ctrl.close();
    }

    ctrl = StreamController(onCancel: dispose);
    sub = _realtime.subscribe(
        ['databases.$_dbId.collections.$collectionId.documents']);
    sub.stream.listen((_) => reload(), onDone: dispose, onError: (_) {});
    reload();
    return ctrl.stream;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Outgoing claim requests (parent perspective)
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> sendClaimRequest(String childEmail) async {
    final normalized = childEmail.toLowerCase().trim();

    final res = await _db.listDocuments(
      databaseId: _dbId,
      collectionId: _colUsers,
      queries: [Query.equal('email', normalized), Query.limit(1)],
    );
    if (res.documents.isEmpty) throw const _ClaimException('user_not_found');

    final childUid = res.documents.first.$id;
    if (childUid == _uid) throw const _ClaimException('cannot_claim_self');

    // Duplicate check client-side (OR-query not supported in Appwrite)
    final existing = await _db.listDocuments(
      databaseId: _dbId,
      collectionId: _colClaims,
      queries: [Query.equal('fromUid', _uid), Query.equal('status', 'pending')],
    );
    if (existing.documents.any((d) => d.data['toUid'] == childUid)) {
      throw const _ClaimException('already_exists');
    }

    final now = DateTime.now();
    await _db.createDocument(
      databaseId: _dbId,
      collectionId: _colClaims,
      documentId: ID.unique(),
      data: {
        'fromUid': _uid,
        'fromName': _displayName,
        'fromEmail': _email,
        'toUid': childUid,
        'toEmail': normalized,
        'status': 'pending',
        'createdAt': now.toIso8601String(),
        'expiresAt': now.add(const Duration(days: 7)).toIso8601String(),
      },
      permissions: [
        Permission.read(Role.user(_uid)),
        Permission.update(Role.user(_uid)),
        Permission.read(Role.user(childUid)),
        Permission.update(Role.user(childUid)),
      ],
    );
  }

  Future<void> cancelClaimRequest(String requestId) async {
    await _db.updateDocument(
      databaseId: _dbId,
      collectionId: _colClaims,
      documentId: requestId,
      data: {'status': ClaimRequestStatus.cancelled.name},
    );
  }

  Stream<List<ClaimRequest>> watchOutgoingClaims() {
    return _watchQuery<ClaimRequest>(
      _colClaims,
      ClaimRequest.fromAppwrite,
      [Query.equal('fromUid', _uid), Query.orderDesc('createdAt')],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Incoming claim requests (child perspective)
  // ──────────────────────────────────────────────────────────────────────────

  Stream<List<ClaimRequest>> watchIncomingClaims() {
    return _watchQuery<ClaimRequest>(
      _colClaims,
      ClaimRequest.fromAppwrite,
      [
        Query.equal('toUid', _uid),
        Query.equal('status', 'pending'),
        Query.orderDesc('createdAt'),
      ],
    );
  }

  Future<void> confirmClaimRequest(String requestId) async {
    await _db.updateDocument(
      databaseId: _dbId,
      collectionId: _colClaims,
      documentId: requestId,
      data: {'status': ClaimRequestStatus.confirmed.name},
    );
  }

  Future<void> rejectClaimRequest(String requestId) async {
    await _db.updateDocument(
      databaseId: _dbId,
      collectionId: _colClaims,
      documentId: requestId,
      data: {'status': ClaimRequestStatus.rejected.name},
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Verified relationships
  // ──────────────────────────────────────────────────────────────────────────

  Stream<List<Map<String, dynamic>>> watchMyChildren() =>
      _watchRelatives('verifiedChildUids');

  Stream<List<Map<String, dynamic>>> watchMyParents() =>
      _watchRelatives('verifiedParentUids');

  /// Watches [field] on the current user doc and fetches each referenced user.
  Stream<List<Map<String, dynamic>>> _watchRelatives(String field) {
    late StreamController<List<Map<String, dynamic>>> ctrl;
    RealtimeSubscription? sub;

    Future<void> reload() async {
      if (ctrl.isClosed) return;
      try {
        final doc = await _db.getDocument(
            databaseId: _dbId, collectionId: _colUsers, documentId: _uid);
        final uids =
            List<String>.from(doc.data[field] as List? ?? []);
        if (uids.isEmpty) {
          if (!ctrl.isClosed) ctrl.add([]);
          return;
        }
        final docs = await Future.wait(
          uids.map((u) => _db.getDocument(
              databaseId: _dbId, collectionId: _colUsers, documentId: u)),
        );
        if (!ctrl.isClosed) {
          ctrl.add(docs.map((d) => {'uid': d.$id, ...d.data}).toList());
        }
      } catch (e) {
        if (!ctrl.isClosed) ctrl.addError(e);
      }
    }

    void dispose() {
      sub?.close();
      ctrl.close();
    }

    ctrl = StreamController(onCancel: dispose);
    sub = _realtime.subscribe(
        ['databases.$_dbId.collections.$_colUsers.documents.$_uid']);
    sub.stream.listen((_) => reload(), onDone: dispose, onError: (_) {});
    reload();
    return ctrl.stream;
  }

  /// Revokes a verified parent-child connection from both sides.
  Future<void> revokeConnection(String otherUid) async {
    // No transactions in Appwrite — two sequential read-modify-write pairs.
    await _removeFromArrayField(_colUsers, _uid, 'verifiedParentUids', otherUid);
    await _removeFromArrayField(_colUsers, _uid, 'verifiedChildUids', otherUid);
    await _removeFromArrayField(
        _colUsers, otherUid, 'verifiedParentUids', _uid);
    await _removeFromArrayField(
        _colUsers, otherUid, 'verifiedChildUids', _uid);
  }

  Future<void> _removeFromArrayField(
      String col, String docId, String field, String value) async {
    final doc = await _db.getDocument(
        databaseId: _dbId, collectionId: col, documentId: docId);
    final list = List<String>.from(doc.data[field] as List? ?? [])
      ..remove(value);
    await _db.updateDocument(
        databaseId: _dbId,
        collectionId: col,
        documentId: docId,
        data: {field: list});
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Org-invite consent (parent perspective)
  // ──────────────────────────────────────────────────────────────────────────

  Stream<List<OrgInviteConsent>> watchPendingConsentsForMe() {
    return _watchQuery<OrgInviteConsent>(
      _colConsents,
      OrgInviteConsent.fromAppwrite,
      [
        Query.contains('parentUids', [_uid]),
        Query.equal('status', 'pending'),
        Query.orderDesc('createdAt'),
      ],
    );
  }

  Future<void> approveOrgConsent(String consentId) async {
    await _db.updateDocument(
      databaseId: _dbId,
      collectionId: _colConsents,
      documentId: consentId,
      data: {
        'status': OrgInviteConsentStatus.approved.name,
        'approvedBy': _uid,
      },
    );
  }

  Future<void> vetoOrgConsent(String consentId) async {
    await _db.updateDocument(
      databaseId: _dbId,
      collectionId: _colConsents,
      documentId: consentId,
      data: {
        'status': OrgInviteConsentStatus.vetoed.name,
        'vetoedBy': _uid,
      },
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Child activity summary
  // ──────────────────────────────────────────────────────────────────────────

  Future<ChildSummary> getChildSummary(String childUid, String period) async {
    final result = await _functions.createExecution(
      functionId: 'get-child-summary',
      body: jsonEncode({'childUid': childUid, 'period': period}),
      method: ExecutionMethod.pOST,
    );
    final data =
        jsonDecode(result.responseBody) as Map<String, dynamic>;
    return ChildSummary.fromMap(data);
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
