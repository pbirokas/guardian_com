import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:guardian_app/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/models/announcement.dart';
import '../../../core/models/app_user.dart';
import '../../../core/models/conversation.dart';
import '../../../core/models/member_suggestion.dart';
import '../../../core/models/notification_settings.dart';
import '../../../core/models/org_member.dart';

import '../../../core/models/organization.dart';
import '../../chat/providers/chat_provider.dart';
import '../providers/organizations_provider.dart';
import 'bulk_import_screen.dart';

class OrganizationDetailScreen extends ConsumerWidget {
  final String orgId;

  const OrganizationDetailScreen({super.key, required this.orgId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final orgAsync = ref.watch(organizationProvider(orgId));
    final currentUid = FirebaseAuth.instance.currentUser!.uid;

    final membersAsync = ref.watch(orgMembersProvider(orgId));

    return orgAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text(l.errorMessage(e.toString())))),
      data: (org) {
        final isAdmin = org.adminUid == currentUid;
        final currentMember = membersAsync.value
            ?.where((m) => m.uid == currentUid)
            .firstOrNull;
        final isModerator =
            !isAdmin && currentMember?.role == OrgRole.moderator;

        final tabCount = (isAdmin || isModerator) ? 4 : 3;
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
                    tooltip: l.keywordsTooltip,
                    onPressed: () => _showKeywordsDialog(context, ref, org),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: l.editTooltip,
                    onPressed: () => _showEditDialog(context, ref, org),
                  ),
                ],
              ],
              bottom: TabBar(
                labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                tabs: [
                  Tab(icon: const Icon(Icons.people_outline), text: l.tabMembers),
                  Tab(
                    child: _ChatTabLabel(
                        orgId: orgId,
                        isAdminOrMod: isAdmin || isModerator,
                        currentUid: currentUid),
                  ),
                  Tab(child: _PinnwandTabLabel(orgId: orgId)),
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
                _PinnwandTab(
                    orgId: orgId,
                    canManage: isAdmin || isModerator),
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
    final l = AppLocalizations.of(context);
    final nameController = TextEditingController(text: org.name);
    OrgTag selectedTag = org.tag;
    ChatMode selectedMode = org.chatMode;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final ld = AppLocalizations.of(ctx);
          return AlertDialog(
            title: Text(ld.editOrganization),
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
                      labelText: ld.orgName,
                      border: const OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 16),
                  Text(ld.category,
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
                  Text(ld.chatMode,
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
                child: Text(ld.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(ld.save),
              ),
            ],
          );
        },
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
            SnackBar(content: Text(l.errorMessage(e.toString()))),
          );
        }
      }
    }
  }

  Future<void> _showKeywordsDialog(
      BuildContext context, WidgetRef ref, Organization org) async {
    final l = AppLocalizations.of(context);
    final keywords = List<String>.from(org.keywords);
    final controller = TextEditingController();

    // ── CSV Export ────────────────────────────────────────────────────────────
    Future<void> exportCsv(StateSetter setState) async {
      if (keywords.isEmpty) return;
      try {
        final csvContent = keywords.join('\n');
        final dir = await getTemporaryDirectory();
        final safeName = org.name.replaceAll(RegExp(r'[^\w]'), '_');
        final file = File('${dir.path}/${safeName}_keywords.csv');
        await file.writeAsString(csvContent);
        await OpenFilex.open(file.path);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.keywordsExported)),
          );
        }
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.keywordsExportFailed)),
          );
        }
      }
    }

    // ── CSV Import ────────────────────────────────────────────────────────────
    Future<void> importCsv(StateSetter setState) async {
      final result = await FilePicker.pickFiles(
        dialogTitle: l.keywordsImportCsv,
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final bytes = result.files.first.bytes;
      if (bytes == null) return;

      final content = String.fromCharCodes(bytes);
      // Unterstützt: eine Zeile pro Keyword ODER kommagetrennt
      final raw = content
          .split(RegExp(r'[\n,;]'))
          .map((w) => w.trim().toLowerCase())
          .where((w) => w.isNotEmpty)
          .toList();

      int added = 0;
      setState(() {
        for (final word in raw) {
          if (!keywords.contains(word)) {
            keywords.add(word);
            added++;
          }
        }
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.keywordsImported(added))),
        );
      }
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final ld = AppLocalizations.of(ctx);
          return AlertDialog(
            title: Row(
              children: [
                Expanded(child: Text(ld.keywordsTitle)),
                IconButton(
                  icon: const Icon(Icons.upload_file_outlined),
                  tooltip: ld.keywordsImportCsv,
                  onPressed: () => importCsv(setState),
                ),
                IconButton(
                  icon: const Icon(Icons.download_outlined),
                  tooltip: ld.keywordsExportCsv,
                  onPressed: () => exportCsv(setState),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ld.keywordsDescription,
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          decoration: InputDecoration(
                            hintText: ld.addKeywordHint,
                            border: const OutlineInputBorder(),
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
                    Text(ld.noKeywordsDefined,
                        style: const TextStyle(color: Colors.grey, fontSize: 13))
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
                child: Text(ld.cancel),
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
                        SnackBar(content: Text(l.errorMessage(e.toString()))),
                      );
                    }
                  }
                },
                child: Text(ld.save),
              ),
            ],
          );
        },
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
    final l = AppLocalizations.of(context);
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
      error: (e, _) => Center(child: Text(l.errorMessage(e.toString()))),
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
                              l.childChatRequests(guardianPending.length),
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
                              l.pendingRequests(moderatorPending.length),
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
                                l.pendingRequests(pending.length),
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
                              l.pendingRequests(ownPendingConvs.length),
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
                                ? l.noChatsGuardian
                                : l.noChatsSheltered,
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
                              l.monitoredChats(allSupervisorConvs.length),
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
                              l.archivedChats(archivedConvs.length),
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
                    label: Text(l.createGroup),
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
  final l = AppLocalizations.of(context);
  final nameController = TextEditingController();
  final nonAdmins = members.where((m) => m.uid != org.adminUid).toList();
  final selected = <String>{};

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final ld = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(ld.createGroup),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  maxLength: 40,
                  decoration: InputDecoration(
                    labelText: ld.groupName,
                    border: const OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                Text(ld.addMembers,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
              child: Text(ld.cancel),
            ),
            FilledButton(
              onPressed: selected.isEmpty || nameController.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: Text(ld.create),
            ),
          ],
        );
      },
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
          SnackBar(content: Text(l.errorMessage(e.toString()))),
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
    final l = AppLocalizations.of(context);
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
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.chat_outlined),
            Text(l.tabChats, style: const TextStyle(fontSize: 10)),
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
    final l = AppLocalizations.of(context);
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
      error: (e, _) => Center(child: Text(l.errorMessage(e.toString()))),
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
                            l.suggestions(pendingSuggestions.length),
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
                            l.pendingChildInvitations(pendingChildInvites.length + pendingPreRegInvites.length),
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
                    ? SliverFillRemaining(
                        child: Center(
                          child: Text(l.noMembers,
                              style: const TextStyle(color: Colors.grey)),
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (isAdmin && org.chatMode == ChatMode.sheltered)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: FloatingActionButton.extended(
                        heroTag: 'bulk_import',
                        backgroundColor:
                            Theme.of(context).colorScheme.secondaryContainer,
                        foregroundColor:
                            Theme.of(context).colorScheme.onSecondaryContainer,
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => BulkImportScreen(
                              org: org,
                              members: members,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.upload_file_outlined),
                        label: Text(l.csvImport),
                      ),
                    ),
                  FloatingActionButton.extended(
                    heroTag: 'invite',
                    onPressed: () =>
                        _showInviteDialog(context, widgetRef, members),
                    icon: const Icon(Icons.person_add_outlined),
                    label: Text(l.inviteMember),
                  ),
                ],
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
                label: Text(l.suggestMember),
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
                label: Text(l.requestChat),
              ),
            ),
        ],
      );
    },
  );
  }

  Future<void> _showInviteDialog(
      BuildContext context, WidgetRef ref, List<OrgMember> members) async {
    final l = AppLocalizations.of(context);
    final emailController = TextEditingController();
    OrgRole selectedRole = OrgRole.member;
    final selectedGuardians = <OrgMember>{};
    bool emailValid = false;

    // Mögliche Guardians: aktive Mitglieder und Moderatoren (keine Kinder)
    final possibleGuardians = members
        .where((m) =>
            m.role != OrgRole.child &&
            m.status == MemberStatus.active)
        .toList();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final ld = AppLocalizations.of(ctx);
          final roleLabels = {
            OrgRole.moderator: ld.roleModerator,
            OrgRole.member: ld.roleMember,
            OrgRole.child: ld.roleChild,
          };
          return AlertDialog(
            title: Text(ld.inviteMember),
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
                      labelText: ld.emailAddress,
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.email_outlined),
                      errorText: emailController.text.isNotEmpty && !emailValid
                          ? ld.invalidEmailAddress
                          : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(ld.role,
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(ld.guardians,
                          style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
                              ld.childGuardianHint,
                              style: TextStyle(
                                  fontSize: 11, color: Colors.amber[900]),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (possibleGuardians.isEmpty)
                      Text(
                        ld.noGuardiansAvailable,
                        style: const TextStyle(fontSize: 12, color: Colors.red),
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
                child: Text(ld.cancel),
              ),
              FilledButton(
                onPressed: (!emailValid ||
                        (selectedRole == OrgRole.child &&
                            selectedGuardians.isEmpty))
                    ? null
                    : () => Navigator.pop(ctx, true),
                child: Text(ld.invite),
              ),
            ],
          );
        },
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
                  ? l.inviteSentChild
                  : l.inviteSent),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.errorMessage(e.toString()))),
          );
        }
      }
    }
  }

  Future<void> _showChatRequestDialog(
      BuildContext context, WidgetRef ref, List<OrgMember> members) async {
    final l = AppLocalizations.of(context);
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
        builder: (ctx, setState) {
          final ld = AppLocalizations.of(ctx);
          return AlertDialog(
            title: Text(ld.requestChat),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ld.requestChatSubtitle,
                    style: const TextStyle(fontSize: 13, color: Colors.grey)),
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
                      Expanded(
                        child: Text(
                          ld.requestChatHint,
                          style: const TextStyle(fontSize: 12, color: Colors.blue),
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
                child: Text(ld.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(ld.requestChatButton),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed == true && selected != null) {
      try {
        await ref
            .read(chatServiceProvider)
            .requestConversation(org.id, selected!.uid);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.chatRequestSent)),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.errorMessage(e.toString()))),
          );
        }
      }
    }
  }

  Future<void> _showSuggestDialog(
      BuildContext context, WidgetRef ref, List<OrgMember> members) async {
    final l = AppLocalizations.of(context);
    final emailController = TextEditingController();
    OrgRole selectedRole = OrgRole.member;
    OrgMember? selectedGuardian;
    bool emailValid = false;

    final possibleGuardians = members
        .where((m) =>
            m.role != OrgRole.child && m.status == MemberStatus.active)
        .toList();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final ld = AppLocalizations.of(ctx);
          final roleLabels = {
            OrgRole.member: ld.roleMember,
            OrgRole.child: ld.roleChild,
          };
          return AlertDialog(
            title: Text(ld.suggestMemberTitle),
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
                      labelText: ld.emailAddress,
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.email_outlined),
                      errorText: emailController.text.isNotEmpty && !emailValid
                          ? ld.invalidEmailAddress
                          : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(ld.role,
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(ld.guardian,
                          style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ),
                    const SizedBox(height: 4),
                    if (possibleGuardians.isEmpty)
                      Text(
                        ld.noGuardiansAvailable,
                        style: const TextStyle(fontSize: 12, color: Colors.red),
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
                child: Text(ld.cancel),
              ),
              FilledButton(
                onPressed: (!emailValid ||
                        (selectedRole == OrgRole.child &&
                            selectedGuardian == null))
                    ? null
                    : () => Navigator.pop(ctx, true),
                child: Text(ld.suggest),
              ),
            ],
          );
        },
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
            SnackBar(
              content: Text(l.suggestionSent),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.errorMessage(e.toString()))),
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
    final l = AppLocalizations.of(context);
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
                      : l.roleMember,
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
                    SnackBar(content: Text(l.errorMessage(e.toString()))),
                  );
                }
              }
            },
            child: Text(l.reject),
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
                    SnackBar(content: Text(l.inviteSent)),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l.errorMessage(e.toString()))),
                  );
                }
              }
            },
            child: Text(l.accept),
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
    final l = AppLocalizations.of(context);
    final interval =
        ref.watch(orgMessageIntervalProvider(orgId)).value ??
            MessageAlertInterval.always;
    final muted = interval == MessageAlertInterval.never;

    return IconButton(
      icon: Icon(
        muted ? Icons.notifications_off_outlined : Icons.notifications_outlined,
        color: muted ? Colors.grey : null,
      ),
      tooltip: l.orgNotificationsTitle,
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
      builder: (ctx) {
        final ld = AppLocalizations.of(ctx);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  ld.orgNotificationsTitle,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
        );
      },
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
    final l = AppLocalizations.of(context);
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
                title: Text(l.archive),
                onTap: () { Navigator.pop(ctx); onArchive!(); },
              ),
            if (isArchived && onUnarchive != null)
              ListTile(
                leading: const Icon(Icons.unarchive_outlined),
                title: Text(l.restore),
                onTap: () { Navigator.pop(ctx); onUnarchive!(); },
              ),
            if (onDelete != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: Text(l.delete, style: const TextStyle(color: Colors.red)),
                onTap: () { Navigator.pop(ctx); onDelete!(); },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
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
          : Text(l.noMessages,
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
    final l = AppLocalizations.of(context);
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
      subtitle: Text(l.pendingApproval),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.check_circle_outline, color: Colors.green),
            tooltip: l.approveTooltip,
            onPressed: onApprove,
          ),
          IconButton(
            icon: const Icon(Icons.cancel_outlined, color: Colors.red),
            tooltip: l.rejectTooltip,
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

  String _roleLabel(OrgRole role, AppLocalizations l) => switch (role) {
        OrgRole.admin => l.roleAdmin,
        OrgRole.moderator => l.roleModerator,
        OrgRole.member => l.roleMember,
        OrgRole.child => l.roleChild,
      };

  Color _roleColor(OrgRole role) => switch (role) {
        OrgRole.admin => Colors.red,
        OrgRole.moderator => Colors.orange,
        OrgRole.member => Colors.blue,
        OrgRole.child => Colors.green,
      };

  void _showOptions(BuildContext context) {
    final l = AppLocalizations.of(context);
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
                title: Text(l.notificationSettings),
                onTap: () {
                  Navigator.pop(context);
                  _showAlertIntervalDialog(context);
                },
              ),
            if (isOwnTile)
              ListTile(
                leading: const Icon(Icons.exit_to_app, color: Colors.red),
                title: Text(l.leaveOrganization,
                    style: const TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _confirmLeave(context);
                },
              ),
            // Moderator: Guardians eines Kindes ändern
            if ((isMod || isAdmin) && !isOwnTile && member.role == OrgRole.child)
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: Text(l.changeGuardians),
                onTap: () {
                  Navigator.pop(context);
                  _showGuardiansDialog(context);
                },
              ),
            // Guardian: direkter Chat mit eigenem Kind (kein Approval nötig)
            if (!isAdmin && !isOwnTile && isGuardian)
              ListTile(
                leading: const Icon(Icons.chat_outlined),
                title: Text(l.startChat),
                onTap: () {
                  Navigator.pop(context);
                  _startAdminChat(context);
                },
              ),
            // Nicht-Admin im Guardian-Modus: Chat anfragen (für andere Mitglieder)
            if (!isAdmin && !isOwnTile && !isGuardian && org.chatMode == ChatMode.guardian)
              ListTile(
                leading: const Icon(Icons.chat_outlined),
                title: Text(l.requestChat),
                onTap: () {
                  Navigator.pop(context);
                  _requestChat(context);
                },
              ),
            // Admin: Chat starten, Rolle ändern, Admin übertragen, Entfernen
            if (isAdmin && !isOwnTile && member.role != OrgRole.admin) ...[
              ListTile(
                leading: const Icon(Icons.chat_outlined),
                title: Text(l.startChat),
                onTap: () {
                  Navigator.pop(context);
                  _startAdminChat(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: Text(l.changeRole),
                onTap: () {
                  Navigator.pop(context);
                  _showRoleDialog(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined,
                    color: Colors.orange),
                title: Text(l.transferAdmin,
                    style: const TextStyle(color: Colors.orange)),
                onTap: () {
                  Navigator.pop(context);
                  _confirmTransferAdmin(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.person_remove_outlined, color: Colors.red),
                title: Text(l.remove, style: const TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _confirmRemove(context);
                },
              ),
            ],
            if (!isOwnTile && !isGuardian && !isAdmin && !isMod)
              ListTile(
                title: Text(l.noActionsAvailable,
                    style: const TextStyle(color: Colors.grey)),
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
        builder: (ctx, setState) {
          final ld = AppLocalizations.of(ctx);
          return AlertDialog(
            title: Text(ld.guardiansFor(member.displayName)),
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
                child: Text(ld.cancel),
              ),
              FilledButton(
                onPressed: selected.isEmpty ? null : () => Navigator.pop(ctx, true),
                child: Text(ld.save),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed == true) {
      await ref.read(organizationServiceProvider).updateGuardians(
            org.id, member.uid, selected.toList());
    }
  }

  Future<void> _requestChat(BuildContext context) async {
    final l = AppLocalizations.of(context);
    try {
      await ref
          .read(chatServiceProvider)
          .requestConversation(org.id, member.uid);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.chatRequestSent)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.errorMessage(e.toString()))),
        );
      }
    }
  }

  Future<void> _startAdminChat(BuildContext context) async {
    final l = AppLocalizations.of(context);
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
          SnackBar(content: Text(l.errorMessage(e.toString()))),
        );
      }
    }
  }

  Future<void> _showRoleDialog(BuildContext context) async {
    OrgRole selected = member.role;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final ld = AppLocalizations.of(ctx);
          final roleLabels = {
            OrgRole.moderator: ld.roleModerator,
            OrgRole.member: ld.roleMember,
            OrgRole.child: ld.roleChild,
          };
          return AlertDialog(
            title: Text(ld.roleFor(member.displayName)),
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
                child: Text(ld.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(ld.save),
              ),
            ],
          );
        },
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
        builder: (ctx, setState) {
          final ld = AppLocalizations.of(ctx);
          return AlertDialog(
            title: Text(ld.guardianFor(member.displayName)),
            content: possibleGuardians.isEmpty
                ? Text(ld.noGuardiansInOrg)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        ld.selectGuardianHint,
                        style: const TextStyle(fontSize: 13),
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
                child: Text(ld.cancel),
              ),
              FilledButton(
                onPressed: possibleGuardians.isEmpty || selected.isNotEmpty
                    ? () => Navigator.pop(ctx, true)
                    : null,
                child: Text(ld.save),
              ),
            ],
          );
        },
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
      builder: (ctx) {
        final ld = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(ld.removeMemberTitle),
          content: Text(ld.removeMemberContent(member.displayName)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ld.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ld.remove),
            ),
          ],
        );
      },
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
      builder: (ctx) {
        final ld = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(ld.leaveOrgTitle),
          content: Text(ld.leaveOrgContent(org.name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ld.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ld.leave),
            ),
          ],
        );
      },
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
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final ld = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(ld.transferAdminTitle),
          content: Text(ld.transferAdminContent(member.displayName)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ld.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ld.transfer),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      try {
        await ref
            .read(organizationServiceProvider)
            .transferAdmin(org.id, member.uid);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.errorMessage(e.toString()))),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
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
          // Verified relationship indicator
          Builder(builder: (context) {
            final appUser = ref.watch(currentAppUserProvider).value;
            if (appUser == null) return const SizedBox.shrink();
            final isVerifiedChild =
                appUser.verifiedChildUids.contains(member.uid);
            final isVerifiedParent =
                appUser.verifiedParentUids.contains(member.uid);
            if (!isVerifiedChild && !isVerifiedParent) {
              return const SizedBox.shrink();
            }
            return Tooltip(
              message: isVerifiedChild ? l.verifiedChild : l.verifiedParent,
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.family_restroom,
                  size: 18,
                  color: isVerifiedChild ? Colors.green : Colors.blue,
                ),
              ),
            );
          }),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _roleColor(member.role).withAlpha(30),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _roleLabel(member.role, l),
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
        builder: (ctx, setState) {
          final ld = AppLocalizations.of(ctx);
          return AlertDialog(
            title: Text(ld.childActivityNotifications),
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
                child: Text(ld.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(ld.save),
              ),
            ],
          );
        },
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
    final l = AppLocalizations.of(context);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.amber.withAlpha(40),
        child: Icon(Icons.child_care, color: Colors.amber[800], size: 20),
      ),
      title: Text(child.displayName),
      subtitle: Text(
        '${child.email} · ${l.pendingChildSubtitle}',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.check_circle_outline, color: Colors.green),
            tooltip: l.approveChildTooltip,
            onPressed: () async {
              try {
                await ref
                    .read(organizationServiceProvider)
                    .approveChildInvite(org.id, child.uid);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content:
                            Text(l.memberAdded(child.displayName))),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(l.errorMessage(e.toString()))));
                }
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.cancel_outlined, color: Colors.red),
            tooltip: l.rejectTooltip,
            onPressed: () async {
              try {
                await ref
                    .read(organizationServiceProvider)
                    .rejectChildInvite(org.id, child.uid);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(l.errorMessage(e.toString()))));
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

// ── Pinnwand-Tab-Label mit Aktiv-Indikator ────────────────────────────────────

class _PinnwandTabLabel extends ConsumerWidget {
  final String orgId;
  const _PinnwandTabLabel({required this.orgId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final announcementsAsync = ref.watch(announcementsProvider(orgId));
    final hasActive = announcementsAsync.value?.any(
          (a) => !a.isExpired,
        ) ??
        false;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: EdgeInsets.only(right: hasActive ? 8 : 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.campaign_outlined, size: 24),
              Text(l.tabPinboard, style: const TextStyle(fontSize: 10)),
            ],
          ),
        ),
        if (hasActive)
          Positioned(
            right: 0,
            top: -2,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }
}

class _ReportsTabLabel extends ConsumerWidget {
  final String orgId;
  const _ReportsTabLabel({required this.orgId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final reportsAsync = ref.watch(_pendingReportsCountProvider(orgId));
    final count = reportsAsync.value ?? 0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: EdgeInsets.only(right: count > 0 ? 8 : 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.flag_outlined, size: 24),
              Text(l.tabReports, style: const TextStyle(fontSize: 10)),
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
    final l = AppLocalizations.of(context);
    final reportsAsync = ref.watch(_orgReportsProvider(widget.org.id));

    return reportsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(l.errorMessage(e.toString()))),
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
                            ? l.hideArchived
                            : l.showArchived(archived.length),
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
                            ? l.noReports
                            : l.noPendingReports,
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
                                isPending ? l.reportPending : l.reportReviewed,
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
                                PopupMenuItem(
                                  value: 'reviewed',
                                  child: ListTile(
                                    leading: const Icon(
                                        Icons.check_circle_outline,
                                        color: Colors.green),
                                    title: Text(l.markReviewed),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              PopupMenuItem(
                                value: 'delete_msg',
                                child: ListTile(
                                  leading: const Icon(Icons.delete_outline,
                                      color: Colors.red),
                                  title: Text(l.deleteMessage,
                                      style: const TextStyle(color: Colors.red)),
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
      builder: (ctx) {
        final ld = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(ld.deleteMessage),
          content: Text(ld.deleteMessageContent),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(ld.cancel)),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ld.delete),
            ),
          ],
        );
      },
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
    final l = AppLocalizations.of(context);
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
        tooltip: l.withdrawInvitationTitle,
        onPressed: () async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) {
              final ld = AppLocalizations.of(ctx);
              return AlertDialog(
                title: Text(ld.withdrawInvitationTitle),
                content: Text(ld.withdrawInvitationContent(email)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(ld.cancel),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(ld.withdraw),
                  ),
                ],
              );
            },
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

// ── Pinnwand ──────────────────────────────────────────────────────────────────

class _PinnwandTab extends ConsumerWidget {
  final String orgId;
  final bool canManage;

  const _PinnwandTab({required this.orgId, required this.canManage});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final announcementsAsync = ref.watch(announcementsProvider(orgId));

    return announcementsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(l.errorMessage(e.toString()))),
      data: (items) => Stack(
        children: [
          items.isEmpty
              ? Center(
                  child: Text(l.noAnnouncements,
                      style: const TextStyle(color: Colors.grey)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _AnnouncementCard(
                    announcement: items[i],
                    orgId: orgId,
                    canManage: canManage,
                  ),
                ),
          if (canManage)
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.extended(
                heroTag: 'pinnwand_fab',
                icon: const Icon(Icons.add),
                label: Text(l.newAnnouncement),
                onPressed: () => _showEditDialog(context, ref, null),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showEditDialog(
      BuildContext context, WidgetRef ref, Announcement? existing) async {
    final l = AppLocalizations.of(context);
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final contentCtrl = TextEditingController(text: existing?.content ?? '');
    DateTime? expiresAt = existing?.expiresAt;
    bool clearExpiry = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final ld = AppLocalizations.of(ctx);
          final expLabel = expiresAt == null
              ? ld.announcementNoExpiry
              : '${ld.announcementSetExpiry}: '
                  '${expiresAt!.day.toString().padLeft(2, '0')}.'
                  '${expiresAt!.month.toString().padLeft(2, '0')}.'
                  '${expiresAt!.year}';
          return AlertDialog(
            title: Text(existing == null ? ld.newAnnouncement : ld.editAnnouncement),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleCtrl,
                    autofocus: true,
                    maxLength: 120,
                    decoration: InputDecoration(
                      labelText: ld.announcementTitleLabel,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: contentCtrl,
                    maxLines: 5,
                    maxLength: 2000,
                    decoration: InputDecoration(
                      labelText: ld.announcementContentLabel,
                      border: const OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.event_outlined, size: 16),
                          label: Text(expLabel,
                              style: const TextStyle(fontSize: 13)),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: expiresAt ??
                                  DateTime.now().add(const Duration(days: 7)),
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now()
                                  .add(const Duration(days: 365)),
                            );
                            if (picked != null) {
                              setS(() {
                                expiresAt = picked;
                                clearExpiry = false;
                              });
                            }
                          },
                        ),
                      ),
                      if (expiresAt != null)
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          tooltip: ld.announcementRemoveExpiry,
                          onPressed: () => setS(() {
                            expiresAt = null;
                            clearExpiry = true;
                          }),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(ld.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(existing == null ? ld.create : ld.save),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true || !context.mounted) return;
    final title = titleCtrl.text.trim();
    final content = contentCtrl.text.trim();
    if (title.isEmpty || content.isEmpty) return;

    try {
      final service = ref.read(organizationServiceProvider);
      if (existing == null) {
        await service.createAnnouncement(orgId, title, content,
            expiresAt: expiresAt);
      } else {
        await service.editAnnouncement(orgId, existing.id, title, content,
            expiresAt: expiresAt, clearExpiry: clearExpiry);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.errorMessage(e.toString()))),
        );
      }
    }
  }
}

class _AnnouncementCard extends ConsumerWidget {
  final Announcement announcement;
  final String orgId;
  final bool canManage;

  const _AnnouncementCard({
    required this.announcement,
    required this.orgId,
    required this.canManage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    final isExpired = announcement.isExpired;

    return Card(
      margin: EdgeInsets.zero,
      color: isExpired
          ? colorScheme.surfaceContainerHighest.withAlpha(180)
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.campaign_outlined,
                    size: 18,
                    color: isExpired
                        ? colorScheme.onSurfaceVariant
                        : colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    announcement.title,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: isExpired
                            ? colorScheme.onSurfaceVariant
                            : null),
                  ),
                ),
                if (canManage)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 18),
                    onSelected: (value) async {
                      if (value == 'edit') {
                        if (context.mounted) {
                          await _PinnwandTab(
                                  orgId: orgId, canManage: canManage)
                              ._showEditDialog(context, ref, announcement);
                        }
                      } else if (value == 'delete') {
                        await _confirmDelete(context, ref);
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          leading: const Icon(Icons.edit_outlined),
                          title: Text(l.edit),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading:
                              const Icon(Icons.delete_outline, color: Colors.red),
                          title: Text(l.delete,
                              style: const TextStyle(color: Colors.red)),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              announcement.content,
              style: TextStyle(
                  color: isExpired ? colorScheme.onSurfaceVariant : null),
            ),
            if (announcement.expiresAt != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    isExpired
                        ? Icons.event_busy_outlined
                        : Icons.event_available_outlined,
                    size: 12,
                    color: isExpired ? Colors.red[400] : Colors.green[600],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isExpired
                        ? l.announcementExpired
                        : l.announcementExpiresOn(
                            '${announcement.expiresAt!.day.toString().padLeft(2, '0')}.'
                            '${announcement.expiresAt!.month.toString().padLeft(2, '0')}.'
                            '${announcement.expiresAt!.year}'),
                    style: TextStyle(
                      fontSize: 11,
                      color: isExpired ? Colors.red[400] : Colors.green[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.person_outline,
                    size: 12, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Text(
                  l.announcementBy(announcement.authorName),
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
                const Spacer(),
                if (announcement.updatedAt != null) ...[
                  Text(
                    '${l.announcementEdited} · ',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[500],
                        fontStyle: FontStyle.italic),
                  ),
                ],
                Text(
                  _formatDate(announcement.updatedAt ?? announcement.createdAt),
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final ld = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(ld.deleteAnnouncementTitle),
          content: Text(ld.deleteAnnouncementContent),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ld.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ld.delete),
            ),
          ],
        );
      },
    );
    if (confirmed == true && context.mounted) {
      try {
        await ref
            .read(organizationServiceProvider)
            .deleteAnnouncement(orgId, announcement.id);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.errorMessage(e.toString()))),
          );
        }
      }
    }
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
  }
}
