import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:guardian_app/l10n/app_localizations.dart';
import '../../../core/models/app_user.dart';
import '../../../core/models/claim_request.dart';
import '../../../core/models/org_invite_consent.dart';
import '../../../core/services/parent_claim_service.dart';
import '../providers/relationships_provider.dart';
import '../../organizations/providers/organizations_provider.dart';

class RelationshipsScreen extends ConsumerStatefulWidget {
  const RelationshipsScreen({super.key});

  @override
  ConsumerState<RelationshipsScreen> createState() =>
      _RelationshipsScreenState();
}

class _RelationshipsScreenState extends ConsumerState<RelationshipsScreen> {
  final _emailController = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendClaimRequest() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;
    setState(() => _sending = true);
    final l = AppLocalizations.of(context);
    try {
      await ref
          .read(parentClaimServiceProvider)
          .sendClaimRequest(email);
      if (mounted) {
        _emailController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.claimRequestSent)),
        );
      }
    } on Exception catch (e) {
      if (!mounted) return;
      final code = e.claimCode;
      String msg;
      if (code == 'user_not_found') {
        msg = l.claimRequestNotFound;
      } else if (code == 'already_exists') {
        msg = l.claimRequestAlreadyExists;
      } else {
        msg = l.errorMessage(e.toString());
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _confirmClaim(ClaimRequest req) async {
    final l = AppLocalizations.of(context);

    // Check if current user has non-child memberships that will be downgraded
    final currentUser = ref.read(currentAppUserProvider).value;
    final affectedMemberships = currentUser?.memberships
            .where((m) => m.role != OrgRole.child)
            .toList() ??
        [];

    if (affectedMemberships.isNotEmpty) {
      // Fetch org names for the warning dialog
      final db = FirebaseFirestore.instance;
      final orgDocs = await Future.wait(
        affectedMemberships.map((m) =>
            db.collection('organizations').doc(m.orgId).get()),
      );
      final orgNames = orgDocs
          .where((d) => d.exists)
          .map((d) =>
              (d.data() as Map<String, dynamic>)['name'] as String? ?? d.id)
          .toList();

      if (!mounted) return;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.roleConflictTitle),
          content: Text(l.roleConflictContent(orgNames.map((n) => '• $n').join('\n'))),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.confirmClaim),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    try {
      await ref
          .read(parentClaimServiceProvider)
          .confirmClaimRequest(req.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.claimConfirmed)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.errorMessage(e.toString()))),
        );
      }
    }
  }

  Future<void> _rejectClaim(ClaimRequest req) async {
    final l = AppLocalizations.of(context);
    try {
      await ref
          .read(parentClaimServiceProvider)
          .rejectClaimRequest(req.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.claimRejected)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.errorMessage(e.toString()))),
        );
      }
    }
  }

  Future<void> _cancelClaim(ClaimRequest req) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.claimRequestCancelTitle),
        content: Text(l.claimRequestCancelContent(req.toEmail)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.cancel)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.withdraw,
                  style: const TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(parentClaimServiceProvider)
          .cancelClaimRequest(req.id);
    } catch (e) {
      if (mounted) {
        final l2 = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l2.errorMessage(e.toString()))),
        );
      }
    }
  }

  Future<void> _revokeConnection(String otherUid, String name) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.revokeConnectionTitle),
        content: Text(l.revokeConnectionContent(name)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.cancel)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.revokeConnection,
                  style: const TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(parentClaimServiceProvider)
          .revokeConnection(otherUid);
    } catch (e) {
      if (mounted) {
        final l2 = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l2.errorMessage(e.toString()))),
        );
      }
    }
  }

  Future<void> _approveConsent(OrgInviteConsent consent) async {
    final l = AppLocalizations.of(context);
    try {
      await ref
          .read(parentClaimServiceProvider)
          .approveOrgConsent(consent.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.orgInvitationApproved)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.errorMessage(e.toString()))),
        );
      }
    }
  }

  Future<void> _vetoConsent(OrgInviteConsent consent) async {
    final l = AppLocalizations.of(context);
    try {
      await ref
          .read(parentClaimServiceProvider)
          .vetoOrgConsent(consent.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.orgInvitationVetoed)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.errorMessage(e.toString()))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final incomingAsync = ref.watch(incomingClaimRequestsProvider);
    final outgoingAsync = ref.watch(outgoingClaimRequestsProvider);
    final childrenAsync = ref.watch(myChildrenProvider);
    final parentsAsync = ref.watch(myParentsProvider);
    final consentsAsync = ref.watch(pendingOrgConsentsProvider);
    final currentUser = ref.watch(currentAppUserProvider).value;

    return Scaffold(
      appBar: AppBar(title: Text(l.myRelationships)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // ── Incoming claim requests (child sees "X wants to be your parent") ──
          ...incomingAsync.when(
            data: (requests) {
              final pending =
                  requests.where((r) => r.isPending).toList();
              if (pending.isEmpty) return const [];
              return [
                _SectionHeader(l.incomingClaimRequests(pending.length)),
                ...pending.map((req) => _IncomingClaimTile(
                      req: req,
                      onConfirm: () => _confirmClaim(req),
                      onReject: () => _rejectClaim(req),
                    )),
                const Divider(),
              ];
            },
            loading: () => const [],
            error: (_, _) => const [],
          ),

          // ── Pending org invite consents (parent approves/vetoes child org invite)
          ...consentsAsync.when(
            data: (consents) {
              if (consents.isEmpty) return const [];
              return [
                _SectionHeader(l.pendingParentConsents(consents.length)),
                ...consents.map((c) => _ConsentTile(
                      consent: c,
                      onApprove: () => _approveConsent(c),
                      onVeto: () => _vetoConsent(c),
                    )),
                const Divider(),
              ];
            },
            loading: () => const [],
            error: (_, _) => const [],
          ),

          // ── Connect a child (parent initiates) ──
          if (currentUser?.isChild != true) ...[
            _SectionHeader(l.connectChild),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _emailController,
                    decoration: InputDecoration(
                      labelText: l.emailAddress,
                      hintText: l.connectChildHint,
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    onSubmitted: (_) => _sendClaimRequest(),
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: _sending ? null : _sendClaimRequest,
                    child: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l.sendClaimRequest),
                  ),
                ],
              ),
            ),
            // Outgoing pending requests
            ...outgoingAsync.when(
              data: (reqs) {
                final pending =
                    reqs.where((r) => r.isPending).toList();
                if (pending.isEmpty) return const [];
                return pending
                    .map((req) => _OutgoingClaimTile(
                          req: req,
                          onCancel: () => _cancelClaim(req),
                        ))
                    .toList();
              },
              loading: () => const [],
              error: (_, _) => const [],
            ),
            const Divider(),
          ],

          // ── Verified children (not shown for child accounts) ──
          if (currentUser?.isChild != true) ...[
            _SectionHeader(l.myChildren),
            ...childrenAsync.when(
              data: (children) {
                if (children.isEmpty) {
                  return [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Text(l.noChildren,
                          style: const TextStyle(color: Colors.grey)),
                    ),
                  ];
                }
                return children
                    .map((u) => _RelationTile(
                          uid: u['uid'] as String,
                          name: u['displayName'] as String? ?? '',
                          email: u['email'] as String? ?? '',
                          photoUrl: u['photoUrl'] as String?,
                          label: l.verifiedChild,
                          onRevoke: () => _revokeConnection(
                              u['uid'] as String,
                              u['displayName'] as String? ?? ''),
                        ))
                    .toList();
              },
              loading: () => [
                const Center(
                    child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator()))
              ],
              error: (_, _) => const [],
            ),
            const Divider(),
          ],

          // ── Verified parents (only shown when at least one exists) ──
          ...parentsAsync.when(
            data: (parents) {
              if (parents.isEmpty) return const [];
              return [
                _SectionHeader(l.myParents),
                ...parents.map((u) => _RelationTile(
                      uid: u['uid'] as String,
                      name: u['displayName'] as String? ?? '',
                      email: u['email'] as String? ?? '',
                      photoUrl: u['photoUrl'] as String?,
                      label: l.verifiedParent,
                      onRevoke: null, // Kinder können Eltern nicht trennen
                    )),
              ];
            },
            loading: () => const [],
            error: (_, _) => const [],
          ),
        ],
      ),
    );
  }
}

// ─── Sub-widgets ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _IncomingClaimTile extends StatelessWidget {
  final ClaimRequest req;
  final VoidCallback onConfirm;
  final VoidCallback onReject;

  const _IncomingClaimTile({
    required this.req,
    required this.onConfirm,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.person_add_outlined)),
      title: Text(l.wantsToBeYourParent(req.fromName.isNotEmpty
          ? req.fromName
          : req.fromEmail)),
      subtitle: Text(req.fromEmail,
          style: const TextStyle(fontSize: 12)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.check_circle_outline,
                color: Colors.green),
            tooltip: l.confirmClaim,
            onPressed: onConfirm,
          ),
          IconButton(
            icon: const Icon(Icons.cancel_outlined, color: Colors.red),
            tooltip: l.rejectClaim,
            onPressed: onReject,
          ),
        ],
      ),
    );
  }
}

class _OutgoingClaimTile extends StatelessWidget {
  final ClaimRequest req;
  final VoidCallback onCancel;

  const _OutgoingClaimTile({required this.req, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListTile(
      leading: const CircleAvatar(
          child: Icon(Icons.hourglass_empty_outlined)),
      title: Text(req.toEmail),
      subtitle: Text(l.pendingApproval,
          style: const TextStyle(fontSize: 12, color: Colors.orange)),
      trailing: IconButton(
        icon: const Icon(Icons.close),
        tooltip: l.claimRequestCancelTitle,
        onPressed: onCancel,
      ),
    );
  }
}

class _RelationTile extends StatelessWidget {
  final String uid;
  final String name;
  final String email;
  final String? photoUrl;
  final String label;
  final VoidCallback? onRevoke;

  const _RelationTile({
    required this.uid,
    required this.name,
    required this.email,
    required this.photoUrl,
    required this.label,
    this.onRevoke,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final initials =
        (name.isNotEmpty ? name[0] : (email.isNotEmpty ? email[0] : '?'))
            .toUpperCase();
    return ListTile(
      leading: CircleAvatar(
        backgroundImage:
            photoUrl != null ? NetworkImage(photoUrl!) : null,
        child: photoUrl == null ? Text(initials) : null,
      ),
      title: Text(name.isNotEmpty ? name : email),
      subtitle: Text(label,
          style: const TextStyle(fontSize: 12)),
      trailing: onRevoke != null
          ? IconButton(
              icon: const Icon(Icons.link_off, color: Colors.red),
              tooltip: l.revokeConnection,
              onPressed: onRevoke,
            )
          : null,
    );
  }
}

class _ConsentTile extends StatelessWidget {
  final OrgInviteConsent consent;
  final VoidCallback onApprove;
  final VoidCallback onVeto;

  const _ConsentTile({
    required this.consent,
    required this.onApprove,
    required this.onVeto,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListTile(
      leading:
          const CircleAvatar(child: Icon(Icons.domain_outlined)),
      title: Text(l.orgInvitationForChild(consent.orgName, consent.childName)),
      subtitle: Text(
          l.orgInvitationInvitedBy(consent.invitedByName),
          style: const TextStyle(fontSize: 12)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.check_circle_outline,
                color: Colors.green),
            tooltip: l.approveOrgInvitation,
            onPressed: onApprove,
          ),
          IconButton(
            icon: const Icon(Icons.cancel_outlined, color: Colors.red),
            tooltip: l.vetoOrgInvitation,
            onPressed: onVeto,
          ),
        ],
      ),
    );
  }
}
