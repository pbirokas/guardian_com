import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:guardian_app/l10n/app_localizations.dart';
import '../../../core/appwrite_client.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/utils/launch_url.dart';
import '../../auth/providers/auth_provider.dart';
import '../../organizations/providers/organizations_provider.dart';

class PrivacyScreen extends ConsumerStatefulWidget {
  const PrivacyScreen({super.key});

  @override
  ConsumerState<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends ConsumerState<PrivacyScreen> {
  bool _showOnlineStatus = true;
  bool _showLastSeen = true;
  bool _showProfilePhoto = true;
  bool? _hideEmailOverride;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final appUser = ref.watch(currentAppUserProvider).value;
    final hideEmail = _hideEmailOverride ?? (appUser?.hideEmail ?? false);

    return Scaffold(
      appBar: AppBar(title: Text(l.privacyTitle)),
      body: ListView(
        children: [
          _SectionHeader(l.visibility),
          SwitchListTile(
            title: Text(l.showOnlineStatus),
            subtitle: Text(l.showOnlineStatusSubtitle),
            value: _showOnlineStatus,
            onChanged: (v) => setState(() => _showOnlineStatus = v),
          ),
          SwitchListTile(
            title: Text(l.showLastSeen),
            subtitle: Text(l.showLastSeenSubtitle),
            value: _showLastSeen,
            onChanged: (v) => setState(() => _showLastSeen = v),
          ),
          SwitchListTile(
            title: Text(l.showProfilePhoto),
            subtitle: Text(l.showProfilePhotoSubtitle),
            value: _showProfilePhoto,
            onChanged: (v) => setState(() => _showProfilePhoto = v),
          ),
          SwitchListTile(
            secondary: Icon(
              hideEmail ? Icons.no_accounts_outlined : Icons.alternate_email,
            ),
            title: Text(l.hideEmail),
            subtitle: Text(l.hideEmailSubtitle),
            value: hideEmail,
            onChanged: (v) async {
              setState(() => _hideEmailOverride = v);
              try {
                await ref.read(organizationServiceProvider).setHideEmail(v);
              } catch (_) {
                if (mounted) setState(() => _hideEmailOverride = !v);
              }
            },
          ),
          const Divider(),
          _SectionHeader(l.legal),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(l.privacyPolicy),
            subtitle: Text(l.openInBrowser),
            trailing: const Icon(Icons.open_in_new, size: 16),
            onTap: () => openExternalUrl(privacyPolicyUrl),
          ),
          const Divider(),
          _SectionHeader(l.data),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: Text(
              l.deleteAccount,
              style: const TextStyle(color: Colors.red),
            ),
            subtitle: Text(l.deleteAccountSubtitle),
            trailing: _deleteBusy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            onTap: () => _handleDeleteTap(context, l),
          ),
        ],
      ),
    );
  }

  bool _deleteBusy = false;

  Future<void> _handleDeleteTap(
    BuildContext context,
    AppLocalizations l,
  ) async {
    if (_deleteBusy) return;
    final auth = ref.read(authServiceProvider);
    // Vorab holen: endet die Session, kann der Router den Screen abbauen,
    // bevor der Fortschrittsdialog zurückkehrt (ref danach unbenutzbar).
    final authNotifier = ref.read(authStateProvider.notifier);

    // Eltern-Kind-Sperren sofort aus dem Live-Stand des eigenen users-Docs
    // (ohne Server-Rundlauf) …
    final me = ref.read(currentAppUserProvider).value;
    final localBlockers = [
      if (me != null && me.isChild && me.hasVerifiedParents)
        const AccountDeletionBlocker(code: 'childHasParents'),
      if (me != null && me.hasVerifiedChildren)
        const AccountDeletionBlocker(code: 'parentHasChildren'),
    ];
    if (localBlockers.isNotEmpty) {
      _showBlockedDialog(context, l, localBlockers);
      return;
    }

    // … alle Sperren (inkl. Org-Admin mit weiteren Mitgliedern) prüft der
    // Server — `start` prüft sie noch einmal.
    setState(() => _deleteBusy = true);
    List<AccountDeletionBlocker> blockers;
    try {
      blockers = await auth.checkAccountDeletion();
    } catch (e) {
      if (context.mounted) _showDeleteError(context, l, e);
      return;
    } finally {
      if (mounted) setState(() => _deleteBusy = false);
    }
    if (!context.mounted) return;

    if (blockers.isNotEmpty) {
      _showBlockedDialog(context, l, blockers);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.deleteAccount),
        content: SingleChildScrollView(
          child: Text(l.deleteAccountConfirmContent),
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
    if (confirmed != true || !context.mounted) return;

    try {
      await auth.startAccountDeletion();
    } on FunctionCallException catch (e) {
      if (!context.mounted) return;
      if (e.message == 'blocked') {
        _showSimpleDialog(
          context,
          l.deleteAccountBlockedTitle,
          l.deleteAccountBlockedRetry,
        );
      } else {
        _showDeleteError(context, l, e);
      }
      return;
    } catch (e) {
      if (context.mounted) _showDeleteError(context, l, e);
      return;
    }
    if (!context.mounted) return;

    final outcome = await showDialog<_DeletionOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _DeletionProgressDialog(),
    );
    if (outcome == _DeletionOutcome.blocked) {
      if (context.mounted) {
        _showSimpleDialog(
          context,
          l.deleteAccountBlockedTitle,
          l.deleteAccountBlockedRetry,
        );
      }
      return;
    }
    // Fertig oder läuft serverseitig weiter → abmelden (Router → /login).
    await authNotifier.signOut();
  }

  void _showBlockedDialog(
    BuildContext context,
    AppLocalizations l,
    List<AccountDeletionBlocker> blockers,
  ) {
    final codes = blockers.map((b) => b.code).toSet();
    final adminOrgs = blockers.where((b) => b.code == 'orgAdmin').toList();
    final toRelationships =
        codes.contains('childHasParents') ||
        codes.contains('parentHasChildren');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.deleteAccountBlockedTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (codes.contains('childHasParents'))
                _BlockerText(l.deleteAccountBlockedChild),
              if (codes.contains('parentHasChildren'))
                _BlockerText(l.deleteAccountBlockedParent),
              if (adminOrgs.isNotEmpty) ...[
                _BlockerText(l.deleteAccountBlockedOrgAdmin),
                for (final b in adminOrgs)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.admin_panel_settings_outlined),
                    title: Text(
                      b.orgName?.isNotEmpty == true
                          ? b.orgName!
                          : (b.orgId ?? ''),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: b.orgId == null
                        ? null
                        : () {
                            Navigator.pop(ctx);
                            context.push('/org/${b.orgId}');
                          },
                  ),
              ],
            ],
          ),
        ),
        actions: [
          if (toRelationships)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.push('/relationships');
              },
              child: Text(l.myRelationships),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.close),
          ),
        ],
      ),
    );
  }

  void _showSimpleDialog(BuildContext context, String title, String content) {
    showDialog(
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

  void _showDeleteError(BuildContext context, AppLocalizations l, Object e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.deleteAccountFailed(e.toString()))),
    );
  }
}

class _BlockerText extends StatelessWidget {
  final String text;
  const _BlockerText(this.text);

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(text));
}

enum _DeletionOutcome { done, background, blocked }

/// Wartet, bis der Server das Auth-Konto gelöscht hat (Session → 401), und
/// meldet dann Erfolg. Nach [_maxWait] läuft die Löschung serverseitig weiter
/// (Function setzt sich selbst bzw. per Schedule fort) — der Nutzer wird
/// trotzdem abgemeldet. `deletionStatus: 'blocked'` → Abbruch mit Hinweis.
class _DeletionProgressDialog extends ConsumerStatefulWidget {
  const _DeletionProgressDialog();

  @override
  ConsumerState<_DeletionProgressDialog> createState() =>
      _DeletionProgressDialogState();
}

class _DeletionProgressDialogState
    extends ConsumerState<_DeletionProgressDialog> {
  static const _pollInterval = Duration(seconds: 3);
  static const _maxWait = Duration(minutes: 3);

  Timer? _timer;
  final _started = DateTime.now();
  _DeletionOutcome? _outcome;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    if (_polling || _outcome != null) return;
    _polling = true;
    try {
      final gone = await ref.read(authServiceProvider).isAccountGone();
      if (gone) return _finish(_DeletionOutcome.done);
      if (ref.read(currentAppUserProvider).value?.deletionStatus == 'blocked') {
        return _finish(_DeletionOutcome.blocked);
      }
      if (DateTime.now().difference(_started) > _maxWait) {
        return _finish(_DeletionOutcome.background);
      }
    } catch (_) {
      // Netzfehler: beim nächsten Intervall erneut versuchen.
    } finally {
      _polling = false;
    }
  }

  void _finish(_DeletionOutcome outcome) {
    _timer?.cancel();
    if (!mounted) return;
    if (outcome == _DeletionOutcome.blocked) {
      Navigator.pop(context, outcome);
    } else {
      setState(() => _outcome = outcome);
    }
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
              ? l.deleteAccountInProgressTitle
              : l.deleteAccountDoneTitle,
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
                  Expanded(child: Text(l.deleteAccountInProgress)),
                ],
              )
            : Text(
                outcome == _DeletionOutcome.done
                    ? l.deleteAccountDone
                    : l.deleteAccountBackground,
              ),
        actions: [
          if (outcome != null)
            FilledButton(
              onPressed: () => Navigator.pop(context, outcome),
              child: Text(l.signOut),
            ),
        ],
      ),
    );
  }
}

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
          fontSize: 12,
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
