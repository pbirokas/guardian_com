import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/models/app_user.dart';
import '../../../core/models/conversation.dart';
import '../../../core/models/org_member.dart';
import '../../../core/models/organization.dart';
import '../../chat/providers/chat_provider.dart';
import '../providers/organizations_provider.dart';

class OrganizationDetailScreen extends ConsumerWidget {
  final String orgId;

  const OrganizationDetailScreen({super.key, required this.orgId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orgAsync = ref.watch(organizationProvider(orgId));
    final currentUid = FirebaseAuth.instance.currentUser!.uid;

    return orgAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Fehler: $e'))),
      data: (org) {
        final isAdmin = org.adminUid == currentUid;
        final isModerator = !isAdmin;

        return DefaultTabController(
          length: 2,
          initialIndex: 1,
          child: Scaffold(
            appBar: AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(org.name),
                  Row(
                    children: [
                      Icon(org.tag.icon, size: 12, color: org.tag.color),
                      const SizedBox(width: 4),
                      Text(org.tag.label,
                          style:
                              TextStyle(fontSize: 12, color: org.tag.color)),
                      const SizedBox(width: 8),
                      Icon(org.chatMode.icon, size: 12, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(org.chatMode.label,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ],
              ),
              actions: [
                if (isAdmin)
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Bearbeiten',
                    onPressed: () => _showEditDialog(context, ref, org),
                  ),
              ],
              bottom: TabBar(
                tabs: [
                  const Tab(icon: Icon(Icons.people_outline), text: 'Mitglieder'),
                  Tab(
                    child: _ChatTabLabel(orgId: orgId, isAdminOrMod: isAdmin || isModerator),
                  ),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                _MembersTab(org: org, isAdmin: isAdmin, ref: ref),
                _ChatsTab(org: org, currentUid: currentUid, isAdmin: isAdmin),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showEditDialog(
      BuildContext context, WidgetRef ref, Organization org) async {
    final nameController = TextEditingController(text: org.name);
    OrgTag selectedTag = org.tag;
    ChatMode selectedMode = org.chatMode;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Organisation bearbeiten'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Name',
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
                ...ChatMode.values.map((mode) {
                  final selected = selectedMode == mode;
                  final color = Theme.of(ctx).colorScheme.primary;
                  return GestureDetector(
                    onTap: () => setState(() => selectedMode = mode),
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
                              color: selected ? color : Colors.grey,
                              size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(mode.label,
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: selected ? color : null,
                                        fontSize: 13)),
                                Text(mode.description,
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.grey)),
                              ],
                            ),
                          ),
                          if (selected)
                            Icon(Icons.check_circle, color: color, size: 18),
                        ],
                      ),
                    ),
                  );
                }),
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
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && nameController.text.trim().isNotEmpty) {
      try {
        await ref.read(organizationServiceProvider).updateOrganization(
              orgId,
              name: nameController.text.trim(),
              tag: selectedTag,
              chatMode: selectedMode,
            );
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fehler: $e')),
          );
        }
      }
    }
  }
}

// ── Chats Tab ────────────────────────────────────────────────────────────────

class _ChatsTab extends ConsumerWidget {
  final Organization org;
  final String currentUid;
  final bool isAdmin;

  const _ChatsTab({
    required this.org,
    required this.currentUid,
    required this.isAdmin,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final convsAsync = isAdmin
        ? ref.watch(adminConversationsProvider(org.id))
        : ref.watch(orgConversationsProvider(org.id));
    final pendingAsync = ref.watch(pendingRequestsProvider(org.id));
    final membersAsync = ref.watch(orgMembersProvider(org.id));

    return convsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (convs) {
        final approved =
            convs.where((c) => c.status == ConversationStatus.approved).toList();

        return Stack(
          children: [
            CustomScrollView(
              slivers: [
                // Ausstehende Anfragen (nur für Admin/Mod sichtbar)
                if (isAdmin)
                  pendingAsync.when(
                    loading: () => const SliverToBoxAdapter(child: SizedBox()),
                    error: (_, _) => const SliverToBoxAdapter(child: SizedBox()),
                    data: (pending) {
                      if (pending.isEmpty) {
                        return const SliverToBoxAdapter(child: SizedBox());
                      }
                      return SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                              child: Text(
                                'Ausstehende Anfragen (${pending.length})',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            ...pending.map((conv) => membersAsync.maybeWhen(
                                  data: (members) => _PendingRequestTile(
                                    conv: conv,
                                    members: members,
                                    currentUid: currentUid,
                                    onApprove: () => ref
                                        .read(chatServiceProvider)
                                        .approveConversation(conv.id),
                                    onReject: () => ref
                                        .read(chatServiceProvider)
                                        .rejectConversation(conv.id),
                                  ),
                                  orElse: () => const SizedBox(),
                                )),
                            const Divider(),
                          ],
                        ),
                      );
                    },
                  )
                else
                  const SliverToBoxAdapter(child: SizedBox()),

                // Genehmigte Chats
                if (approved.isEmpty)
                  SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_bubble_outline,
                              size: 56, color: Colors.grey[400]),
                          const SizedBox(height: 12),
                          Text(
                            org.chatMode == ChatMode.guardian
                                ? 'Noch keine Chats.\nStelle eine Anfrage um zu starten.'
                                : 'Noch keine Chats.\nDer Admin legt Verbindungen fest.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => membersAsync.maybeWhen(
                        data: (members) => _ConversationTile(
                          conv: approved[i],
                          members: members,
                          currentUid: currentUid,
                        ),
                        orElse: () => const SizedBox(),
                      ),
                      childCount: approved.length,
                    ),
                  ),
              ],
            ),
            // FAB für Admin im Sheltered-Modus: Gruppe erstellen
            if (isAdmin && org.chatMode == ChatMode.sheltered)
              Positioned(
                bottom: 16,
                right: 16,
                child: membersAsync.maybeWhen(
                  data: (members) => FloatingActionButton.extended(
                    heroTag: 'create_group',
                    onPressed: () => _showCreateGroupDialog(context, ref, org, members),
                    icon: const Icon(Icons.group_add_outlined),
                    label: const Text('Gruppe erstellen'),
                  ),
                  orElse: () => const SizedBox(),
                ),
              ),
          ],
        );
      },
    );
  }
}

Future<void> _showCreateGroupDialog(BuildContext context, WidgetRef ref,
    Organization org, List<OrgMember> members) async {
  final nameController = TextEditingController();
  final nonAdmins = members.where((m) => m.uid != org.adminUid).toList();
  final selected = <String>{};

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Gruppe erstellen'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Gruppenname',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),
              const Text('Mitglieder hinzufügen',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 8),
              ...nonAdmins.map((m) => CheckboxListTile(
                    value: selected.contains(m.uid),
                    onChanged: (v) => setState(() =>
                        v == true ? selected.add(m.uid) : selected.remove(m.uid)),
                    title: Text(m.displayName),
                    subtitle: Text(m.email,
                        style: const TextStyle(fontSize: 12)),
                    secondary: CircleAvatar(
                      radius: 16,
                      backgroundImage: m.photoUrl != null
                          ? NetworkImage(m.photoUrl!)
                          : null,
                      child: m.photoUrl == null
                          ? Text(m.displayName[0].toUpperCase())
                          : null,
                    ),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
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
            onPressed: selected.isEmpty || nameController.text.trim().isEmpty
                ? null
                : () => Navigator.pop(ctx, true),
            child: const Text('Erstellen'),
          ),
        ],
      ),
    ),
  );

  if (confirmed == true) {
    try {
      await ref.read(chatServiceProvider).createGroupChat(
            org.id,
            nameController.text.trim(),
            selected.toList(),
          );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e')),
        );
      }
    }
  }
  nameController.dispose();
}

// ── FAB-ähnliche Anfrage-Schaltfläche ────────────────────────────────────────

class _ChatTabLabel extends ConsumerWidget {
  final String orgId;
  final bool isAdminOrMod;

  const _ChatTabLabel({required this.orgId, required this.isAdminOrMod});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isAdminOrMod) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(Icons.chat_outlined), Text('Chats', style: TextStyle(fontSize: 10))],
      );
    }

    final pendingAsync = ref.watch(pendingRequestsProvider(orgId));
    final count = pendingAsync.valueOrNull?.length ?? 0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_outlined),
            Text('Chats', style: TextStyle(fontSize: 10)),
          ],
        ),
        if (count > 0)
          Positioned(
            top: -4,
            right: -10,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              child: Text('$count',
                  style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.bold)),
            ),
          ),
      ],
    );
  }
}

// ── Mitglieder Tab ───────────────────────────────────────────────────────────

class _MembersTab extends ConsumerWidget {
  final Organization org;
  final bool isAdmin;
  final WidgetRef ref;

  const _MembersTab(
      {required this.org, required this.isAdmin, required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef widgetRef) {
    final membersAsync = widgetRef.watch(orgMembersProvider(org.id));

    return membersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (members) => Stack(
        children: [
          members.isEmpty
              ? const Center(
                  child: Text('Noch keine Mitglieder',
                      style: TextStyle(color: Colors.grey)))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                  itemCount: members.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => _MemberTile(
                    member: members[i],
                    org: org,
                    isAdmin: isAdmin,
                    ref: widgetRef,
                  ),
                ),
          if (isAdmin)
            Positioned(
              bottom: 16,
              right: 16,
              child: FloatingActionButton.extended(
                heroTag: 'invite',
                onPressed: () =>
                    _showInviteDialog(context, widgetRef),
                icon: const Icon(Icons.person_add_outlined),
                label: const Text('Mitglied einladen'),
              ),
            ),
          if (org.chatMode == ChatMode.guardian && !isAdmin)
            Positioned(
              bottom: 16,
              right: 16,
              child: FloatingActionButton.extended(
                heroTag: 'chat_request',
                onPressed: () =>
                    _showChatRequestDialog(context, widgetRef, members),
                icon: const Icon(Icons.chat_outlined),
                label: const Text('Chat anfragen'),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showInviteDialog(BuildContext context, WidgetRef ref) async {
    final emailController = TextEditingController();
    OrgRole selectedRole = OrgRole.member;

    final roleLabels = {
      OrgRole.moderator: 'Moderator',
      OrgRole.member: 'Mitglied',
      OrgRole.child: 'Kind',
    };

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Mitglied einladen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailController,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'E-Mail-Adresse',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 16),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Rolle',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
              const SizedBox(height: 8),
              SegmentedButton<OrgRole>(
                segments: roleLabels.entries
                    .map((e) => ButtonSegment(
                          value: e.key,
                          label: Text(e.value),
                        ))
                    .toList(),
                selected: {selectedRole},
                onSelectionChanged: (s) =>
                    setState(() => selectedRole = s.first),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Einladen'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && emailController.text.trim().isNotEmpty) {
      try {
        await ref.read(organizationServiceProvider).inviteMember(
              org.id,
              emailController.text.trim(),
              selectedRole,
            );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Mitglied erfolgreich eingeladen.')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fehler: $e')),
          );
        }
      }
    }
  }

  Future<void> _showChatRequestDialog(
      BuildContext context, WidgetRef ref, List<OrgMember> members) async {
    final currentUid = FirebaseAuth.instance.currentUser!.uid;
    final others = members.where((m) => m.uid != currentUid).toList();
    if (others.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keine anderen Mitglieder vorhanden.')),
      );
      return;
    }

    OrgMember? selected = others.first;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Chat anfragen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Mit wem möchtest du chatten?',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 12),
              ...others.map((m) {
                final isSelected = selected == m;
                return InkWell(
                  onTap: () => setState(() => selected = m),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundImage: m.photoUrl != null ? NetworkImage(m.photoUrl!) : null,
                          child: m.photoUrl == null ? Text(m.displayName[0].toUpperCase()) : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m.displayName, style: const TextStyle(fontWeight: FontWeight.w500)),
                              Text(m.email, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                        ),
                        if (isSelected) const Icon(Icons.check_circle, color: Colors.blue),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 16, color: Colors.blue),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Deine Anfrage wird von einem Admin oder Moderator geprüft.',
                        style: TextStyle(fontSize: 12, color: Colors.blue),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Anfragen'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && selected != null) {
      try {
        await ref
            .read(chatServiceProvider)
            .requestConversation(org.id, selected!.uid);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Chat-Anfrage wurde gesendet.')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fehler: $e')),
          );
        }
      }
    }
  }
}

// ── Conversation Tile ────────────────────────────────────────────────────────

class _ConversationTile extends StatelessWidget {
  final Conversation conv;
  final List<OrgMember> members;
  final String currentUid;

  const _ConversationTile({
    required this.conv,
    required this.members,
    required this.currentUid,
  });

  @override
  Widget build(BuildContext context) {
    final String title;
    final Widget avatar;

    if (conv.isGroup) {
      title = conv.name ?? 'Gruppe';
      avatar = CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
        child: Icon(Icons.group,
            color: Theme.of(context).colorScheme.onSecondaryContainer),
      );
    } else {
      final otherUid = conv.participantUids.firstWhere(
          (uid) => uid != currentUid,
          orElse: () => '');
      final other = members.where((m) => m.uid == otherUid).firstOrNull;
      title = other?.displayName ?? 'Unbekannt';
      final photoUrl = other?.photoUrl;
      avatar = CircleAvatar(
        backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
        child: photoUrl == null ? Text(title[0].toUpperCase()) : null,
      );
    }

    return ListTile(
      leading: avatar,
      title: Text(title),
      subtitle: conv.lastMessage != null
          ? Text(conv.lastMessage!,
              maxLines: 1, overflow: TextOverflow.ellipsis)
          : const Text('Noch keine Nachrichten',
              style: TextStyle(color: Colors.grey)),
      trailing: conv.lastMessageAt != null
          ? Text(
              _formatTime(conv.lastMessageAt!),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            )
          : null,
      onTap: () => context.push('/chat/${conv.id}', extra: title),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    if (dt.day == now.day) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.day}.${dt.month}.';
  }
}

// ── Pending Request Tile ─────────────────────────────────────────────────────

class _PendingRequestTile extends StatelessWidget {
  final Conversation conv;
  final List<OrgMember> members;
  final String currentUid;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _PendingRequestTile({
    required this.conv,
    required this.members,
    required this.currentUid,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final requester =
        members.where((m) => m.uid == conv.requestedBy).firstOrNull;
    final other = members
        .where((m) =>
            m.uid != conv.requestedBy &&
            conv.participantUids.contains(m.uid))
        .firstOrNull;

    return ListTile(
      leading: const CircleAvatar(
        backgroundColor: Colors.orange,
        child: Icon(Icons.chat_outlined, color: Colors.white, size: 18),
      ),
      title: Text(
          '${requester?.displayName ?? '?'} → ${other?.displayName ?? '?'}'),
      subtitle: const Text('Wartet auf Genehmigung'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.check_circle_outline, color: Colors.green),
            tooltip: 'Genehmigen',
            onPressed: onApprove,
          ),
          IconButton(
            icon: const Icon(Icons.cancel_outlined, color: Colors.red),
            tooltip: 'Ablehnen',
            onPressed: onReject,
          ),
        ],
      ),
    );
  }
}

// ── Member Tile ──────────────────────────────────────────────────────────────

class _MemberTile extends StatelessWidget {
  final OrgMember member;
  final Organization org;
  final bool isAdmin;
  final WidgetRef ref;

  const _MemberTile({
    required this.member,
    required this.org,
    required this.isAdmin,
    required this.ref,
  });

  String _roleLabel(OrgRole role) => switch (role) {
        OrgRole.admin => 'Admin',
        OrgRole.moderator => 'Moderator',
        OrgRole.member => 'Mitglied',
        OrgRole.child => 'Kind',
      };

  Color _roleColor(OrgRole role) => switch (role) {
        OrgRole.admin => Colors.red,
        OrgRole.moderator => Colors.orange,
        OrgRole.member => Colors.blue,
        OrgRole.child => Colors.green,
      };

  void _showMemberOptions(BuildContext context) {
    if (!isAdmin || member.role == OrgRole.admin) return;
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.chat_outlined),
              title: const Text('Chat starten'),
              onTap: () {
                Navigator.pop(context);
                _startAdminChat(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Rolle ändern'),
              onTap: () {
                Navigator.pop(context);
                _showRoleDialog(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_remove_outlined,
                  color: Colors.red),
              title: const Text('Entfernen',
                  style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _confirmRemove(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startAdminChat(BuildContext context) async {
    try {
      final conv = await ref
          .read(chatServiceProvider)
          .createApprovedConversation(org.id, member.uid);
      if (context.mounted) {
        context.push('/chat/${conv.id}', extra: member.displayName);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e')),
        );
      }
    }
  }

  Future<void> _showRoleDialog(BuildContext context) async {
    OrgRole selected = member.role;
    final roleLabels = {
      OrgRole.moderator: 'Moderator',
      OrgRole.member: 'Mitglied',
      OrgRole.child: 'Kind',
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('Rolle für ${member.displayName}'),
          content: SegmentedButton<OrgRole>(
            segments: roleLabels.entries
                .map((e) =>
                    ButtonSegment(value: e.key, label: Text(e.value)))
                .toList(),
            selected: {selected},
            onSelectionChanged: (s) => setState(() => selected = s.first),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && selected != member.role) {
      await ref
          .read(organizationServiceProvider)
          .updateMemberRole(org.id, member.uid, selected);
    }
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mitglied entfernen'),
        content: Text('${member.displayName} wirklich entfernen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Entfernen'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref
          .read(organizationServiceProvider)
          .removeMember(org.id, member.uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundImage: member.photoUrl != null
            ? NetworkImage(member.photoUrl!)
            : null,
        child: member.photoUrl == null
            ? Text(member.displayName[0].toUpperCase())
            : null,
      ),
      title: Text(member.displayName),
      subtitle:
          Text(member.email, style: const TextStyle(fontSize: 12)),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: _roleColor(member.role).withAlpha(30),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          _roleLabel(member.role),
          style: TextStyle(
              fontSize: 11, color: _roleColor(member.role)),
        ),
      ),
      onTap: isAdmin && member.role != OrgRole.admin
          ? () => _showMemberOptions(context)
          : null,
    );
  }
}
