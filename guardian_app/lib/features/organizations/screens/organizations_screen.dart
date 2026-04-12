import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:guardian_app/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/models/organization.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/chat/providers/chat_provider.dart';
import '../../../features/relationships/providers/relationships_provider.dart';
import '../../../features/relationships/widgets/family_tree_sheet.dart';
import '../providers/organizations_provider.dart';

const _kGithubUrl = 'https://github.com/pbirokas/guardian_com';

class OrganizationsScreen extends ConsumerStatefulWidget {
  const OrganizationsScreen({super.key});

  @override
  ConsumerState<OrganizationsScreen> createState() =>
      _OrganizationsScreenState();
}

class _OrganizationsScreenState extends ConsumerState<OrganizationsScreen> {
  bool _showArchived = false;
  bool _donationCheckDone = false;

  static const _kLastDonationShown = 'lastDonationShownAt';
  static const _kDonationIntervalDays = 7;

  Future<void> _maybeShowDonationDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final lastShown = prefs.getInt(_kLastDonationShown);
    final now = DateTime.now().millisecondsSinceEpoch;
    final intervalMs = const Duration(days: _kDonationIntervalDays).inMilliseconds;

    if (lastShown == null || now - lastShown >= intervalMs) {
      if (!mounted) return;
      await _showDonationDialog();
      await prefs.setInt(_kLastDonationShown, now);
    }
  }

  Future<void> _showDonationDialog() async {
    final l = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.donationTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.donationContent, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 20),
            _DonationButton(
              icon: Icons.coffee_outlined,
              label: l.kofiButton,
              color: const Color(0xFF29ABE0),
              url: 'https://ko-fi.com/pantelisbirokas',
            ),
            const SizedBox(height: 10),
            _DonationButton(
              icon: Icons.payment_outlined,
              label: l.paypalButton,
              color: const Color(0xFF003087),
              url: 'https://paypal.me/pantirokas',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.maybeLater),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final nameController = TextEditingController();
    OrgTag selectedTag = OrgTag.sonstiges;
    ChatMode selectedMode = ChatMode.guardian;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(l.createOrganization),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  maxLength: 40,
                  decoration: InputDecoration(
                    labelText: l.orgNameLabel,
                    border: const OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                Text(l.category,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: OrgTag.values.map((tag) {
                    final selected = selectedTag == tag;
                    return FilterChip(
                      avatar: Icon(tag.icon,
                          size: 16,
                          color: selected ? Colors.white : tag.color),
                      label: Text(tag.label),
                      selected: selected,
                      selectedColor: tag.color,
                      labelStyle:
                          TextStyle(color: selected ? Colors.white : null),
                      onSelected: (_) => setState(() => selectedTag = tag),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Text(l.chatMode,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 8),
                ...ChatMode.values.map((mode) => _ChatModeOption(
                      mode: mode,
                      selected: selectedMode == mode,
                      onTap: () => setState(() => selectedMode = mode),
                    )),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.create),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && nameController.text.trim().isNotEmpty) {
      try {
        await ref
            .read(organizationServiceProvider)
            .createOrganization(
                nameController.text.trim(), selectedTag, selectedMode);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.errorMessage(e.toString()))),
          );
        }
      }
    }
  }

  void _showAboutAppDialog(BuildContext context, PackageInfo? info) {
    final l = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.shield_outlined,
                size: 28, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Text(l.aboutAppDialogTitle),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (info != null)
              Text(
                'v${info.version} (Build ${info.buildNumber})',
                style: TextStyle(
                    fontSize: 13, color: Colors.grey[600]),
              ),
            const SizedBox(height: 12),
            Text(l.aboutAppDescription),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.code),
                label: Text(l.githubRepository),
                onPressed: () async {
                  final uri = Uri.parse(_kGithubUrl);
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (mounted) showLicensePage(context: context);
            },
            child: Text(l.openSourceLicenses),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.close),
          ),
        ],
      ),
    );
  }

  void _showProfileMenu(BuildContext context, User user) {
    final l = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            CircleAvatar(
              radius: 32,
              backgroundImage: user.photoURL != null
                  ? NetworkImage(user.photoURL!)
                  : null,
              child: user.photoURL == null
                  ? Text(
                      ((user.displayName?.isNotEmpty == true ? user.displayName : user.email?.isNotEmpty == true ? user.email : '?')!)[0].toUpperCase(),
                      style: const TextStyle(fontSize: 24),
                    )
                  : null,
            ),
            const SizedBox(height: 8),
            Text(user.displayName ?? '',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text(user.email ?? '',
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
            const Divider(height: 32),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(l.editProfile),
              onTap: () { Navigator.pop(context); context.push('/profile'); },
            ),
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: Text(l.notificationsTitle),
              onTap: () { Navigator.pop(context); context.push('/settings/notifications'); },
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: Text(l.privacyTitle),
              onTap: () { Navigator.pop(context); context.push('/settings/privacy'); },
            ),
            const Divider(height: 8),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: Text(l.signOut, style: const TextStyle(color: Colors.red)),
              onTap: () { Navigator.pop(context); ref.read(authServiceProvider).signOut(); },
            ),
            const SizedBox(height: 8),
          ],
        ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final orgsAsync = ref.watch(myOrganizationsProvider);
    final user = FirebaseAuth.instance.currentUser;
    final currentAppUserAsync = ref.watch(currentAppUserProvider);
    // Kinder dürfen keine Organisationen erstellen.
    // Während der Provider lädt, FAB verstecken (verhindert Race Condition
    // zwischen Auth-Event und abgeschlossener Einladungsverarbeitung).
    final isChildInAnyOrg = currentAppUserAsync.when(
      loading: () => true,
      error: (_, _) => false,
      data: (u) => u?.isChild ?? false,
    );

    // Spenden-Popup: einmal pro Woche, nicht für Kinder
    if (!_donationCheckDone) {
      currentAppUserAsync.whenData((u) {
        if (u?.isChild != true) {
          _donationCheckDone = true;
          WidgetsBinding.instance.addPostFrameCallback(
              (_) => _maybeShowDonationDialog());
        } else {
          _donationCheckDone = true; // Kinder: nie zeigen
        }
      });
    }

    // Badge-Zähler für ausstehende Eltern-Kind-Aktionen
    final incomingClaims = ref.watch(incomingClaimRequestsProvider)
        .whenData((list) => list.where((r) => r.isPending).length)
        .value ?? 0;
    final pendingConsents = ref.watch(pendingOrgConsentsProvider)
        .whenData((list) => list.length)
        .value ?? 0;
    final familyBadgeCount = incomingClaims + pendingConsents;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.myOrganizations),
        actions: [
          // Baum-Icon: Familienübersicht
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: IconButton(
              tooltip: l.familyTreeTooltip,
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                shape: const RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(16)),
                ),
                builder: (_) => const FamilyTreeSheet(),
              ),
              icon: Badge(
                isLabelVisible: familyBadgeCount > 0,
                label: Text('$familyBadgeCount'),
                child: const Icon(Icons.park_outlined),
              ),
            ),
          ),
          if (user != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => _showProfileMenu(context, user),
                child: CircleAvatar(
                  radius: 18,
                  backgroundImage: user.photoURL != null
                      ? NetworkImage(user.photoURL!)
                      : null,
                  child: user.photoURL == null
                      ? Text(
                          ((user.displayName?.isNotEmpty == true
                                  ? user.displayName!
                                  : user.email?.isNotEmpty == true
                                      ? user.email!
                                      : '?')[0])
                              .toUpperCase(),
                        )
                      : null,
                ),
              ),
            ),
        ],
      ),
      body: orgsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l.errorMessage(e.toString()))),
        data: (orgs) {
          final hasArchived = orgs.any((o) => o.isArchived);
          final visibleOrgs = _showArchived
              ? orgs
              : orgs.where((o) => !o.isArchived).toList();
          final hiddenCount = orgs.length - visibleOrgs.length;

          if (visibleOrgs.isEmpty && !hasArchived) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.groups_outlined, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(l.noOrganizations,
                      style: const TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }
          return Column(
            children: [
              if (hasArchived)
                InkWell(
                  onTap: () => setState(() => _showArchived = !_showArchived),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        Icon(
                          _showArchived
                              ? Icons.visibility_off_outlined
                              : Icons.archive_outlined,
                          size: 16,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _showArchived
                              ? l.hideArchived
                              : l.showArchived(hiddenCount),
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                ),
              // LayoutBuilder reads the actual available size so we can clamp
              // the list to max 640 px without overflow on small windows.
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final listWidth =
                        constraints.maxWidth.clamp(0.0, 640.0);
                    return Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: listWidth,
                        height: constraints.maxHeight,
                        child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: visibleOrgs.length,
                  separatorBuilder: (_, idx) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
              final org = visibleOrgs[i];
              final currentUid = FirebaseAuth.instance.currentUser!.uid;
              final isOrgAdmin = org.adminUid == currentUid;
              final unreadCount = ref.watch(unreadOrgCountProvider(org.id));
              return Card(
                color: org.isArchived ? Colors.grey[100] : null,
                child: ListTile(
                  leading: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CircleAvatar(
                        backgroundColor: org.isArchived
                            ? Colors.grey[300]
                            : org.tag.color.withAlpha(30),
                        child: Icon(
                          org.isArchived ? Icons.archive_outlined : org.tag.icon,
                          color: org.isArchived ? Colors.grey : org.tag.color,
                        ),
                      ),
                      if (unreadCount > 0)
                        Positioned(
                          top: -4,
                          right: -4,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '$unreadCount',
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                    ],
                  ),
                  title: Text(org.name,
                      style: org.isArchived
                          ? TextStyle(color: Colors.grey[500])
                          : null),
                  subtitle: Row(
                    children: [
                      if (org.isArchived)
                        Text(l.archivedBadge,
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[500]))
                      else ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: org.tag.color.withAlpha(30),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(org.tag.label,
                              style: TextStyle(
                                  fontSize: 11, color: org.tag.color)),
                        ),
                        const SizedBox(width: 6),
                        Icon(org.chatMode.icon,
                            size: 13, color: Colors.grey[600]),
                        const SizedBox(width: 3),
                        Text(org.chatMode.label,
                            style:
                                TextStyle(fontSize: 11, color: Colors.grey[600])),
                      ],
                    ],
                  ),
                  trailing: isOrgAdmin
                      ? PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert),
                          onSelected: (value) async {
                            final svc = ref
                                .read(organizationServiceProvider);
                            if (value == 'archive') {
                              await svc.archiveOrganization(org.id);
                            } else if (value == 'unarchive') {
                              await svc.unarchiveOrganization(org.id);
                            } else if (value == 'delete') {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: Text(l.deleteOrgTitle),
                                  content: Text(l.deleteOrgContent(org.name)),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: Text(l.cancel),
                                    ),
                                    FilledButton(
                                      style: FilledButton.styleFrom(
                                          backgroundColor: Colors.red),
                                      onPressed: () =>
                                          Navigator.pop(ctx, true),
                                      child: Text(l.delete),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true) {
                                await svc.deleteOrganization(org.id);
                              }
                            } else if (value == 'open') {
                              if (context.mounted) {
                                context.push('/org/${org.id}');
                              }
                            }
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(
                                value: 'open',
                                child: ListTile(
                                    leading: const Icon(Icons.open_in_new),
                                    title: Text(l.open),
                                    contentPadding: EdgeInsets.zero)),
                            if (!org.isArchived)
                              PopupMenuItem(
                                  value: 'archive',
                                  child: ListTile(
                                      leading: const Icon(Icons.archive_outlined),
                                      title: Text(l.archive),
                                      contentPadding: EdgeInsets.zero)),
                            if (org.isArchived)
                              PopupMenuItem(
                                  value: 'unarchive',
                                  child: ListTile(
                                      leading: const Icon(Icons.unarchive_outlined),
                                      title: Text(l.unarchive),
                                      contentPadding: EdgeInsets.zero)),
                            PopupMenuItem(
                                value: 'delete',
                                child: ListTile(
                                    leading: const Icon(Icons.delete_outline,
                                        color: Colors.red),
                                    title: Text(l.delete,
                                        style: const TextStyle(color: Colors.red)),
                                    contentPadding: EdgeInsets.zero)),
                          ],
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: org.isArchived
                      ? null
                      : () => context.push('/org/${org.id}'),
                ),
              );
            },
          ),            // closes ListView.separated
        ),            // closes SizedBox
      );              // closes Align (return)
    },                // closes LayoutBuilder builder
  ),                  // closes LayoutBuilder
),                    // closes Expanded
],                    // closes Column children
);                    // closes Column
        },            // closes data:
      ),              // closes orgsAsync.when(
      floatingActionButton: FutureBuilder<PackageInfo>(
        future: PackageInfo.fromPlatform(),
        builder: (context, snap) {
          final info = snap.data;
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FloatingActionButton.extended(
                heroTag: 'about',
                onPressed: () => _showAboutAppDialog(context, info),
                backgroundColor:
                    Theme.of(context).colorScheme.secondaryContainer,
                foregroundColor:
                    Theme.of(context).colorScheme.onSecondaryContainer,
                icon: const Icon(Icons.info_outline),
                label: Text(l.aboutApp),
              ),
              if (!isChildInAnyOrg) ...[
                const SizedBox(width: 12),
                FloatingActionButton.extended(
                  heroTag: 'create',
                  onPressed: () => _showCreateDialog(context),
                  icon: const Icon(Icons.add),
                  label: Text(l.createOrganization),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ChatModeOption extends StatelessWidget {
  final ChatMode mode;
  final bool selected;
  final VoidCallback onTap;

  const _ChatModeOption({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? color : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: selected ? color.withAlpha(15) : null,
        ),
        child: Row(
          children: [
            Icon(mode.icon,
                color: selected ? color : Colors.grey, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(mode.label,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: selected ? color : null)),
                  const SizedBox(height: 2),
                  Text(mode.description,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle, color: color, size: 20),
          ],
        ),
      ),
    );
  }
}

class _DonationButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final String url;

  const _DonationButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.url,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
        ),
        icon: Icon(icon),
        label: Text(label),
        onPressed: () async {
          final uri = Uri.parse(url);
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        },
      ),
    );
  }
}
