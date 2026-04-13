import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:guardian_app/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';
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

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

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
          const Divider(),
          _SectionHeader(l.legal),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(l.privacyPolicy),
            subtitle: Text(l.openInBrowser),
            trailing: const Icon(Icons.open_in_new, size: 16),
            onTap: () => launchUrl(
              Uri.parse('https://pbirokas.github.io/guardian_com/privacy_policy.html'),
              mode: LaunchMode.externalApplication,
            ),
          ),
          const Divider(),
          _SectionHeader(l.data),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: Text(l.deleteAccount,
                style: const TextStyle(color: Colors.red)),
            subtitle: Text(l.deleteAccountSubtitle),
            onTap: () => _handleDeleteTap(context, l),
          ),
        ],
      ),
    );
  }

  void _handleDeleteTap(BuildContext context, AppLocalizations l) {
    final currentUser = ref.read(currentAppUserProvider).value;

    // Block if the user is a child with verified parents
    if (currentUser?.isChild == true &&
        (currentUser?.verifiedParentUids.isNotEmpty ?? false)) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.deleteAccountBlockedTitle),
          content: Text(l.deleteAccountBlockedChild),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.push('/relationships');
              },
              child: Text(l.myRelationships),
            ),
          ],
        ),
      );
      return;
    }

    // Block if the user is a parent with verified children
    if (currentUser?.verifiedChildUids.isNotEmpty ?? false) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.deleteAccountBlockedTitle),
          content: Text(l.deleteAccountBlockedParent),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.push('/relationships');
              },
              child: Text(l.myRelationships),
            ),
          ],
        ),
      );
      return;
    }

    // No active connections — show normal confirmation dialog
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.deleteAccount),
        content: Text(l.deleteAccountConfirmContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.delete),
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
      child: Text(title,
          style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold)),
    );
  }
}
