import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:guardian_app/l10n/app_localizations.dart';
import '../../../core/appwrite_client.dart' show FunctionCallException;
import '../../../core/models/app_user.dart';
import '../../../core/models/claim_request.dart';
import '../../../core/models/org_invite_consent.dart';
import '../../../core/services/parent_claim_service.dart';
import '../providers/relationships_provider.dart';
import '../../organizations/providers/organizations_provider.dart';
import '../../../core/widgets/help_sheet.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../core/utils/initials.dart';

class RelationshipsScreen extends ConsumerStatefulWidget {
  const RelationshipsScreen({super.key});

  @override
  ConsumerState<RelationshipsScreen> createState() =>
      _RelationshipsScreenState();
}

class _RelationshipsScreenState extends ConsumerState<RelationshipsScreen> {
  final _emailController = TextEditingController();
  bool _sending = false;
  int _prevPendingOutgoing = -1;

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
      // Resolve org names from already-loaded provider (no extra network call)
      final myOrgs = ref.read(myOrganizationsProvider).value ?? [];
      final orgNames = affectedMemberships
          .map((m) =>
              myOrgs.where((o) => o.id == m.orgId).firstOrNull?.name ?? m.orgId)
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
      ref.invalidate(incomingClaimRequestsProvider);
      ref.invalidate(outgoingClaimRequestsProvider);
      ref.invalidate(myParentsProvider);
      ref.invalidate(myChildrenProvider);
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
      ref.invalidate(incomingClaimRequestsProvider);
      ref.invalidate(outgoingClaimRequestsProvider);
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
      ref.invalidate(myChildrenProvider);
      ref.invalidate(myParentsProvider);
    } catch (e) {
      if (mounted) {
        final l2 = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l2.errorMessage(e.toString()))),
        );
      }
    }
  }

  /// Konto eines verifizierten Kindes löschen (`delete-account/startForChild`).
  /// Ein Elternteil reicht; weitere Eltern benachrichtigt der Server.
  Future<void> _deleteChildAccount(String childUid, String name) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.childDeleteAccountTitle(name)),
        content: SingleChildScrollView(
          child: Text(l.childDeleteAccountConfirmContent(name)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref.read(parentClaimServiceProvider).deleteChildAccount(childUid);
    } on FunctionCallException catch (e) {
      if (!mounted) return;
      if (e.message == 'blocked') {
        _showInfoDialog(
            l.deleteAccountBlockedTitle, l.childDeleteAccountBlocked(name));
      } else if (e.message == 'not_parent') {
        _showInfoDialog(
            l.deleteAccountBlockedTitle, l.childDeleteAccountNotParent);
      } else {
        _showSnack(l.deleteAccountFailed(e.toString()));
      }
      return;
    } catch (e) {
      if (mounted) _showSnack(l.deleteAccountFailed(e.toString()));
      return;
    }
    if (!mounted) return;

    // Liste neu laden → Karte zeigt „Konto wird gelöscht…“.
    ref.invalidate(myChildrenProvider);
    final outcome = await showDialog<_ChildDeletionOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _ChildDeletionProgressDialog(childUid: childUid, name: name),
    );
    if (outcome == _ChildDeletionOutcome.blocked && mounted) {
      _showInfoDialog(
          l.deleteAccountBlockedTitle, l.childDeleteAccountBlocked(name));
    }
  }

  void _showInfoDialog(String title, String content) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(ctx).close),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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

    ref.listen(outgoingClaimRequestsProvider, (_, next) {
      if (!next.hasValue) return;
      final pending = next.value!.where((r) => r.isPending).length;
      if (_prevPendingOutgoing == -1) {
        _prevPendingOutgoing = pending;
        return;
      }
      if (_prevPendingOutgoing > 0 && pending < _prevPendingOutgoing) {
        ref.invalidate(myChildrenProvider);
        ref.invalidate(myParentsProvider);
      }
      _prevPendingOutgoing = pending;
    });
    final childrenAsync = ref.watch(myChildrenProvider);
    final parentsAsync = ref.watch(myParentsProvider);
    final consentsAsync = ref.watch(pendingOrgConsentsProvider);
    final currentUser = ref.watch(currentAppUserProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.myRelationships),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: l.helpLabel,
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => HelpSheet(
                screenTitle: l.helpRelTitle,
                topics: [
                  HelpTopic(
                    icon: Icons.family_restroom_outlined,
                    title: l.helpRelOverviewTitle,
                    body: l.helpRelOverviewBody,
                  ),
                  if (currentUser?.isChild != true) ...[
                    HelpTopic(
                      icon: Icons.person_add_outlined,
                      title: l.helpRelConnectTitle,
                      body: l.helpRelConnectBody,
                    ),
                    HelpTopic(
                      icon: Icons.approval_outlined,
                      title: l.helpRelConsentsTitle,
                      body: l.helpRelConsentsBody,
                    ),
                    HelpTopic(
                      icon: Icons.link_off_outlined,
                      title: l.helpRelRevokeTitle,
                      body: l.helpRelRevokeBody,
                    ),
                  ] else ...[
                    HelpTopic(
                      icon: Icons.mark_email_read_outlined,
                      title: l.helpRelIncomingTitle,
                      body: l.helpRelIncomingBody,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(incomingClaimRequestsProvider);
          ref.invalidate(outgoingClaimRequestsProvider);
          ref.invalidate(myChildrenProvider);
          ref.invalidate(myParentsProvider);
          ref.invalidate(pendingOrgConsentsProvider);
        },
        child: ListView(
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
                    .map((u) {
                      final childUid = u['uid'] as String;
                      final childName = u['displayName'] as String? ?? '';
                      final email = u['email'] as String? ?? '';
                      final shownName =
                          childName.isNotEmpty ? childName : email;
                      // Löschung läuft (delete-account/startForChild) →
                      // keine Aktionen mehr anbieten.
                      final deleting = u['deletionStatus'] == 'deleting';
                      return _RelationTile(
                        uid: childUid,
                        name: childName,
                        email: email,
                        photoUrl: u['photoUrl'] as String?,
                        label: deleting
                            ? l.childAccountDeleting
                            : l.verifiedChild,
                        onSummary: deleting
                            ? null
                            : () => context.push(
                                  '/child-summary/$childUid',
                                  extra: childName,
                                ),
                        onRevoke: deleting
                            ? null
                            : () => _revokeConnection(childUid, childName),
                        onDeleteAccount: deleting
                            ? null
                            : () => _deleteChildAccount(childUid, shownName),
                      );
                    })
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
                      onRevoke: null,
                    )),
              ];
            },
            loading: () => const [],
            error: (_, _) => const [],
          ),
        ],
      ),
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
  final VoidCallback? onSummary;

  /// Nur bei Kindern: Konto des Kindes löschen. Dann landen „Verknüpfung
  /// aufheben“ und „Konto löschen“ gemeinsam in einem ⋮-Menü.
  final VoidCallback? onDeleteAccount;

  const _RelationTile({
    required this.uid,
    required this.name,
    required this.email,
    required this.photoUrl,
    required this.label,
    this.onRevoke,
    this.onSummary,
    this.onDeleteAccount,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final initials =
        initialsFor(name, email);
    return ListTile(
      leading: UserAvatar(photoUrl: photoUrl, fallbackText: initials),
      title: Text(name.isNotEmpty ? name : email),
      subtitle: Text(label, style: const TextStyle(fontSize: 12)),
      trailing: (onSummary == null &&
              onRevoke == null &&
              onDeleteAccount == null)
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onSummary != null)
                  IconButton(
                    icon: const Icon(Icons.bar_chart_outlined),
                    tooltip: l.summaryButtonTooltip,
                    onPressed: onSummary,
                  ),
                if (onDeleteAccount != null)
                  PopupMenuButton<VoidCallback>(
                    onSelected: (action) => action(),
                    itemBuilder: (_) => [
                      if (onRevoke != null)
                        PopupMenuItem(
                          value: onRevoke,
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.link_off),
                            title: Text(l.revokeConnection),
                          ),
                        ),
                      PopupMenuItem(
                        value: onDeleteAccount,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.delete_forever_outlined,
                              color: Colors.red),
                          title: Text(l.childDeleteAccount,
                              style: const TextStyle(color: Colors.red)),
                        ),
                      ),
                    ],
                  )
                else if (onRevoke != null)
                  IconButton(
                    icon: const Icon(Icons.link_off, color: Colors.red),
                    tooltip: l.revokeConnection,
                    onPressed: onRevoke,
                  ),
              ],
            ),
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

enum _ChildDeletionOutcome { done, background, blocked }

/// Wartet, bis das Kind aus der eigenen Kinderliste verschwindet —
/// `delete-account` löst die Verknüpfung am Ende des Laufs, das ändert das
/// eigene users-Doc (Realtime → `listRelatives` lädt neu). Zusätzlich alle
/// [_reloadInterval] neu laden (verpasstes Event, `deletionStatus: blocked`).
/// Nach [_maxWait] läuft die Löschung serverseitig weiter (Function setzt
/// sich selbst bzw. per Schedule fort).
class _ChildDeletionProgressDialog extends ConsumerStatefulWidget {
  const _ChildDeletionProgressDialog({
    required this.childUid,
    required this.name,
  });

  final String childUid;
  final String name;

  @override
  ConsumerState<_ChildDeletionProgressDialog> createState() =>
      _ChildDeletionProgressDialogState();
}

class _ChildDeletionProgressDialogState
    extends ConsumerState<_ChildDeletionProgressDialog> {
  static const _reloadInterval = Duration(seconds: 20);
  static const _maxWait = Duration(minutes: 3);

  Timer? _timer;
  final _started = DateTime.now();
  _ChildDeletionOutcome? _outcome;

  @override
  void initState() {
    super.initState();
    ref.listenManual(myChildrenProvider, (_, next) {
      // Nur fertige Ladeergebnisse auswerten, nicht den alten Stand während
      // eines Reloads.
      if (next is! AsyncData<List<Map<String, dynamic>>>) return;
      final child =
          next.value.where((c) => c['uid'] == widget.childUid).firstOrNull;
      if (child == null) {
        _finish(_ChildDeletionOutcome.done);
      } else if (child['deletionStatus'] == 'blocked') {
        _finish(_ChildDeletionOutcome.blocked);
      }
    }, fireImmediately: true);
    _timer = Timer.periodic(_reloadInterval, (_) {
      if (_outcome != null) return;
      if (DateTime.now().difference(_started) > _maxWait) {
        _finish(_ChildDeletionOutcome.background);
      } else {
        ref.invalidate(myChildrenProvider);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _finish(_ChildDeletionOutcome outcome) {
    if (_outcome != null) return;
    _outcome = outcome;
    _timer?.cancel();
    // Nicht synchron aus dem Provider-Listener heraus bauen/poppen — der
    // feuert auch in initState (fireImmediately) bzw. während eines Builds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (outcome == _ChildDeletionOutcome.blocked) {
        Navigator.pop(context, outcome);
      } else {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final outcome = _outcome;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(
          outcome == null
              ? l.childDeleteAccountInProgressTitle
              : l.childDeleteAccountDoneTitle,
        ),
        content: outcome == null
            ? Row(
                children: [
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(l.childDeleteAccountInProgress(widget.name)),
                  ),
                ],
              )
            : Text(
                outcome == _ChildDeletionOutcome.done
                    ? l.childDeleteAccountDone(widget.name)
                    : l.childDeleteAccountBackground,
              ),
        actions: [
          if (outcome != null)
            FilledButton(
              onPressed: () => Navigator.pop(context, outcome),
              child: Text(l.close),
            ),
        ],
      ),
    );
  }
}
