import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/models/app_user.dart';
import '../../../core/models/organization.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/chat/providers/chat_provider.dart';
import '../providers/organizations_provider.dart';

class OrganizationsScreen extends ConsumerWidget {
  const OrganizationsScreen({super.key});

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    final nameController = TextEditingController();
    OrgTag selectedTag = OrgTag.sonstiges;
    ChatMode selectedMode = ChatMode.guardian;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Organisation erstellen'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Name der Organisation',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                const Text('Kategorie',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
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
                const Text('Chat-Modus',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
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
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Erstellen'),
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
            SnackBar(content: Text('Fehler: $e')),
          );
        }
      }
    }
  }

  void _showProfileMenu(BuildContext context, WidgetRef ref, User user) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
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
            Text(
              user.displayName ?? '',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              user.email ?? '',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const Divider(height: 32),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Profil bearbeiten'),
              onTap: () {
                Navigator.pop(context);
                context.push('/profile');
              },
            ),
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('Benachrichtigungen'),
              onTap: () {
                Navigator.pop(context);
                context.push('/settings/notifications');
              },
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Datenschutz'),
              onTap: () {
                Navigator.pop(context);
                context.push('/settings/privacy');
              },
            ),
            const Divider(height: 8),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Abmelden',
                  style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                ref.read(authServiceProvider).signOut();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orgsAsync = ref.watch(myOrganizationsProvider);
    final user = FirebaseAuth.instance.currentUser;
    final currentAppUser = ref.watch(currentAppUserProvider).valueOrNull;
    // Kinder dürfen keine Organisationen erstellen
    final isChildInAnyOrg = currentAppUser?.memberships
            .any((m) => m.role == OrgRole.child) ??
        false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meine Organisationen'),
        actions: [
          if (user != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => _showProfileMenu(context, ref, user),
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
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (orgs) {
          if (orgs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.groups_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('Noch keine Organisationen',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: orgs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final org = orgs[i];
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
                        Text('Archiviert',
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
                                  title: const Text('Organisation löschen?'),
                                  content: Text(
                                      '"${org.name}" und alle Mitgliedschaften werden unwiderruflich gelöscht.'),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: const Text('Abbrechen'),
                                    ),
                                    FilledButton(
                                      style: FilledButton.styleFrom(
                                          backgroundColor: Colors.red),
                                      onPressed: () =>
                                          Navigator.pop(ctx, true),
                                      child: const Text('Löschen'),
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
                            const PopupMenuItem(
                                value: 'open',
                                child: ListTile(
                                    leading: Icon(Icons.open_in_new),
                                    title: Text('Öffnen'),
                                    contentPadding: EdgeInsets.zero)),
                            if (!org.isArchived)
                              const PopupMenuItem(
                                  value: 'archive',
                                  child: ListTile(
                                      leading: Icon(Icons.archive_outlined),
                                      title: Text('Archivieren'),
                                      contentPadding: EdgeInsets.zero)),
                            if (org.isArchived)
                              const PopupMenuItem(
                                  value: 'unarchive',
                                  child: ListTile(
                                      leading: Icon(Icons.unarchive_outlined),
                                      title: Text('Wiederherstellen'),
                                      contentPadding: EdgeInsets.zero)),
                            const PopupMenuItem(
                                value: 'delete',
                                child: ListTile(
                                    leading: Icon(Icons.delete_outline,
                                        color: Colors.red),
                                    title: Text('Löschen',
                                        style:
                                            TextStyle(color: Colors.red)),
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
          );
        },
      ),
      floatingActionButton: isChildInAnyOrg
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showCreateDialog(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Organisation erstellen'),
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
