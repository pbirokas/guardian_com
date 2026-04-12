import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/claim_request.dart';
import '../../../core/models/org_invite_consent.dart';
import '../../../core/services/parent_claim_service.dart';
import '../../auth/providers/auth_provider.dart';

final parentClaimServiceProvider =
    Provider<ParentClaimService>((ref) => ParentClaimService());

/// Pending incoming ClaimRequests for the current user (child perspective).
final incomingClaimRequestsProvider =
    StreamProvider<List<ClaimRequest>>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(parentClaimServiceProvider).watchIncomingClaims();
});

/// All outgoing ClaimRequests sent by the current user (parent perspective).
final outgoingClaimRequestsProvider =
    StreamProvider<List<ClaimRequest>>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(parentClaimServiceProvider).watchOutgoingClaims();
});

/// Verified children of the current user.
final myChildrenProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(parentClaimServiceProvider).watchMyChildren();
});

/// Verified parents of the current user.
final myParentsProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(parentClaimServiceProvider).watchMyParents();
});

/// Pending OrgInviteConsents where the current user (as a parent) must act.
final pendingOrgConsentsProvider =
    StreamProvider<List<OrgInviteConsent>>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(parentClaimServiceProvider).watchPendingConsentsForMe();
});
