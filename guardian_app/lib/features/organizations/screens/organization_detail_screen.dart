import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/models/app_user.dart';
import '../../../core/models/conversation.dart';
import '../../../core/models/member_suggestion.dart';
import '../../../core/models/notification_settings.dart';
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

    final membersAsync = ref.watch(orgMembersProvider(orgId));

    return orgAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Fehler: $e'))),
      data: (org) {
        final isAdmin = org.adminUid == currentUid;
        final currentMember = membersAsync.value
            ?.where((m) => m.uid == currentUid)
            .firstOrNull;
        final isModerator =
            !isAdmin && currentMember?.role == OrgRole.moderator;

        final tabCount = (isAdmin || isModerator) ? 3 : 2;
        return DefaultTabController(
          length: tabCount,
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
                _OrgNotificationToggle(orgId: orgId),
                if (isAdmin) ...[
                  IconButton(
                    icon: const Icon(Icons.manage_search_outlined),
                    tooltip: 'Schlüsselwörter',
                    onPressed: () => _showKeywordsDialog(context, ref, org),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Bearbeiten',
                    onPressed: () => _showEditDialog(context, ref, org),
                  ),
                ],
              ],
              bottom: TabBar(
                tabs: [
                  const Tab(icon: Icon(Icons.people_outline), text: 'Mitglieder'),
                  Tab(
                    child: _ChatTabLabel(
                        orgId: orgId,
                        isAdminOrMod: isAdmin || isModerator,
                        currentUid: currentUid),
                  ),
                  if (isAdmin || isModerator)
                    Tab(
                      child: _ReportsTabLabel(orgId: orgId),
                    ),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                _MembersTab(org: org, isAdmin: isAdmin, isModerator: isModerator, ref: ref),
                _ChatsTab(
                    org: org,
                    currentUid: currentUid,
                    isAdmin: isAdmin,
                    isModerator: isModerator),
                if (isAdmin || isModerator)
                  _ReportsTab(org: org),
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

  Future<void> _showKeywordsDialog(
      BuildContext context, WidgetRef ref, Organization org) async {
    final keywords = List<String>.from(org.keywords);
    final controller = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Schlüsselwörter'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Guardians und Moderatoren werden benachrichtigt, wenn eines dieser Wörter in einem Chat auftaucht.',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        decoration: const InputDecoration(
                          hintText: 'Neues Wort hinzufügen',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        textCapitalization: TextCapitalization.none,
                        onSubmitted: (value) {
                          final word = value.trim().toLowerCase();
                          if (word.isNotEmpty && !keywords.contains(word)) {
                            setState(() => keywords.add(word));
                            controller.clear();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      icon: const Icon(Icons.add),
                      onPressed: () {
                        final word = controller.text.trim().toLowerCase();
                        if (word.isNotEmpty && !keywords.contains(word)) {
                          setState(() => keywords.add(word));
                          controller.clear();
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (keywords.isEmpty)
                  const Text('Keine Schlüsselwörter definiert.',
                      style: TextStyle(color: Colors.grey, fontSize: 13))
                else
                  Flexible(
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: keywords
                            .map((kw) => Chip(
                                  label: Text(kw),
                                  onDeleted: () =>
                                      setState(() => keywords.remove(kw)),
                                ))
                            .toList(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await ref
                      .read(organizationServiceProvider)
                      .updateKeywords(orgId, keywords);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Fehler: $e')),
                    );
                  }
                }
              },
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Chats Tab ────────────────────────────────────────────────────────────────

class _ChatsTab extends ConsumerWidget {
  final Organization org;
  final String currentUid;
  final bool isAdmin;
  final bool isModerator;

  const _ChatsTab({
    required this.org,
    required this.currentUid,
    required this.isAdmin,
    required this.isModerator,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final convsAsync = isAdmin
        ? ref.watch(adminConversationsProvider(org.id))
        : ref.watch(orgConversationsProvider(org.id));
    final pendingAsync = ref.watch(pendingRequestsProvider(org.id));
    final moderatorPendingAsync =
        ref.watch(moderatorPendingRequestsProvider(org.id));
    final guardianPendingAsync =
        ref.watch(guardianPendingRequestsProvider(org.id));
    final supervisorConvsAsync =
        ref.watch(supervisorConversationsProvider(org.id));
    final guardianSupervisorConvsAsync =
        ref.watch(guardianSupervisorConversationsProvider(org.id));
    final shelteredModConvsAsync = (isModerator &&
            org.chatMode == ChatMode.sheltered)
        ? ref.watch(shelteredModeratorConversationsProvider(
            (orgId: org.id, adminUid: org.adminUid)))
        : const AsyncData(<Conversation>[]);
    final membersAsync = ref.watch(orgMembersProvider(org.id));

    return convsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (convs) {
        final approved =
            convs.where((c) => c.status == ConversationStatus.approved).toList();
        final archivedConvs =
            convs.where((c) => c.status == ConversationStatus.archived).toList();
        final ownPendingConvs = !isAdmin
            ? convs
                .where((c) => c.status == ConversationStatus.pending)
                .toList()
            : <Conversation>[];
        final guardianPending = guardianPendingAsync.value ?? [];
        final moderatorPending = moderatorPendingAsync.value ?? [];
        final supervisorConvs = supervisorConvsAsync.value ?? [];
        final guardianSupervisorConvs =
            guardianSupervisorConvsAsync.value ?? [];
        final shelteredModConvs = shelteredModConvsAsync.value ?? [];
        final allSupervisorConvs = [
          ...supervisorConvs,
          ...guardianSupervisorConvs
              .where((c) => !supervisorConvs.any((s) => s.id == c.id)),
          ...shelteredModConvs.where((c) =>
              !supervisorConvs.any((s) => s.id == c.id) &&
              !guardianSupervisorConvs.any((g) => g.id == c.id)),
        ];

        return Stack(
          children: [
            CustomScrollView(
              slivers: [
                // Ausstehende Anfragen der Kinder (für Guardians)
                if (!isAdmin && guardianPending.isNotEmpty)
                  SliverToBoxAdapter(
                    child: membersAsync.maybeWhen(
                      data: (members) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Text(
                              'Chat-Anfragen deiner Kinder (${guardianPending.length})',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.amber[800],
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                          ...guardianPending.map((conv) => _PendingRequestTile(
                                conv: conv,
                                members: members,
                                currentUid: currentUid,
                                onApprove: () => ref
                                    .read(chatServiceProvider)
                                    .approveConversation(conv.id),
                                onReject: () => ref
                                    .read(chatServiceProvider)
                                    .rejectConversation(conv.id),
                              )),
                          const Divider(),
                        ],
                      ),
                      orElse: () => const SizedBox(),
                    ),
                  ),
                // Ausstehende Anfragen für Moderatoren
                if (isModerator && moderatorPending.isNotEmpty)
                  SliverToBoxAdapter(
                    child: membersAsync.maybeWhen(
                      data: (members) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Text(
                              'Ausstehende Anfragen (${moderatorPending.length})',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                          ...moderatorPending.map((conv) => _PendingRequestTile(
                                conv: conv,
                                members: members,
                                currentUid: currentUid,
                                onApprove: () => ref
                                    .read(chatServiceProvider)
                                    .approveConversation(conv.id),
                                onReject: () => ref
                                    .read(chatServiceProvider)
                                    .rejectConversation(conv.id),
                              )),
                          const Divider(),
                        ],
                      ),
                      orElse: () => const SizedBox(),
                    ),
                  ),
                // Ausstehende Anfragen (nur für Admin sichtbar)
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

                // Ausstehende eigene Anfragen (für Nicht-Admins sichtbar)
                if (ownPendingConvs.isNotEmpty)
                  SliverToBoxAdapter(
                    child: membersAsync.maybeWhen(
                      data: (members) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Text(
                              'Ausstehende Anfragen (${ownPendingConvs.length})',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                          ...ownPendingConvs.map((conv) => _ConversationTile(
                                conv: conv,
                                members: members,
                                currentUid: currentUid,
                                isAdminOrMod: false,
                                onArchive: null,
                                onDelete: null,
                              )),
                          const Divider(),
                        ],
                      ),
                      orElse: () => const SizedBox(),
                    ),
                  ),

                // Eigene genehmigte Chats
                if (approved.isEmpty && allSupervisorConvs.isEmpty && ownPendingConvs.isEmpty)
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
                else ...[
                  if (approved.isNotEmpty)
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) => membersAsync.maybeWhen(
                          data: (members) => _ConversationTile(
                            conv: approved[i],
                            members: members,
                            currentUid: currentUid,
                            isAdminOrMod: isAdmin || isModerator,
                            onArchive: (isAdmin || isModerator)
                                ? () => ref.read(chatServiceProvider).archiveConversation(approved[i].id)
                                : null,
                            onDelete: (isAdmin || isModerator)
                                ? () => ref.read(chatServiceProvider).deleteConversation(approved[i].id)
                                : null,
                          ),
                          orElse: () => const SizedBox(),
                        ),
                        childCount: approved.length,
                      ),
                    ),
                  // Überwachte Chats (für Moderatoren + Guardians)
                  if (allSupervisorConvs.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Row(
                          children: [
                            Icon(Icons.visibility_outlined,
                                size: 14, color: Colors.grey[600]),
                            const SizedBox(width: 6),
                            Text(
                              'Überwachte Chats (${allSupervisorConvs.length})',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) => membersAsync.maybeWhen(
                          data: (members) => _ConversationTile(
                            conv: allSupervisorConvs[i],
                            members: members,
                            currentUid: currentUid,
                            isSupervisor: true,
                            isAdminOrMod: isAdmin || isModerator,
                            onArchive: (isAdmin || isModerator)
                                ? () => ref.read(chatServiceProvider).archiveConversation(allSupervisorConvs[i].id)
                                : null,
                            onDelete: (isAdmin || isModerator)
                                ? () => ref.read(chatServiceProvider).deleteConversation(allSupervisorConvs[i].id)
                                : null,
                          ),
                          orElse: () => const SizedBox(),
                        ),
                        childCount: allSupervisorConvs.length,
                      ),
                    ),
                  ],
                  // Archivierte Chats
                  if (archivedConvs.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Row(
                          children: [
                            Icon(Icons.archive_outlined,
                                size: 14, color: Colors.grey[500]),
                            const SizedBox(width: 6),
                            Text(
                              'Archiviert (${archivedConvs.length})',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[500],
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) => membersAsync.maybeWhen(
                          data: (members) => _ConversationTile(
                            conv: archivedConvs[i],
                            members: members,
                            currentUid: currentUid,
                            isAdminOrMod: isAdmin || isModerator,
                            onUnarchive: (isAdmin || isModerator)
                                ? () => ref.read(chatServiceProvider).approveConversation(archivedConvs[i].id)
                                : null,
                            onDelete: (isAdmin || isModerator)
                                ? () => ref.read(chatServiceProvider).deleteConversation(archivedConvs[i].id)
                                : null,
                          ),
                          orElse: () => const SizedBox(),
                        ),
                        childCount: archivedConvs.length,
                      ),
                    ),
                  ],
                ],
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
                          ? Text((m.displayName.isNotEmpty ? m.displayName[0] : '?').toUpperCase())
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
}

// ── FAB-ähnliche Anfrage-Schaltfläche ────────────────────────────────────────

class _ChatTabLabel extends ConsumerWidget {
  final String orgId;
  final bool isAdminOrMod;
  final String currentUid;

  const _ChatTabLabel(
      {required this.orgId,
      required this.isAdminOrMod,
      required this.currentUid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingCount = isAdminOrMod
        ? (ref.watch(pendingRequestsProvider(orgId)).value?.length ?? 0)
        : 0;

    final allConvs = [
      ...ref.watch(orgConversationsProvider(orgId)).value ?? [],
      ...ref.watch(adminConversationsProvider(orgId)).value ?? [],
    ];
    final unreadCount = allConvs
        .where((c) =>
            c.status == ConversationStatus.approved && c.hasUnread(currentUid))
        .map((c) => c.id)
        .toSet()
        .length;

    final totalCount = pendingCount + unreadCount;

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
        if (totalCount > 0)
          Positioned(
            top: -4,
            right: -10,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: pendingCount > 0 ? Colors.red : Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: Text('$totalCount',
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
  final bool isModerator;
  final WidgetRef ref;

  const _MembersTab(
      {required this.org, required this.isAdmin, required this.isModerator, required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef widgetRef) {
    final membersAsync = widgetRef.watch(orgMembersProvider(org.id));
    final pendingChildInvites =
        widgetRef.watch(pendingChildInvitesProvider(org.id)).value ?? [];
    final pendingPreRegInvites =
        widgetRef.watch(pendingPreRegInvitesProvider(org.id)).value ?? [];
    final pendingSuggestions = (isAdmin || isModerator)
        ? widgetRef.watch(pendingMemberSuggestionsProvider(org.id)).value ?? []
        : <MemberSuggestion>[];

    return membersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (members) {
        final currentUid = FirebaseAuth.instance.currentUser!.uid;
        final currentMember =
            members.where((m) => m.uid == currentUid).firstOrNull;
        final isRegularMember = !isAdmin &&
            !isModerator &&
            currentMember?.role == OrgRole.member;
        final activeMembers =
            members.where((m) => m.status == MemberStatus.active).toList();
        return Stack(
          children: [
            CustomScrollView(
              slivers: [
                // Ausstehende Mitglied-Vorschläge (nur für Admin/Moderator)
                if ((isAdmin || isModerator) && pendingSuggestions.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Text(
                            'Vorschläge (${pendingSuggestions.length})',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue[700],
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        ...pendingSuggestions.map((s) => _SuggestionTile(
                              suggestion: s,
                              org: org,
                              allMembers: members,
                              ref: widgetRef,
                            )),
                        const Divider(),
                      ],
                    ),
                  ),
                // Ausstehende Kind-Einladungen für Guardian
                if (pendingChildInvites.isNotEmpty || pendingPreRegInvites.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Text(
                            'Ausstehende Kind-Einladungen (${pendingChildInvites.length + pendingPreRegInvites.length})',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.amber[800],
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        // Bereits registrierte Kinder (warten auf Guardian-Zustimmung)
                        ...pendingChildInvites.map((child) => _PendingChildTile(
                              child: child,
                              org: org,
                              ref: widgetRef,
                            )),
                        // Noch nicht registrierte Kinder (Einladung verschickt)
                        ...pendingPreRegInvites.map((invite) => _PendingInviteTile(
                              invite: invite,
                              org: org,
                              ref: widgetRef,
                            )),
                        const Divider(),
                      ],
                    ),
                  ),
                // Mitgliederliste
                activeMembers.isEmpty
                    ? const SliverFillRemaining(
                        child: Center(
                          child: Text('Noch keine Mitglieder',
                              style: TextStyle(color: Colors.grey)),
                        ),
                      )
                    : SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (ctx, i) => Column(
                              children: [
                                _MemberTile(
                                  member: activeMembers[i],
                                  org: org,
                                  isAdmin: isAdmin,
                                  ref: widgetRef,
                                  allMembers: members,
                                  currentUid: FirebaseAuth.instance.currentUser!.uid,
                                ),
                                if (i < activeMembers.length - 1)
                                  const Divider(height: 1),
                              ],
                            ),
                            childCount: activeMembers.length,
                          ),
                        ),
                      ),
              ],
            ),
          if (isAdmin || isModerator)
            Positioned(
              bottom: 16,
              right: 16,
              child: FloatingActionButton.extended(
                heroTag: 'invite',
                onPressed: () =>
                    _showInviteDialog(context, widgetRef, members),
                icon: const Icon(Icons.person_add_outlined),
                label: const Text('Mitglied einladen'),
              ),
            ),
          if (isRegularMember)
            Positioned(
              bottom: 16,
              right: 16,
              child: FloatingActionButton.extended(
                heroTag: 'suggest',
                onPressed: () =>
                    _showSuggestDialog(context, widgetRef, members),
                icon: const Icon(Icons.person_add_outlined),
                label: const Text('Mitglied vorschlagen'),
              ),
            ),
          if (org.chatMode == ChatMode.guardian && !isAdmin && !isModerator && !isRegularMember)
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
      );
    },
  );
  }

  Future<void> _showInviteDialog(
      BuildContext context, WidgetRef ref, List<OrgMember> members) async {
    final emailController = TextEditingController();
    OrgRole selectedRole = OrgRole.member;
    final selectedGuardians = <OrgMember>{};
    bool emailValid = false;

    final roleLabels = {
      OrgRole.moderator: 'Moderator',
      OrgRole.member: 'Mitglied',
      OrgRole.child: 'Kind',
    };

    // Mögliche Guardians: aktive Mitglieder und Moderatoren (keine Kinder)
    final possibleGuardians = members
        .where((m) =>
            m.role != OrgRole.child &&
            m.status == MemberStatus.active)
        .toList();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Mitglied einladen'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: emailController,
                  autofocus: true,
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (v) => setState(() {
                    emailValid = RegExp(
                      r'^[\w.+\-]+@[\w\-]+\.[\w.\-]+$',
                    ).hasMatch(v.trim());
                  }),
                  decoration: InputDecoration(
                    labelText: 'E-Mail-Adresse',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.email_outlined),
                    errorText: emailController.text.isNotEmpty && !emailValid
                        ? 'Ungültige E-Mail-Adresse'
                        : null,
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
                  onSelectionChanged: (s) => setState(() {
                    selectedRole = s.first;
                    if (selectedRole != OrgRole.child) selectedGuardians.clear();
                  }),
                ),
                if (selectedRole == OrgRole.child) ...[
                  const SizedBox(height: 16),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Guardians (Elternteile)',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 14, color: Colors.amber[800]),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Das Kind wird erst hinzugefügt, wenn ein Guardian zustimmt.',
                            style: TextStyle(
                                fontSize: 11, color: Colors.amber[900]),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (possibleGuardians.isEmpty)
                    const Text(
                      'Keine Mitglieder als Guardian verfügbar.',
                      style: TextStyle(fontSize: 12, color: Colors.red),
                    )
                  else
                    ...possibleGuardians.map((m) => CheckboxListTile(
                          value: selectedGuardians.contains(m),
                          title: Text(m.displayName),
                          subtitle: Text(m.email,
                              style: const TextStyle(fontSize: 11)),
                          secondary: const Icon(Icons.shield_outlined),
                          contentPadding: EdgeInsets.zero,
                          onChanged: (checked) => setState(() {
                            if (checked == true) {
                              selectedGuardians.add(m);
                            } else {
                              selectedGuardians.remove(m);
                            }
                          }),
                        )),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: (!emailValid ||
                      (selectedRole == OrgRole.child &&
                          selectedGuardians.isEmpty))
                  ? null
                  : () => Navigator.pop(ctx, true),
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
              guardianUids: selectedRole == OrgRole.child
                  ? selectedGuardians.map((m) => m.uid).toList()
                  : [],
            );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(selectedRole == OrgRole.child
                  ? 'Einladung gesendet. Das Kind wird nach Registrierung und Guardian-Zustimmung hinzugefügt.'
                  : 'Einladung gesendet.'),
            ),
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
                          child: m.photoUrl == null ? Text((m.displayName.isNotEmpty ? m.displayName[0] : '?').toUpperCase()) : null,
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

  Future<void> _showSuggestDialog(
      BuildContext context, WidgetRef ref, List<OrgMember> members) async {
    final emailController = TextEditingController();
    OrgRole selectedRole = OrgRole.member;
    OrgMember? selectedGuardian;
    bool emailValid = false;

    final roleLabels = {
      OrgRole.member: 'Mitglied',
      OrgRole.child: 'Kind',
    };

    final possibleGuardians = members
        .where((m) =>
            m.role != OrgRole.child && m.status == MemberStatus.active)
        .toList();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Mitglied vorschlagen'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: emailController,
                  autofocus: true,
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (v) => setState(() {
                    emailValid = RegExp(
                      r'^[\w.+\-]+@[\w\-]+\.[\w.\-]+$',
                    ).hasMatch(v.trim());
                  }),
                  decoration: InputDecoration(
                    labelText: 'E-Mail-Adresse',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.email_outlined),
                    errorText: emailController.text.isNotEmpty && !emailValid
                        ? 'Ungültige E-Mail-Adresse'
                        : null,
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
                  onSelectionChanged: (s) => setState(() {
                    selectedRole = s.first;
                    if (selectedRole != OrgRole.child) selectedGuardian = null;
                  }),
                ),
                if (selectedRole == OrgRole.child) ...[
                  const SizedBox(height: 16),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Guardian',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
                  const SizedBox(height: 4),
                  if (possibleGuardians.isEmpty)
                    const Text(
                      'Keine Mitglieder als Guardian verfügbar.',
                      style: TextStyle(fontSize: 12, color: Colors.red),
                    )
                  else
                    DropdownButtonFormField<OrgMember>(
                      initialValue: selectedGuardian,
                      hint: const Text('Guardian wählen'),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.shield_outlined),
                      ),
                      items: possibleGuardians
                          .map((m) => DropdownMenuItem(
                                value: m,
                                child: Text(m.displayName),
                              ))
                          .toList(),
                      onChanged: (m) => setState(() => selectedGuardian = m),
                    ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: (!emailValid ||
                      (selectedRole == OrgRole.child &&
                          selectedGuardian == null))
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: const Text('Vorschlagen'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && emailController.text.trim().isNotEmpty) {
      try {
        await ref.read(organizationServiceProvider).suggestMember(
              org.id,
              emailController.text.trim(),
              selectedRole,
              guardianUids: selectedRole == OrgRole.child && selectedGuardian != null
                  ? [selectedGuardian!.uid]
                  : [],
            );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Vorschlag wurde eingereicht und wartet auf Genehmigung.'),
            ),
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

// ── Suggestion Tile ──────────────────────────────────────────────────────────

class _SuggestionTile extends StatelessWidget {
  final MemberSuggestion suggestion;
  final Organization org;
  final List<OrgMember> allMembers;
  final WidgetRef ref;

  const _SuggestionTile({
    required this.suggestion,
    required this.org,
    required this.allMembers,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final guardianNames = suggestion.guardianUids
        .map((uid) =>
            allMembers.where((m) => m.uid == uid).firstOrNull?.displayName ??
            uid)
        .join(', ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 18,
            child: Icon(Icons.person_outline, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(suggestion.email,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                Text(
                  suggestion.role == OrgRole.child
                      ? 'Kind · Guardian: ${guardianNames.isNotEmpty ? guardianNames : '–'}'
                      : 'Mitglied',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                Text(
                  'von ${suggestion.suggestedByName}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () async {
              try {
                await ref
                    .read(organizationServiceProvider)
                    .rejectSuggestion(org.id, suggestion.id);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Fehler: $e')),
                  );
                }
              }
            },
            child: const Text('Ablehnen'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await ref
                    .read(organizationServiceProvider)
                    .approveSuggestion(
                      org.id,
                      suggestion.id,
                      suggestion.email,
                      suggestion.role,
                      suggestion.guardianUids,
                    );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Einladung gesendet.')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Fehler: $e')),
                  );
                }
              }
            },
            child: const Text('Annehmen'),
          ),
        ],
      ),
    );
  }
}

// ── Org Notification Toggle ──────────────────────────────────────────────────

class _OrgNotificationToggle extends ConsumerWidget {
  final String orgId;
  const _OrgNotificationToggle({required this.orgId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final interval =
        ref.watch(orgMessageIntervalProvider(orgId)).value ??
            MessageAlertInterval.always;
    final muted = interval == MessageAlertInterval.never;

    return IconButton(
      icon: Icon(
        muted ? Icons.notifications_off_outlined : Icons.notifications_outlined,
        color: muted ? Colors.grey : null,
      ),
      tooltip: 'Benachrichtigungen dieser Org',
      onPressed: () => _showIntervalSheet(context, ref, interval),
    );
  }

  void _showIntervalSheet(
      BuildContext context, WidgetRef ref, MessageAlertInterval current) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Benachrichtigungen dieser Org',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            RadioGroup<MessageAlertInterval>(
              groupValue: current,
              onChanged: (v) async {
                Navigator.pop(ctx);
                if (v == null) return;
                await ref
                    .read(organizationServiceProvider)
                    .setOrgMessageInterval(orgId, v);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: MessageAlertInterval.values
                    .map((interval) => RadioListTile<MessageAlertInterval>(
                          title: Text(interval.label),
                          value: interval,
                        ))
                    .toList(),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Conversation Tile ────────────────────────────────────────────────────────

class _ConversationTile extends StatelessWidget {
  final Conversation conv;
  final List<OrgMember> members;
  final String currentUid;
  final bool isSupervisor;
  final bool isAdminOrMod;
  final VoidCallback? onArchive;
  final VoidCallback? onUnarchive;
  final VoidCallback? onDelete;

  const _ConversationTile({
    required this.conv,
    required this.members,
    required this.currentUid,
    this.isSupervisor = false,
    this.isAdminOrMod = false,
    this.onArchive,
    this.onUnarchive,
    this.onDelete,
  });

  void _showOptions(BuildContext context) {
    final isArchived = conv.status == ConversationStatus.archived;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isArchived && onArchive != null)
              ListTile(
                leading: const Icon(Icons.archive_outlined),
                title: const Text('Archivieren'),
                onTap: () { Navigator.pop(ctx); onArchive!(); },
              ),
            if (isArchived && onUnarchive != null)
              ListTile(
                leading: const Icon(Icons.unarchive_outlined),
                title: const Text('Aus Archiv wiederherstellen'),
                onTap: () { Navigator.pop(ctx); onUnarchive!(); },
              ),
            if (onDelete != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Löschen', style: TextStyle(color: Colors.red)),
                onTap: () { Navigator.pop(ctx); onDelete!(); },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isArchived = conv.status == ConversationStatus.archived;
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
        child: photoUrl == null ? Text((title.isNotEmpty ? title[0] : '?').toUpperCase()) : null,
      );
    }

    Widget leading = isSupervisor
        ? Stack(
            children: [
              avatar,
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.grey[600],
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.visibility, size: 10, color: Colors.white),
                ),
              ),
            ],
          )
        : avatar;

    if (isArchived) {
      leading = Stack(
        children: [
          ColorFiltered(
            colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.saturation),
            child: leading,
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(color: Colors.grey[500], shape: BoxShape.circle),
              child: const Icon(Icons.archive, size: 10, color: Colors.white),
            ),
          ),
        ],
      );
    }

    final hasUnread = !isArchived && conv.hasUnread(currentUid);

    return ListTile(
      leading: leading,
      title: Text(title,
          style: isArchived
              ? TextStyle(color: Colors.grey[500])
              : hasUnread
                  ? const TextStyle(fontWeight: FontWeight.bold)
                  : null),
      subtitle: conv.lastMessage != null
          ? Text(conv.lastMessage!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: isArchived
                  ? TextStyle(color: Colors.grey[400])
                  : hasUnread
                      ? const TextStyle(fontWeight: FontWeight.w500)
                      : null)
          : Text('Noch keine Nachrichten',
              style: TextStyle(color: isArchived ? Colors.grey[400] : Colors.grey)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasUnread)
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
          if (conv.lastMessageAt != null)
            Text(_formatTime(conv.lastMessageAt!),
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
                    color: isArchived
                        ? Colors.grey[400]
                        : hasUnread
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey)),
          if (isAdminOrMod) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => _showOptions(context),
              child: Icon(Icons.more_vert, size: 18, color: Colors.grey[500]),
            ),
          ],
        ],
      ),
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
  final List<OrgMember> allMembers;
  final String currentUid;

  const _MemberTile({
    required this.member,
    required this.org,
    required this.isAdmin,
    required this.ref,
    required this.allMembers,
    required this.currentUid,
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

  void _showOptions(BuildContext context) {
    final isOwnTile = member.uid == currentUid;
    final isGuardian = member.guardianUids.contains(currentUid);
    final isMod = !isAdmin &&
        allMembers
            .where((m) => m.uid == currentUid)
            .firstOrNull
            ?.role == OrgRole.moderator;

    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Eigene Benachrichtigungseinstellungen
            if (isOwnTile)
              ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: const Text('Benachrichtigungseinstellungen'),
                onTap: () {
                  Navigator.pop(context);
                  _showAlertIntervalDialog(context);
                },
              ),
            if (isOwnTile)
              ListTile(
                leading: const Icon(Icons.exit_to_app, color: Colors.red),
                title: const Text('Organisation verlassen',
                    style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _confirmLeave(context);
                },
              ),
            // Moderator: Guardians eines Kindes ändern
            if ((isMod || isAdmin) && !isOwnTile && member.role == OrgRole.child)
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: const Text('Guardians ändern'),
                onTap: () {
                  Navigator.pop(context);
                  _showGuardiansDialog(context);
                },
              ),
            // Guardian: direkter Chat mit eigenem Kind (kein Approval nötig)
            if (!isAdmin && !isOwnTile && isGuardian)
              ListTile(
                leading: const Icon(Icons.chat_outlined),
                title: const Text('Chat starten'),
                onTap: () {
                  Navigator.pop(context);
                  _startAdminChat(context);
                },
              ),
            // Nicht-Admin im Guardian-Modus: Chat anfragen (für andere Mitglieder)
            if (!isAdmin && !isOwnTile && !isGuardian && org.chatMode == ChatMode.guardian)
              ListTile(
                leading: const Icon(Icons.chat_outlined),
                title: const Text('Chat anfragen'),
                onTap: () {
                  Navigator.pop(context);
                  _requestChat(context);
                },
              ),
            // Admin: Chat starten, Rolle ändern, Admin übertragen, Entfernen
            if (isAdmin && !isOwnTile && member.role != OrgRole.admin) ...[
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
                leading: const Icon(Icons.admin_panel_settings_outlined,
                    color: Colors.orange),
                title: const Text('Admin-Rolle übertragen',
                    style: TextStyle(color: Colors.orange)),
                onTap: () {
                  Navigator.pop(context);
                  _confirmTransferAdmin(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.person_remove_outlined, color: Colors.red),
                title: const Text('Entfernen', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _confirmRemove(context);
                },
              ),
            ],
            if (!isOwnTile && !isGuardian && !isAdmin && !isMod)
              const ListTile(
                title: Text('Keine Aktionen verfügbar.',
                    style: TextStyle(color: Colors.grey)),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showGuardiansDialog(BuildContext context) async {
    final possibleGuardians = allMembers
        .where((m) => m.role != OrgRole.child && m.status == MemberStatus.active)
        .toList();
    final selected = <String>{...member.guardianUids};

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('Guardians für ${member.displayName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: possibleGuardians.map((g) {
              return CheckboxListTile(
                value: selected.contains(g.uid),
                title: Text(g.displayName),
                subtitle: Text(g.email, style: const TextStyle(fontSize: 11)),
                secondary: const Icon(Icons.shield_outlined),
                contentPadding: EdgeInsets.zero,
                onChanged: (v) => setState(() {
                  if (v == true) { selected.add(g.uid); }
                  else { selected.remove(g.uid); }
                }),
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: selected.isEmpty ? null : () => Navigator.pop(ctx, true),
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      await ref.read(organizationServiceProvider).updateGuardians(
            org.id, member.uid, selected.toList());
    }
  }

  Future<void> _requestChat(BuildContext context) async {
    try {
      await ref
          .read(chatServiceProvider)
          .requestConversation(org.id, member.uid);
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
    if (confirmed != true || selected == member.role) return;

    if (selected == OrgRole.child) {
      // Guardian-Auswahl direkt anzeigen wenn Rolle auf Kind gesetzt wird
      if (!context.mounted) return;
      await _showRoleToChildGuardianDialog(context);
    } else {
      await ref
          .read(organizationServiceProvider)
          .updateMemberRole(org.id, member.uid, selected);
    }
  }

  Future<void> _showRoleToChildGuardianDialog(BuildContext context) async {
    final possibleGuardians = allMembers
        .where((m) => m.role != OrgRole.child && m.status == MemberStatus.active && m.uid != member.uid)
        .toList();
    final selected = <String>{};

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('Guardian für ${member.displayName}'),
          content: possibleGuardians.isEmpty
              ? const Text('Keine möglichen Guardians in dieser Organisation.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Wähle mindestens einen Guardian für dieses Kind:',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    ...possibleGuardians.map((g) => CheckboxListTile(
                          value: selected.contains(g.uid),
                          title: Text(g.displayName),
                          subtitle: Text(g.email,
                              style: const TextStyle(fontSize: 11)),
                          secondary: const Icon(Icons.shield_outlined),
                          contentPadding: EdgeInsets.zero,
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              selected.add(g.uid);
                            } else {
                              selected.remove(g.uid);
                            }
                          }),
                        )),
                  ],
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: possibleGuardians.isEmpty || selected.isNotEmpty
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      final service = ref.read(organizationServiceProvider);
      await service.updateMemberRole(org.id, member.uid, OrgRole.child);
      if (selected.isNotEmpty) {
        await service.updateGuardians(org.id, member.uid, selected.toList());
      }
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

  Future<void> _confirmLeave(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Organisation verlassen'),
        content: Text(
            'Möchtest du die Organisation "${org.name}" wirklich verlassen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Verlassen'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      try {
        await ref
            .read(organizationServiceProvider)
            .leaveOrganization(org.id);
        if (context.mounted) context.pop();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$e')));
        }
      }
    }
  }

  Future<void> _confirmTransferAdmin(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Admin-Rolle übertragen'),
        content: Text(
          'Möchtest du die Admin-Rolle an ${member.displayName} übertragen?\n\n'
          'Du wirst danach ein normales Mitglied dieser Organisation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Übertragen'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await ref
            .read(organizationServiceProvider)
            .transferAdmin(org.id, member.uid);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fehler: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Alle Guardians des Kindes ermitteln
    final guardians = member.role == OrgRole.child
        ? allMembers.where((m) => member.guardianUids.contains(m.uid)).toList()
        : <OrgMember>[];
    return ListTile(
      isThreeLine: guardians.isNotEmpty,
      leading: CircleAvatar(
        backgroundImage: member.photoUrl != null
            ? NetworkImage(member.photoUrl!)
            : null,
        child: member.photoUrl == null
            ? Text((member.displayName.isNotEmpty ? member.displayName[0] : '?').toUpperCase())
            : null,
      ),
      title: Text(member.displayName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(member.email, style: const TextStyle(fontSize: 12)),
          if (guardians.isNotEmpty)
            Row(
              children: [
                Icon(Icons.shield_outlined, size: 11, color: Colors.amber[700]),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    guardians.map((g) => g.displayName).join(', '),
                    style: TextStyle(fontSize: 11, color: Colors.amber[800]),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _roleColor(member.role).withAlpha(30),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _roleLabel(member.role),
              style: TextStyle(fontSize: 11, color: _roleColor(member.role)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, size: 20),
            onPressed: () => _showOptions(context),
          ),
        ],
      ),
      onTap: null,
    );
  }

  Future<void> _showAlertIntervalDialog(BuildContext context) async {
    ChildAlertInterval selected = member.childAlertInterval;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Kind-Aktivität Benachrichtigungen'),
          content: RadioGroup<ChildAlertInterval>(
            groupValue: selected,
            onChanged: (v) => setState(() => selected = v!),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: ChildAlertInterval.values.map((interval) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Radio<ChildAlertInterval>(value: interval),
                  title: Text(interval.label),
                  onTap: () => setState(() => selected = interval),
                );
              }).toList(),
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
    if (confirmed == true && selected != member.childAlertInterval) {
      await ref
          .read(organizationServiceProvider)
          .updateChildAlertInterval(org.id, selected);
    }
  }
}

// ── Pending Child Invite Tile ─────────────────────────────────────────────────

class _PendingChildTile extends StatelessWidget {
  final OrgMember child;
  final Organization org;
  final WidgetRef ref;

  const _PendingChildTile({
    required this.child,
    required this.org,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.amber.withAlpha(40),
        child: Icon(Icons.child_care, color: Colors.amber[800], size: 20),
      ),
      title: Text(child.displayName),
      subtitle: Text(
        '${child.email} · Wartet auf deine Zustimmung',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.check_circle_outline, color: Colors.green),
            tooltip: 'Zustimmen',
            onPressed: () async {
              try {
                await ref
                    .read(organizationServiceProvider)
                    .approveChildInvite(org.id, child.uid);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content:
                            Text('${child.displayName} wurde hinzugefügt.')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('Fehler: $e')));
                }
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.cancel_outlined, color: Colors.red),
            tooltip: 'Ablehnen',
            onPressed: () async {
              try {
                await ref
                    .read(organizationServiceProvider)
                    .rejectChildInvite(org.id, child.uid);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('Fehler: $e')));
                }
              }
            },
          ),
        ],
      ),
    );
  }
}

// ── Reports Tab Label ─────────────────────────────────────────────────────────

class _ReportsTabLabel extends ConsumerWidget {
  final String orgId;
  const _ReportsTabLabel({required this.orgId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsAsync = ref.watch(_pendingReportsCountProvider(orgId));
    final count = reportsAsync.value ?? 0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Padding(
          padding: EdgeInsets.only(right: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.flag_outlined, size: 16),
              SizedBox(width: 4),
              Text('Meldungen'),
            ],
          ),
        ),
        if (count > 0)
          Positioned(
            right: 0,
            top: -4,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$count',
                style: const TextStyle(fontSize: 9, color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }
}

final _pendingReportsCountProvider =
    StreamProvider.family<int, String>((ref, orgId) {
  return FirebaseFirestore.instance
      .collection('reports')
      .where('orgId', isEqualTo: orgId)
      .where('status', isEqualTo: 'pending')
      .snapshots()
      .map((s) => s.docs.length);
});

// ── Reports Tab ───────────────────────────────────────────────────────────────

class _ReportsTab extends ConsumerStatefulWidget {
  final Organization org;
  const _ReportsTab({required this.org});

  @override
  ConsumerState<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends ConsumerState<_ReportsTab> {
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final reportsAsync = ref.watch(_orgReportsProvider(widget.org.id));

    return reportsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (allReports) {
        final pending =
            allReports.where((r) => r['status'] == 'pending').toList();
        final archived =
            allReports.where((r) => r['status'] == 'reviewed').toList();
        final visible = _showArchived ? allReports : pending;

        return Column(
          children: [
            // Toggle-Leiste
            if (archived.isNotEmpty)
              InkWell(
                onTap: () => setState(() => _showArchived = !_showArchived),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                            ? 'Archivierte ausblenden'
                            : 'Archivierte anzeigen (${archived.length})',
                        style:
                            TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: visible.isEmpty
                  ? Center(
                      child: Text(
                        _showArchived
                            ? 'Keine Meldungen'
                            : 'Keine ausstehenden Meldungen',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final report = visible[i];
                        final isPending = report['status'] == 'pending';
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isPending
                                ? Colors.red.withAlpha(30)
                                : Colors.grey.withAlpha(30),
                            child: Icon(
                              isPending
                                  ? Icons.flag_outlined
                                  : Icons.archive_outlined,
                              color:
                                  isPending ? Colors.red : Colors.grey,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            report['messageSenderName'] as String? ?? '?',
                            style: TextStyle(
                              fontWeight: isPending
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isPending ? null : Colors.grey[600],
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                report['messageText'] as String? ?? '',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isPending ? null : Colors.grey[500],
                                ),
                              ),
                              Text(
                                isPending ? 'Ausstehend' : 'Geprüft · Archiviert',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isPending ? Colors.red : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                          isThreeLine: true,
                          trailing: PopupMenuButton<String>(
                            onSelected: (action) async {
                              if (action == 'reviewed') {
                                await ref
                                    .read(chatServiceProvider)
                                    .markReportReviewed(
                                        report['id'] as String);
                              } else if (action == 'delete_msg') {
                                await _deleteMessage(context, report);
                              }
                            },
                            itemBuilder: (_) => [
                              if (isPending)
                                const PopupMenuItem(
                                  value: 'reviewed',
                                  child: ListTile(
                                    leading: Icon(
                                        Icons.check_circle_outline,
                                        color: Colors.green),
                                    title: Text('Als geprüft markieren'),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              const PopupMenuItem(
                                value: 'delete_msg',
                                child: ListTile(
                                  leading: Icon(Icons.delete_outline,
                                      color: Colors.red),
                                  title: Text('Nachricht löschen',
                                      style: TextStyle(color: Colors.red)),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ],
                          ),
                          onTap: () {
                            final convId = report['convId'] as String?;
                            if (convId != null) context.push('/chat/$convId');
                          },
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteMessage(
      BuildContext context, Map<String, dynamic> report) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nachricht löschen'),
        content: const Text(
            'Diese Nachricht wird dauerhaft gelöscht und der Report als geprüft markiert.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final convId = report['convId'] as String?;
    final msgId = report['msgId'] as String?;
    final reportId = report['id'] as String;

    if (convId != null && msgId != null) {
      await FirebaseFirestore.instance
          .collection('conversations')
          .doc(convId)
          .collection('messages')
          .doc(msgId)
          .delete();
    }
    await ref.read(chatServiceProvider).markReportReviewed(reportId);
  }
}

// ── Pending Pre-Registration Invite Tile ──────────────────────────────────────

class _PendingInviteTile extends StatelessWidget {
  final Map<String, dynamic> invite;
  final Organization org;
  final WidgetRef ref;

  const _PendingInviteTile({
    required this.invite,
    required this.org,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final email = invite['email'] as String? ?? '?';
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.amber.withAlpha(40),
        child: Icon(Icons.child_care, color: Colors.amber[800], size: 20),
      ),
      title: Text(email),
      subtitle: const Text(
        'Einladung verschickt · Noch nicht registriert',
        style: TextStyle(fontSize: 12),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.cancel_outlined, color: Colors.red),
        tooltip: 'Einladung zurückziehen',
        onPressed: () async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Einladung zurückziehen'),
              content: Text('Einladung für $email wirklich zurückziehen?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Abbrechen'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Zurückziehen'),
                ),
              ],
            ),
          );
          if (confirmed == true) {
            await ref
                .read(organizationServiceProvider)
                .cancelInvitation(invite['id'] as String);
          }
        },
      ),
    );
  }
}

final _orgReportsProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String>((ref, orgId) {
  return ref.read(chatServiceProvider).watchReports(orgId);
});
