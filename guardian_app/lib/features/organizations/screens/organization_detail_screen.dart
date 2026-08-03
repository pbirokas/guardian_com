import 'dart:async';
import 'dart:io';

import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:guardian_app/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/models/announcement.dart';
import '../../../core/models/org_audit_entry.dart';
import '../../../core/models/app_user.dart';
import '../../../core/dialogs/edit_group_dialog.dart';
import '../../../core/widgets/group_avatar.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../core/utils/initials.dart';
import '../../../core/widgets/help_sheet.dart';
import '../../../core/models/conversation.dart';
import '../../../core/models/member_suggestion.dart';
import '../../../core/models/notification_settings.dart';
import '../../../core/models/org_member.dart';

import '../../../core/models/organization.dart';
import '../../auth/providers/auth_provider.dart';
import '../../chat/providers/chat_provider.dart';
import '../providers/organizations_provider.dart';
import 'bulk_import_screen.dart';

class OrganizationDetailScreen extends ConsumerStatefulWidget {
  final String orgId;

  const OrganizationDetailScreen({super.key, required this.orgId});

  @override
  ConsumerState<OrganizationDetailScreen> createState() =>
      _OrganizationDetailScreenState();
}

class _OrganizationDetailScreenState
    extends ConsumerState<OrganizationDetailScreen> {
  // ── Tour GlobalKeys ────────────────────────────────────────────────────────
  final _tourNotifKey    = GlobalKey();
  final _tourMenuKey     = GlobalKey();
  final _tourMembersKey  = GlobalKey();
  final _tourChatKey     = GlobalKey();
  final _tourPinnwandKey = GlobalKey();
  final _tourReportsKey  = GlobalKey();

  // Periodisch Members neu laden: Realtime-Events von API-Key-Operationen
  // (z.B. process-my-invitations) kommen auf manchen Geräten nicht zuverlässig
  // an. Ohne diesen Timer bleibt die Mitgliederliste veraltet bis zum Neustart.
  Timer? _membersRefreshTimer;

  String get orgId => widget.orgId;

  @override
  void initState() {
    super.initState();
    _membersRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) ref.invalidate(orgMembersProvider(orgId));
    });
  }

  @override
  void dispose() {
    _membersRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final orgAsync = ref.watch(organizationProvider(orgId));
    final currentUid = ref.read(authStateProvider).value!.uid;

    final membersAsync = ref.watch(orgMembersProvider(orgId));

    return orgAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) {
        // Org wurde gelöscht oder ist nicht mehr zugänglich → zurück zur Liste.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) context.pop();
        });
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
      data: (org) {
        final isAdmin = org.adminUid == currentUid;
        final currentMember = membersAsync.value
            ?.where((m) => m.uid == currentUid)
            .firstOrNull;
        final isModerator =
            !isAdmin && currentMember?.role == OrgRole.moderator;

        final isChild = currentMember?.role == OrgRole.child;
        final isGuardian = !isAdmin && !isModerator && !isChild;

        final tabCount = (isAdmin || isModerator) ? 4 : 3;
        return ShowCaseWidget(
          builder: (innerCtx) {
            void startTour() {
              final keys = [
                if (isAdmin || isModerator) _tourMembersKey,
                if (isAdmin || isModerator) _tourMenuKey,
                _tourChatKey,
                _tourPinnwandKey,
                if (isAdmin || isModerator) _tourReportsKey,
                _tourNotifKey,
              ];
              ShowCaseWidget.of(innerCtx).startShowCase(keys);
            }

            return DefaultTabController(
              length: tabCount,
              initialIndex: 1,
              child: Scaffold(
                appBar: AppBar(
                  toolbarHeight: kToolbarHeight + 16,
                  title: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(org.name),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(org.tag.icon, size: 12, color: org.tag.color),
                            const SizedBox(width: 4),
                            Text(
                              org.tag.localizedLabel(l),
                              style: TextStyle(fontSize: 12, color: org.tag.color),
                            ),
                            const SizedBox(width: 8),
                            Icon(Icons.timer_outlined, size: 12, color: Colors.grey[500]),
                            const SizedBox(width: 2),
                            Text(
                              l.orgRetentionDays(org.messageRetentionDays),
                              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    Showcase(
                      key: _tourNotifKey,
                      title: l.tourOrgNotifTitle,
                      description: l.tourOrgNotifDesc,
                      child: _OrgNotificationToggle(orgId: orgId),
                    ),
                    _OrgHelpButton(
                      orgId: orgId,
                      onTap: () => _showHelp(
                        innerCtx, org, startTour,
                        isAdmin: isAdmin,
                        isModerator: isModerator,
                      ),
                    ),
                    if (isAdmin || isModerator)
                      Showcase(
                        key: _tourMenuKey,
                        title: l.tourOrgMenuTitle,
                        description: l.tourOrgMenuDesc,
                        child: PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert),
                          onSelected: (value) {
                            switch (value) {
                              case 'keywords':
                                _showKeywordsDialog(context, ref, org);
                              case 'edit':
                                _showEditDialog(context, ref, org);
                              case 'auditLog':
                                showModalBottomSheet<void>(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor: Colors.transparent,
                                  builder: (_) => _AuditLogSheet(orgId: orgId),
                                );
                            }
                          },
                          itemBuilder: (_) => [
                            if (isAdmin || isModerator) ...[
                              PopupMenuItem(
                                value: 'auditLog',
                                child: ListTile(
                                  leading: const Icon(Icons.history_outlined),
                                  title: Text(l.auditLog),
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                ),
                              ),
                            ],
                            if (isAdmin) ...[
                              PopupMenuItem(
                                value: 'keywords',
                                child: ListTile(
                                  leading: const Icon(Icons.manage_search_outlined),
                                  title: Text(l.keywordsTooltip),
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                ),
                              ),
                              PopupMenuItem(
                                value: 'edit',
                                child: ListTile(
                                  leading: const Icon(Icons.edit_outlined),
                                  title: Text(l.editTooltip),
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                  bottom: TabBar(
                    labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                    tabs: [
                      Showcase(
                        key: _tourMembersKey,
                        title: l.tourOrgMembersTitle,
                        description: l.tourOrgMembersDesc,
                        child: Tab(
                          icon: const Icon(Icons.people_outline),
                          text: l.tabMembers,
                        ),
                      ),
                      Showcase(
                        key: _tourChatKey,
                        title: isGuardian
                            ? l.tourOrgGuardianChatTitle
                            : l.tourOrgChatTitle,
                        description: isGuardian
                            ? l.tourOrgGuardianChatDesc
                            : l.tourOrgChatDesc,
                        child: Tab(
                          child: _ChatTabLabel(
                            orgId: orgId,
                            isAdminOrMod: isAdmin || isModerator,
                          ),
                        ),
                      ),
                      Showcase(
                        key: _tourPinnwandKey,
                        title: l.tourOrgPinnwandTitle,
                        description: l.tourOrgPinnwandDesc,
                        child: Tab(child: _PinnwandTabLabel(orgId: orgId)),
                      ),
                      if (isAdmin || isModerator)
                        Showcase(
                          key: _tourReportsKey,
                          title: l.tourOrgReportsTitle,
                          description: l.tourOrgReportsDesc,
                          child: Tab(child: _ReportsTabLabel(orgId: orgId)),
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
                    _PinnwandTab(orgId: orgId, canManage: isAdmin || isModerator),
                    if (isAdmin || isModerator) _ReportsTab(org: org),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showHelp(
    BuildContext innerCtx,
    Organization org,
    VoidCallback startTour, {
    required bool isAdmin,
    required bool isModerator,
  }) {
    final l = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: innerCtx,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => HelpSheet(
        screenTitle: org.name,
        topics: [
          HelpTopic(
            icon: Icons.people_outline,
            title: l.helpDetailTopicMembersTitle,
            body: l.helpDetailTopicMembersBody,
          ),
          HelpTopic(
            icon: Icons.person_add_outlined,
            title: l.helpDetailTopicMembersInviteTitle,
            body: l.helpDetailTopicMembersInviteBody,
          ),
          HelpTopic(
            icon: Icons.notifications_outlined,
            title: l.helpDetailTopicNotificationsTitle,
            body: l.helpDetailTopicNotificationsBody,
          ),
          HelpTopic(
            icon: Icons.chat_bubble_outline,
            title: l.helpDetailTopicChatsSendTitle,
            body: l.helpDetailTopicChatsSendBody,
          ),
          HelpTopic(
            icon: Icons.shield_outlined,
            title: l.helpDetailTopicChatsModTitle,
            body: l.helpDetailTopicChatsModBody,
          ),
          HelpTopic(
            icon: Icons.campaign_outlined,
            title: l.helpDetailTopicPinnwandTitle,
            body: l.helpDetailTopicPinnwandBody,
          ),
          if (isAdmin || isModerator) ...[
            HelpTopic(
              icon: Icons.edit_calendar_outlined,
              title: l.helpDetailTopicPinnwandManageTitle,
              body: l.helpDetailTopicPinnwandManageBody,
            ),
            HelpTopic(
              icon: Icons.flag_outlined,
              title: l.helpDetailTopicReportsTitle,
              body: l.helpDetailTopicReportsBody,
            ),
          ],
        ],
        onStartTour: () {
          Navigator.pop(innerCtx);
          Future.delayed(const Duration(milliseconds: 350), startTour);
        },
      ),
    );
  }

  Future<void> _showEditDialog(
      BuildContext context, WidgetRef ref, Organization org) async {
    final l = AppLocalizations.of(context);
    final nameController = TextEditingController(text: org.name);
    OrgTag selectedTag = org.tag;
    int selectedRetention = org.messageRetentionDays;
    const retentionOptions = [30, 60, 90, 180, 365];

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
                        label: Text(tag.localizedLabel(ld)),
                        selected: selected,
                        selectedColor: tag.color,
                        labelStyle:
                            TextStyle(color: selected ? Colors.white : null),
                        onSelected: (_) => setState(() => selectedTag = tag),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Text(ld.orgRetentionSectionTitle,
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: retentionOptions.map((days) {
                      final selected = selectedRetention == days;
                      return ChoiceChip(
                        label: Text(ld.orgRetentionDays(days)),
                        selected: selected,
                        onSelected: (_) =>
                            setState(() => selectedRetention = days),
                      );
                    }).toList(),
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
              messageRetentionDays: selectedRetention,
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
                  icon: const Icon(Icons.help_outline),
                  tooltip: ld.helpLabel,
                  onPressed: () => showDialog<void>(
                    context: ctx,
                    builder: (hCtx) {
                      final lh = AppLocalizations.of(hCtx);
                      return AlertDialog(
                        title: Text(lh.keywordsHelpTitle),
                        content: SingleChildScrollView(
                          child: Text(
                            lh.keywordsHelpBody,
                            style: const TextStyle(height: 1.6),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(hCtx),
                            child: Text(lh.close),
                          ),
                        ],
                      );
                    },
                  ),
                ),
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

class _ChatsTab extends ConsumerStatefulWidget {
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
  ConsumerState<_ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends ConsumerState<_ChatsTab> {
  bool _supervisedExpanded = true;
  Timer? _refreshTimer;

  Organization get org => widget.org;
  String get currentUid => widget.currentUid;
  bool get isAdmin => widget.isAdmin;
  bool get isModerator => widget.isModerator;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) => _refresh());
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  void _refresh() {
    if (!mounted) return;
    ref.invalidate(orgConversationsProvider(org.id));
    ref.invalidate(adminConversationsProvider(org.id));
    ref.invalidate(pendingRequestsProvider(org.id));
    ref.invalidate(moderatorPendingRequestsProvider(org.id));
    ref.invalidate(guardianPendingRequestsProvider(org.id));
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  SliverToBoxAdapter _buildSectionLabel(BuildContext context, String label) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
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
    final shelteredModConvsAsync = isModerator
        ? ref.watch(shelteredModeratorConversationsProvider(
            (orgId: org.id, adminUid: org.adminUid)))
        : const AsyncData(<Conversation>[]);
    final membersAsync = ref.watch(orgMembersProvider(org.id));

    return convsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(l.errorMessage(e.toString()))),
      data: (convs) {
        // Nur Conversations wo der User selbst Teilnehmer ist → reguläre Liste.
        // Nicht-Teilnehmer-Chats (z. B. Admin-Oversight in Sheltered-Gruppen)
        // landen über supervisorConvs in allSupervisorConvs.
        final approved = convs
            .where((c) =>
                c.status == ConversationStatus.approved &&
                c.participantUids.contains(currentUid))
            .toList();
        final approvedGroups =
            approved.where((c) => c.isGroup).toList();
        final approvedDirect =
            approved.where((c) => !c.isGroup).toList();
        final archivedConvs = convs
            .where((c) =>
                c.status == ConversationStatus.archived &&
                c.participantUids.contains(currentUid))
            .toList();
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
        final approvedIds = approved.map((c) => c.id).toSet();

        // Admin: alle genehmigten Conversations wo er kein Teilnehmer ist
        // als Oversight-Chats behandeln (Fallback für ältere Daten, bei denen
        // canApproveUids evtl. nicht den Admin enthält).
        final adminOversightConvs = isAdmin
            ? convs
                .where((c) =>
                    c.status == ConversationStatus.approved &&
                    !c.participantUids.contains(currentUid))
                .toList()
            : <Conversation>[];

        // Deduplizieren über eine Map: neuere Einträge aus spezifischeren
        // Quellen überschreiben ältere aus dem allgemeinen Admin-Query.
        final supervisorMap = <String, Conversation>{
          for (final c in adminOversightConvs) c.id: c,
          for (final c in supervisorConvs) c.id: c,
          for (final c in guardianSupervisorConvs) c.id: c,
          for (final c in shelteredModConvs) c.id: c,
        };
        final allSupervisorConvs = supervisorMap.values
            .where((c) => !approvedIds.contains(c.id))
            .toList()
          ..sort((a, b) {
            if (a.lastMessageAt == null) return 1;
            if (b.lastMessageAt == null) return -1;
            return b.lastMessageAt!.compareTo(a.lastMessageAt!);
          });

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
                                onApprove: () async {
                                  await ref.read(chatServiceProvider).approveConversation(conv.id);
                                  ref.invalidate(guardianPendingRequestsProvider(org.id));
                                  ref.invalidate(orgConversationsProvider(org.id));
                                  ref.invalidate(adminConversationsProvider(org.id));
                                },
                                onReject: () async {
                                  await ref.read(chatServiceProvider).rejectConversation(conv.id);
                                  ref.invalidate(guardianPendingRequestsProvider(org.id));
                                },
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
                                onApprove: () async {
                                  await ref.read(chatServiceProvider).approveConversation(conv.id);
                                  ref.invalidate(moderatorPendingRequestsProvider(org.id));
                                  ref.invalidate(orgConversationsProvider(org.id));
                                  ref.invalidate(adminConversationsProvider(org.id));
                                },
                                onReject: () async {
                                  await ref.read(chatServiceProvider).rejectConversation(conv.id);
                                  ref.invalidate(moderatorPendingRequestsProvider(org.id));
                                },
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
                                    onApprove: () async {
                                      await ref.read(chatServiceProvider).approveConversation(conv.id);
                                      ref.invalidate(pendingRequestsProvider(org.id));
                                      ref.invalidate(orgConversationsProvider(org.id));
                                      ref.invalidate(adminConversationsProvider(org.id));
                                    },
                                    onReject: () async {
                                      await ref.read(chatServiceProvider).rejectConversation(conv.id);
                                      ref.invalidate(pendingRequestsProvider(org.id));
                                    },
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
                                ref: ref,
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
                            l.noChatsGuardian,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  )
                else ...[
                  // Gruppen
                  if (approvedGroups.isNotEmpty) ...[
                    _buildSectionLabel(context, l.sectionGroups),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) => membersAsync.maybeWhen(
                          data: (members) => _ConversationTile(
                            conv: approvedGroups[i],
                            members: members,
                            currentUid: currentUid,
                            ref: ref,
                            isAdminOrMod: isAdmin || isModerator,
                            onArchive: (isAdmin || isModerator)
                                ? () => ref.read(chatServiceProvider).archiveConversation(approvedGroups[i].id)
                                : null,
                            onDelete: (isAdmin || isModerator)
                                ? () => ref.read(chatServiceProvider).deleteConversation(approvedGroups[i].id)
                                : null,
                          ),
                          orElse: () => const SizedBox(),
                        ),
                        childCount: approvedGroups.length,
                      ),
                    ),
                  ],
                  // Einzel-Chats
                  if (approvedDirect.isNotEmpty) ...[
                    _buildSectionLabel(context, l.sectionDirectChats),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) => membersAsync.maybeWhen(
                          data: (members) => _ConversationTile(
                            conv: approvedDirect[i],
                            members: members,
                            currentUid: currentUid,
                            ref: ref,
                            isAdminOrMod: isAdmin || isModerator,
                            onArchive: (isAdmin || isModerator)
                                ? () => ref.read(chatServiceProvider).archiveConversation(approvedDirect[i].id)
                                : null,
                            onDelete: (isAdmin || isModerator)
                                ? () => ref.read(chatServiceProvider).deleteConversation(approvedDirect[i].id)
                                : null,
                          ),
                          orElse: () => const SizedBox(),
                        ),
                        childCount: approvedDirect.length,
                      ),
                    ),
                  ],
                  // Überwachte Chats (für Moderatoren + Guardians)
                  if (allSupervisorConvs.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: InkWell(
                        onTap: () => setState(
                            () => _supervisedExpanded = !_supervisedExpanded),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
                          child: Row(
                            children: [
                              Icon(Icons.visibility_outlined,
                                  size: 14,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant),
                              const SizedBox(width: 6),
                              Text(
                                l.monitoredChats(allSupervisorConvs.length),
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.bold),
                              ),
                              const Spacer(),
                              Icon(
                                _supervisedExpanded
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                size: 18,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_supervisedExpanded)
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (ctx, i) => membersAsync.maybeWhen(
                            data: (members) => _ConversationTile(
                              conv: allSupervisorConvs[i],
                              members: members,
                              currentUid: currentUid,
                              ref: ref,
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
                                size: 14,
                                color: Theme.of(context).colorScheme.onSurfaceVariant),
                            const SizedBox(width: 6),
                            Text(
                              l.archivedChats(archivedConvs.length),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                            ref: ref,
                            isAdminOrMod: isAdmin || isModerator,
                            onUnarchive: (isAdmin || isModerator)
                                ? () async {
                                    await ref.read(chatServiceProvider).approveConversation(archivedConvs[i].id);
                                    ref.invalidate(orgConversationsProvider(org.id));
                                    ref.invalidate(adminConversationsProvider(org.id));
                                  }
                                : null,
                            onDelete: (isAdmin || isModerator)
                                ? () async {
                                    await ref.read(chatServiceProvider).deleteConversation(archivedConvs[i].id);
                                    ref.invalidate(orgConversationsProvider(org.id));
                                    ref.invalidate(adminConversationsProvider(org.id));
                                  }
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
            // FAB für Admin/Moderator: Gruppe erstellen
            if (isAdmin || isModerator)
              Positioned(
                bottom: 16 + MediaQuery.of(context).padding.bottom,
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
  final currentUid = ref.read(authStateProvider).value?.uid;
  // Auswählbar sind alle außer dem Org-Admin — der Ersteller selbst ist aber
  // immer dabei (damit er sich in die eigene Gruppe aufnehmen kann) und
  // standardmäßig vorausgewählt.
  final selectableMembers = members
      .where((m) => m.uid != org.adminUid || m.uid == currentUid)
      .toList();
  final selected = <String>{?currentUid};

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
                ...selectableMembers.map((m) => CheckboxListTile(
                      value: selected.contains(m.uid),
                      onChanged: (v) => setState(() =>
                          v == true ? selected.add(m.uid) : selected.remove(m.uid)),
                      title: Text(m.displayName),
                      subtitle: Text(m.email,
                          style: const TextStyle(fontSize: 12)),
                      secondary: UserAvatar(
                        radius: 16,
                        photoUrl: m.photoUrl,
                        fallbackText: initialsFor(m.displayName),
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

  const _ChatTabLabel({required this.orgId, required this.isAdminOrMod});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final pendingCount = isAdminOrMod
        ? (ref.watch(pendingRequestsProvider(orgId)).value?.length ?? 0)
        : 0;

    // Ungelesene eigene Chats — dieselbe Zählung wie das Org-Badge auf dem
    // Startbildschirm; nicht doppelt implementieren.
    final unreadCount = ref.watch(unreadOrgCountProvider(orgId));

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
        // Ungelesene eigene Chats — Zahl in Primärfarbe (rechts).
        if (unreadCount > 0)
          _countBadge(unreadCount, Theme.of(context).colorScheme.primary,
              left: false),
        // Offene Anfragen (nur Admin/Mod) — eigenes rotes Badge (links),
        // getrennt vom Ungelesen-Zähler, damit die Zahl eindeutig bleibt.
        if (pendingCount > 0) _countBadge(pendingCount, Colors.red, left: true),
      ],
    );
  }

  /// Kleines Zähler-Badge in der Ecke des Tab-Icons (links = Anfragen,
  /// rechts = Ungelesene).
  static Widget _countBadge(int count, Color color, {required bool left}) {
    return Positioned(
      top: -4,
      left: left ? -10 : null,
      right: left ? null : -10,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Text('$count',
            style: const TextStyle(
                fontSize: 10,
                color: Colors.white,
                fontWeight: FontWeight.bold)),
      ),
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
        final currentUid = ref.read(authStateProvider).value!.uid;
        final currentMember =
            members.where((m) => m.uid == currentUid).firstOrNull;
        final fabBottom = 16.0 + MediaQuery.of(context).padding.bottom;
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
                                  currentUid: ref.read(authStateProvider).value!.uid,
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
              bottom: fabBottom,
              right: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (isAdmin)
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
                        _showInviteDialog(context, widgetRef, members, isAdmin: isAdmin),
                    icon: const Icon(Icons.person_add_outlined),
                    label: Text(l.inviteMember),
                  ),
                ],
              ),
            ),
          if (isRegularMember)
            Positioned(
              bottom: fabBottom,
              right: 16,
              child: FloatingActionButton.extended(
                heroTag: 'suggest',
                onPressed: () =>
                    _showSuggestDialog(context, widgetRef, members),
                icon: const Icon(Icons.person_add_outlined),
                label: Text(l.suggestMember),
              ),
            ),
          if (!isAdmin && !isModerator && !isRegularMember)
            Positioned(
              bottom: fabBottom,
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
      BuildContext context, WidgetRef ref, List<OrgMember> members,
      {bool isAdmin = false}) async {
    final l = AppLocalizations.of(context);
    final emailController = TextEditingController();
    OrgRole selectedRole = OrgRole.member;
    final selectedGuardians = <OrgMember>{};
    bool emailValid = false;

    // Address book state
    int tabIndex = 0;
    Future<List<OrgMember>>? addressBookFuture;
    List<OrgMember> addressBookEntries = [];
    final Set<String> abSelected = {};
    final Map<String, OrgRole> abRoles = {};
    final Map<String, Set<String>> abGuardians = {};

    final possibleGuardians = members
        .where((m) => m.role != OrgRole.child && m.status == MemberStatus.active)
        .toList();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final ld = AppLocalizations.of(ctx);
          final roleLabels = {
            if (isAdmin) OrgRole.moderator: ld.roleModerator,
            OrgRole.member: ld.roleMember,
            OrgRole.child: ld.roleChild,
          };

          // ── Tab selector ────────────────────────────────────────────────
          Widget tabSelector() {
            final primary = Theme.of(ctx).colorScheme.primary;
            return Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => tabIndex = 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: tabIndex == 0 ? primary : Colors.grey.shade300,
                            width: tabIndex == 0 ? 2 : 1,
                          ),
                        ),
                      ),
                      child: Text(ld.emailTab,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: tabIndex == 0 ? FontWeight.bold : FontWeight.normal,
                            color: tabIndex == 0 ? primary : null,
                          )),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() {
                      tabIndex = 1;
                      addressBookFuture ??= ref
                          .read(organizationServiceProvider)
                          .getAddressBook(org.id);
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: tabIndex == 1 ? primary : Colors.grey.shade300,
                            width: tabIndex == 1 ? 2 : 1,
                          ),
                        ),
                      ),
                      child: Text(ld.addressBookTab,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: tabIndex == 1 ? FontWeight.bold : FontWeight.normal,
                            color: tabIndex == 1 ? primary : null,
                          )),
                    ),
                  ),
                ),
              ],
            );
          }

          // ── Email tab content ────────────────────────────────────────────
          final emailContent = SingleChildScrollView(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: emailController,
                  autofocus: tabIndex == 0,
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
                Text(ld.role,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 8),
                SegmentedButton<OrgRole>(
                  segments: roleLabels.entries
                      .map((e) => ButtonSegment(value: e.key, label: Text(e.value)))
                      .toList(),
                  selected: {selectedRole},
                  onSelectionChanged: (s) => setState(() {
                    selectedRole = s.first;
                    if (selectedRole != OrgRole.child) selectedGuardians.clear();
                  }),
                ),
                if (selectedRole == OrgRole.child) ...[
                  const SizedBox(height: 16),
                  Text(ld.guardians,
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
                        Icon(Icons.info_outline, size: 14, color: Colors.amber[800]),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(ld.childGuardianHint,
                              style: TextStyle(fontSize: 11, color: Colors.amber[900])),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (possibleGuardians.isEmpty)
                    Text(ld.noGuardiansAvailable,
                        style: const TextStyle(fontSize: 12, color: Colors.red))
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
          );

          // ── Address book tab content ─────────────────────────────────────
          Widget addressBookContent() {
            if (addressBookFuture == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return FutureBuilder<List<OrgMember>>(
              future: addressBookFuture,
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text(ld.errorMessage(snap.error.toString())));
                }
                final entries = snap.data ?? [];
                addressBookEntries = entries;
                if (entries.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(ld.addressBookEmpty,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.grey)),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (ctx, i) {
                    final entry = entries[i];
                    final isSelected = abSelected.contains(entry.uid);
                    final entryRole = abRoles[entry.uid] ?? OrgRole.member;
                    final entryGuardians = abGuardians.putIfAbsent(entry.uid, () => {});
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CheckboxListTile(
                          value: isSelected,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                          title: Text(entry.displayName),
                          subtitle: entry.hideEmail
                              ? Row(children: [
                                  Icon(Icons.no_accounts_outlined,
                                      size: 12, color: Colors.grey[500]),
                                  const SizedBox(width: 4),
                                  Text(ld.emailHidden,
                                      style: TextStyle(
                                          fontSize: 11, color: Colors.grey[500])),
                                ])
                              : Text(entry.email,
                                  style: const TextStyle(fontSize: 11)),
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              abSelected.add(entry.uid);
                            } else {
                              abSelected.remove(entry.uid);
                              abRoles.remove(entry.uid);
                              abGuardians.remove(entry.uid);
                            }
                          }),
                        ),
                        if (isSelected) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                            child: SegmentedButton<OrgRole>(
                              style: SegmentedButton.styleFrom(
                                  textStyle: const TextStyle(fontSize: 11)),
                              segments: roleLabels.entries
                                  .map((e) => ButtonSegment(
                                        value: e.key,
                                        label: Text(e.value),
                                      ))
                                  .toList(),
                              selected: {entryRole},
                              onSelectionChanged: (s) => setState(() {
                                abRoles[entry.uid] = s.first;
                                if (s.first != OrgRole.child) {
                                  abGuardians[entry.uid]?.clear();
                                }
                              }),
                            ),
                          ),
                          if (entryRole == OrgRole.child) ...[
                            if (possibleGuardians.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                child: Text(ld.noGuardiansAvailable,
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.red)),
                              )
                            else
                              ...possibleGuardians.map((g) => CheckboxListTile(
                                    value: entryGuardians.contains(g.uid),
                                    title: Text(g.displayName,
                                        style: const TextStyle(fontSize: 12)),
                                    secondary: const Icon(Icons.shield_outlined,
                                        size: 18),
                                    contentPadding:
                                        const EdgeInsets.symmetric(horizontal: 8),
                                    dense: true,
                                    onChanged: (v) => setState(() {
                                      if (v == true) {
                                        entryGuardians.add(g.uid);
                                      } else {
                                        entryGuardians.remove(g.uid);
                                      }
                                    }),
                                  )),
                          ],
                          const Divider(height: 8),
                        ],
                      ],
                    );
                  },
                );
              },
            );
          }

          // ── Can confirm? ─────────────────────────────────────────────────
          bool canConfirm() {
            if (tabIndex == 0) {
              return emailValid &&
                  (selectedRole != OrgRole.child || selectedGuardians.isNotEmpty);
            }
            if (abSelected.isEmpty) return false;
            for (final uid in abSelected) {
              final role = abRoles[uid] ?? OrgRole.member;
              if (role == OrgRole.child &&
                  (abGuardians[uid]?.isEmpty ?? true)) { return false; }
            }
            return true;
          }

          return AlertDialog(
            titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            title: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ld.inviteMemberTitle),
                const SizedBox(height: 12),
                tabSelector(),
              ],
            ),
            contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            content: SizedBox(
              width: double.maxFinite,
              height: 360,
              child: tabIndex == 0 ? emailContent : addressBookContent(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(ld.cancel),
              ),
              FilledButton(
                onPressed: canConfirm() ? () => Navigator.pop(ctx, true) : null,
                child: Text(ld.invite),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) return;

    if (tabIndex == 0) {
      // Email invite
      if (emailController.text.trim().isEmpty) return;
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
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(selectedRole == OrgRole.child
                ? l.inviteSentChild
                : l.inviteSent),
          ));
        }
      } catch (e) {
        if (context.mounted) {
          final msg = e.toString().contains('child_account_role_locked')
              ? l.errorChildAccountRoleLocked
              : l.errorMessage(e.toString());
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(msg)));
        }
      }
    } else {
      // Address book multi-invite
      final errors = <String>[];
      for (final uid in abSelected) {
        final entry = addressBookEntries.firstWhere((m) => m.uid == uid);
        final role = abRoles[uid] ?? OrgRole.member;
        final guardianUids = abGuardians[uid]?.toList() ?? [];
        try {
          await ref.read(organizationServiceProvider).inviteMember(
                org.id,
                entry.email,
                role,
                guardianUids: role == OrgRole.child ? guardianUids : [],
              );
        } catch (e) {
          errors.add('${entry.displayName}: $e');
        }
      }
      if (context.mounted) {
        final msg = errors.isEmpty
            ? l.inviteSent
            : errors.join('\n');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 8)),
        );
      }
    }
  }

  Future<void> _showChatRequestDialog(
      BuildContext context, WidgetRef ref, List<OrgMember> members) async {
    final l = AppLocalizations.of(context);
    final currentUid = ref.read(authStateProvider).value!.uid;
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
                          UserAvatar(
                            radius: 16,
                            photoUrl: m.photoUrl,
                            fallbackText: initialsFor(m.displayName),
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
        ref.invalidate(orgConversationsProvider(org.id));
        ref.invalidate(adminConversationsProvider(org.id));
        ref.invalidate(pendingRequestsProvider(org.id));
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
  final WidgetRef ref;
  final bool isSupervisor;
  final bool isAdminOrMod;
  final VoidCallback? onArchive;
  final VoidCallback? onUnarchive;
  final VoidCallback? onDelete;

  const _ConversationTile({
    required this.conv,
    required this.members,
    required this.currentUid,
    required this.ref,
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
            if (conv.isGroup && isAdminOrMod)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(l.editGroup),
                onTap: () {
                  Navigator.pop(ctx);
                  _showEditGroupDialog(context);
                },
              ),
            if (!conv.isGroup && conv.participantUids.contains(currentUid))
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(l.personalChatName),
                onTap: () {
                  Navigator.pop(ctx);
                  _showRenameDialog(context);
                },
              ),
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

  void _showChatInfoSheet(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    // Participants = people in the chat
    final participants = members
        .where((m) => conv.participantUids.contains(m.uid))
        .toList();

    // Supervisors = guardianUids + canApproveUids (live moderators from members list),
    // excluding anyone who is already a participant.
    final participantSet = conv.participantUids.toSet();
    final supervisorUids = {
      ...conv.guardianUids,
      ...members
          .where((m) => m.role == OrgRole.admin || m.role == OrgRole.moderator)
          .map((m) => m.uid),
    }.where((uid) => !participantSet.contains(uid)).toSet();
    final supervisors =
        members.where((m) => supervisorUids.contains(m.uid)).toList();

    Widget memberRow(OrgMember m) {
      final photo = m.photoUrl;
      final initial = initialsFor(m.displayName);
      final roleLabel = switch (m.role) {
        OrgRole.admin => l.roleAdmin,
        OrgRole.moderator => l.roleModerator,
        OrgRole.member => l.roleMember,
        OrgRole.child => l.roleChild,
      };
      return ListTile(
        dense: true,
        leading: UserAvatar(
          radius: 18,
          photoUrl: photo,
          fallbackText: initial,
          textStyle: const TextStyle(fontSize: 13),
        ),
        title: Text(m.displayName, style: const TextStyle(fontSize: 14)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(roleLabel,
              style: TextStyle(
                  fontSize: 11, color: theme.colorScheme.onSecondaryContainer)),
        ),
      );
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        builder: (_, scrollController) => Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(children: [
                const Icon(Icons.group_outlined, size: 18),
                const SizedBox(width: 8),
                Text(l.chatInfoTitle,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: scrollController,
                children: [
                  // ── Teilnehmer ─────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(l.chatParticipants,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[600])),
                  ),
                  if (participants.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Text('—', style: TextStyle(color: Colors.grey[400])),
                    )
                  else
                    ...participants.map(memberRow),

                  // ── Überwacher ─────────────────────────────────────────
                  if (supervisors.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 2),
                      child: Text(l.chatSupervisors,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[600])),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: Text(l.chatSupervisorHint,
                          style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                    ),
                    ...supervisors.map(memberRow),
                  ],
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditGroupDialog(BuildContext context) =>
      showEditGroupDialog(context: context, ref: ref, conv: conv);

  Future<void> _showRenameDialog(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final controller = TextEditingController(text: conv.personalNames[currentUid] ?? '');
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.personalChatName),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 40,
            decoration: InputDecoration(hintText: l.personalNameHint),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.save),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await ref.read(chatServiceProvider).setPersonalName(conv.id, controller.text);
    } finally {
      Future.delayed(const Duration(milliseconds: 400), () {
        controller.dispose();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isArchived = conv.status == ConversationStatus.archived;
    final String title;
    final Widget avatar;

    if (conv.isGroup) {
      title = conv.name ?? 'Gruppe';
      avatar = GroupAvatar(imageUrl: conv.imageUrl);
    } else {
      // Bei überwachten Chats immer das Kind anzeigen, unabhängig davon wer
      // schaut – sonst sehen Guardians zufällig den anderen Erwachsenen.
      final String otherUid;
      if (isSupervisor) {
        final childUid = members
            .where((m) =>
                m.role == OrgRole.child &&
                conv.participantUids.contains(m.uid))
            .map((m) => m.uid)
            .firstOrNull;
        otherUid = childUid ??
            conv.participantUids.firstWhere(
                (uid) => uid != currentUid,
                orElse: () => conv.participantUids.firstOrNull ?? '');
      } else {
        otherUid = conv.participantUids.firstWhere(
            (uid) => uid != currentUid,
            orElse: () => '');
      }
      final other = members.where((m) => m.uid == otherUid).firstOrNull;
      final personalName = conv.personalNames[currentUid];
      title = (personalName != null && personalName.isNotEmpty)
          ? personalName
          : (other?.displayName ?? 'Unbekannt');
      final photoUrl = other?.photoUrl;
      avatar = UserAvatar(
        photoUrl: photoUrl,
        fallbackText: initialsFor(title),
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
            colorFilter: const ColorFilter.matrix([
              0.2126, 0.7152, 0.0722, 0, 0,
              0.2126, 0.7152, 0.0722, 0, 0,
              0.2126, 0.7152, 0.0722, 0, 0,
              0,      0,      0,      1, 0,
            ]),
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

    final receipts = ref.watch(myReadReceiptsProvider).value ?? {};
    final hasUnread = !isArchived && conv.hasUnreadWith(currentUid, receipts);

    return ListTile(
      leading: leading,
      title: Text(title,
          style: isArchived
              ? TextStyle(color: Colors.grey[500])
              : hasUnread
                  ? const TextStyle(fontWeight: FontWeight.bold)
                  : null),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isSupervisor) ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  conv.isGroup ? Icons.group : Icons.person,
                  size: 11,
                  color: Colors.grey[500],
                ),
                const SizedBox(width: 3),
                Text(
                  conv.isGroup ? l.chatTypeGroup : l.chatTypeDirect,
                  style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                ),
              ],
            ),
            const SizedBox(height: 1),
          ],
          if (conv.lastMessage != null)
            Text(conv.lastMessage!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: isArchived
                    ? TextStyle(color: Colors.grey[400])
                    : hasUnread
                        ? const TextStyle(fontWeight: FontWeight.w500)
                        : null)
          else
            Text(l.noMessages,
                style:
                    TextStyle(color: isArchived ? Colors.grey[400] : Colors.grey)),
        ],
      ),
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
          if (isSupervisor) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => _showChatInfoSheet(context),
              child: Icon(Icons.info_outline, size: 18, color: Colors.grey[500]),
            ),
          ],
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
      onLongPress: (!conv.isGroup && conv.participantUids.contains(currentUid) && !isAdminOrMod)
          ? () => _showRenameDialog(context)
          : null,
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

  // Rolle ist gesperrt wenn das Mitglied selbst ein Kind ist.
  bool get _isRoleLocked => member.role == OrgRole.child;


  bool get _hasActions {
    if (member.uid == currentUid) return true; // eigene Kachel: Benachrichtigungen + Austreten
    final isGuardian = member.guardianUids.contains(currentUid);
    final isMod = !isAdmin &&
        allMembers.where((m) => m.uid == currentUid).firstOrNull?.role ==
            OrgRole.moderator;
    if ((isMod || isAdmin) && member.role == OrgRole.child) return true;
    if (!isAdmin && isGuardian) return true;
    if (!isAdmin && !isGuardian) return true;
    if (isAdmin && member.role != OrgRole.admin) return true;
    return false;
  }

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
            // Nicht-Admin: Chat anfragen (für andere Mitglieder)
            if (!isAdmin && !isOwnTile && !isGuardian)
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
              if (!_isRoleLocked) ...[
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
              ],
              ListTile(
                leading: const Icon(Icons.person_remove_outlined, color: Colors.red),
                title: Text(l.remove, style: const TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _confirmRemove(context);
                },
              ),
            ],
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
      ref.invalidate(orgConversationsProvider(org.id));
      ref.invalidate(adminConversationsProvider(org.id));
      ref.invalidate(pendingRequestsProvider(org.id));
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
      ref.invalidate(orgConversationsProvider(org.id));
      ref.invalidate(adminConversationsProvider(org.id));
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

    await ref
        .read(organizationServiceProvider)
        .updateMemberRole(org.id, member.uid, selected);
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final isOnlyGuardian = allMembers.any((m) =>
        m.role == OrgRole.child &&
        m.guardianUids.contains(member.uid) &&
        m.guardianUids.length == 1);

    if (isOnlyGuardian) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          final ld = AppLocalizations.of(ctx);
          return AlertDialog(
            title: Text(ld.errorRemoveLastGuardianTitle),
            content: Text(ld.errorRemoveLastGuardianContent),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(ld.cancel),
              ),
            ],
          );
        },
      );
      return;
    }

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
        ref.invalidate(myOrganizationsProvider);
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
      leading: UserAvatar(
        photoUrl: member.photoUrl,
        fallbackText: initialsFor(member.displayName),
      ),
      title: Text(member.displayName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (member.hideEmail)
            Row(children: [
              Icon(Icons.no_accounts_outlined, size: 12, color: Colors.grey[500]),
              const SizedBox(width: 4),
              Text(AppLocalizations.of(context).emailHidden,
                  style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            ])
          else
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
          if (_hasActions)
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
                ref.invalidate(pendingChildInvitesProvider(org.id));
                ref.invalidate(orgMembersProvider(org.id));
                ref.invalidate(myOrganizationsProvider);
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
                ref.invalidate(pendingChildInvitesProvider(org.id));
                ref.invalidate(orgMembersProvider(org.id));
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
    final count = ref.watch(organizationProvider(orgId)).value?.pendingReportsCount ?? 0;
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
                                        report['id'] as String, widget.org.id);
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
      await ref.read(chatServiceProvider).softDeleteMessage(convId, msgId);
    }
    await ref.read(chatServiceProvider).markReportReviewed(reportId, widget.org.id);
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
  return ref.watch(chatServiceProvider).watchReports(orgId);
});

// ── Pinnwand ──────────────────────────────────────────────────────────────────

class _PinnwandTab extends ConsumerStatefulWidget {
  final String orgId;
  final bool canManage;

  const _PinnwandTab({required this.orgId, required this.canManage});

  @override
  ConsumerState<_PinnwandTab> createState() => _PinnwandTabState();
}

class _PinnwandTabState extends ConsumerState<_PinnwandTab> {
  bool _fabExpanded = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final announcementsAsync = ref.watch(announcementsProvider(widget.orgId));

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
                    orgId: widget.orgId,
                    canManage: widget.canManage,
                  ),
                ),
          if (_fabExpanded)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _fabExpanded = false),
                behavior: HitTestBehavior.opaque,
              ),
            ),
          if (widget.canManage)
            Positioned(
              right: 16,
              bottom: 16 + MediaQuery.of(context).padding.bottom,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_fabExpanded) ...[
                    _SpeedDialOption(
                      icon: Icons.campaign_outlined,
                      label: l.pinnwandNewAnnouncement,
                      onTap: () {
                        setState(() => _fabExpanded = false);
                        _showAnnouncementDialog(context, ref, widget.orgId, null);
                      },
                    ),
                    const SizedBox(height: 8),
                    _SpeedDialOption(
                      icon: Icons.event_outlined,
                      label: l.pinnwandNewEvent,
                      onTap: () {
                        setState(() => _fabExpanded = false);
                        _showEventDialog(context, ref, widget.orgId, null);
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                  FloatingActionButton(
                    heroTag: 'pinnwand_fab',
                    onPressed: () =>
                        setState(() => _fabExpanded = !_fabExpanded),
                    child: AnimatedRotation(
                      turns: _fabExpanded ? 0.125 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(Icons.add),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Pinnwand-Dialoge (freie Funktionen) ───────────────────────────────────────

Future<void> _showAnnouncementDialog(BuildContext context, WidgetRef ref,
    String orgId, Announcement? existing) async {
  final l = AppLocalizations.of(context);
  final titleCtrl = TextEditingController(text: existing?.title ?? '');
  final contentCtrl = TextEditingController(text: existing?.content ?? '');
  DateTime? expiresAt = existing?.expiresAt;
  bool clearExpiry = false;
  try {

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
          title: Text(
              existing == null ? ld.newAnnouncement : ld.editAnnouncement),
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
                                DateTime.now()
                                    .add(const Duration(days: 7)),
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
      ref.invalidate(announcementsProvider(orgId));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.errorMessage(e.toString()))));
      }
    }
  } finally {
    Future.delayed(const Duration(milliseconds: 400), () {
      titleCtrl.dispose();
      contentCtrl.dispose();
    });
  }
}

Future<void> _showEventDialog(BuildContext context, WidgetRef ref,
    String orgId, Announcement? existing) async {
  final l = AppLocalizations.of(context);
  final titleCtrl = TextEditingController(text: existing?.title ?? '');
  final contentCtrl = TextEditingController(text: existing?.content ?? '');
  final locationCtrl = TextEditingController(text: existing?.location ?? '');

  DateTime? eventDate = existing?.eventDate;
  TimeOfDay? eventTime =
      existing?.eventDate != null ? TimeOfDay.fromDateTime(existing!.eventDate!) : null;
  TimeOfDay? endTime = existing?.eventEndDate != null
      ? TimeOfDay.fromDateTime(existing!.eventEndDate!)
      : null;
  bool rsvpPublic = existing?.rsvpPublic ?? false;
  try {

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        final ld = AppLocalizations.of(ctx);

        String dateLine = eventDate == null
            ? ld.eventDate
            : '${eventDate!.day.toString().padLeft(2, '0')}.'
                '${eventDate!.month.toString().padLeft(2, '0')}.'
                '${eventDate!.year}';
        String timeLine =
            eventTime == null ? ld.eventTime : eventTime!.format(ctx);
        String endTimeLine =
            endTime == null ? ld.eventEndTime : endTime!.format(ctx);

        return AlertDialog(
          title: Text(existing == null ? ld.eventCreate : ld.eventEdit),
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
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today_outlined,
                            size: 16),
                        label: Text(dateLine,
                            style: const TextStyle(fontSize: 13)),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate:
                                eventDate ?? DateTime.now(),
                            firstDate: DateTime.now()
                                .subtract(const Duration(days: 1)),
                            lastDate: DateTime.now()
                                .add(const Duration(days: 730)),
                          );
                          if (picked != null) setS(() => eventDate = picked);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.access_time_outlined,
                            size: 16),
                        label: Text(timeLine,
                            style: const TextStyle(fontSize: 13)),
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: ctx,
                            initialTime:
                                eventTime ?? TimeOfDay.now(),
                          );
                          if (picked != null) setS(() => eventTime = picked);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.access_time_outlined, size: 16),
                  label: Text(endTimeLine,
                      style: const TextStyle(fontSize: 13)),
                  onPressed: () async {
                    final picked = await showTimePicker(
                      context: ctx,
                      initialTime: endTime ??
                          (eventTime != null
                              ? TimeOfDay(
                                  hour: (eventTime!.hour + 1) % 24,
                                  minute: eventTime!.minute)
                              : TimeOfDay.now()),
                    );
                    setS(() => endTime = picked);
                  },
                ),
                if (endTime != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: const Icon(Icons.close, size: 14),
                      label: Text(ld.announcementRemoveExpiry,
                          style: const TextStyle(fontSize: 12)),
                      onPressed: () => setS(() => endTime = null),
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: locationCtrl,
                  maxLength: 200,
                  decoration: InputDecoration(
                    labelText: ld.eventLocation,
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.location_on_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: contentCtrl,
                  maxLines: 3,
                  maxLength: 1000,
                  decoration: InputDecoration(
                    labelText: ld.eventDescription,
                    border: const OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  value: rsvpPublic,
                  onChanged: (v) => setS(() => rsvpPublic = v),
                  title: Text(ld.eventRsvpPublic,
                      style: const TextStyle(fontSize: 14)),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
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
    if (title.isEmpty || eventDate == null || eventTime == null) return;

    final fullDate = DateTime(eventDate!.year, eventDate!.month, eventDate!.day,
        eventTime!.hour, eventTime!.minute);
    final rawEndDate = endTime != null
        ? DateTime(eventDate!.year, eventDate!.month, eventDate!.day,
            endTime!.hour, endTime!.minute)
        : null;
    // Endzeit muss nach Startzeit liegen — sonst wird sie verworfen
    final fullEndDate =
        rawEndDate != null && rawEndDate.isAfter(fullDate) ? rawEndDate : null;

    try {
      final service = ref.read(organizationServiceProvider);
      final loc = locationCtrl.text.trim().isEmpty ? null : locationCtrl.text.trim();
      if (existing == null) {
        await service.createEvent(
          orgId,
          title,
          fullDate,
          content: contentCtrl.text.trim(),
          eventEndDate: fullEndDate,
          location: loc,
          rsvpPublic: rsvpPublic,
        );
      } else {
        await service.editEvent(
          orgId,
          existing.id,
          title,
          fullDate,
          content: contentCtrl.text.trim(),
          eventEndDate: fullEndDate,
          location: loc,
          rsvpPublic: rsvpPublic,
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.errorMessage(e.toString()))));
      }
    }
  } finally {
    Future.delayed(const Duration(milliseconds: 400), () {
      titleCtrl.dispose();
      contentCtrl.dispose();
      locationCtrl.dispose();
    });
  }
}

// ── Speed-Dial Option ─────────────────────────────────────────────────────────

class _SpeedDialOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SpeedDialOption(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          elevation: 2,
          borderRadius: BorderRadius.circular(8),
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w500)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FloatingActionButton.small(
          heroTag: null,
          onPressed: onTap,
          child: Icon(icon),
        ),
      ],
    );
  }
}

String _formatEventDate(DateTime start, DateTime? end) {
  final d =
      '${start.day.toString().padLeft(2, '0')}.${start.month.toString().padLeft(2, '0')}.${start.year}';
  final s =
      '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
  if (end == null) return '$d $s';
  final e =
      '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
  return '$d $s – $e';
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

  void _showReactionPicker(
      BuildContext context, WidgetRef ref, String currentUid) {
    final myReaction = announcement.reactions[currentUid];
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: ['👍', '❤️', '😂', '😮', '😢', '😡', '👎']
                .map((e) => GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        ref
                            .read(organizationServiceProvider)
                            .reactToAnnouncement(
                              orgId,
                              announcement.id,
                              currentUid,
                              myReaction == e ? null : e,
                            );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: myReaction == e
                              ? Theme.of(context).colorScheme.primaryContainer
                              : null,
                          shape: BoxShape.circle,
                        ),
                        child: Text(e, style: const TextStyle(fontSize: 26)),
                      ),
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final currentUid = ref.read(authStateProvider).value?.uid ?? '';

    final isEvent = announcement.isEvent;
    final isPast = announcement.isPastEvent;
    final isExpired = announcement.isExpired;
    final isDimmed = isExpired || isPast;
    final hasReactions = announcement.reactions.isNotEmpty;

    Widget card = Card(
      margin: EdgeInsets.zero,
      color: isDimmed
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
                Icon(
                  isEvent ? Icons.event_outlined : Icons.campaign_outlined,
                  size: 18,
                  color: isDimmed
                      ? colorScheme.onSurfaceVariant
                      : colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    announcement.title,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: isDimmed ? colorScheme.onSurfaceVariant : null),
                  ),
                ),
                if (canManage)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 18),
                    onSelected: (value) async {
                      if (value == 'edit' && context.mounted) {
                        if (isEvent) {
                          await _showEventDialog(
                              context, ref, orgId, announcement);
                        } else {
                          await _showAnnouncementDialog(
                              context, ref, orgId, announcement);
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
                          leading: const Icon(Icons.delete_outline,
                              color: Colors.red),
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
            // Event-specific: date/time + location
            if (isEvent && announcement.eventDate != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.access_time_outlined,
                      size: 12,
                      color: isPast ? Colors.grey[400] : colorScheme.primary),
                  const SizedBox(width: 4),
                  Text(
                    _formatEventDate(announcement.eventDate!,
                        announcement.eventEndDate),
                    style: TextStyle(
                      fontSize: 12,
                      color: isPast ? Colors.grey[400] : colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (isPast) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(l.eventPast,
                          style: TextStyle(
                              fontSize: 10, color: Colors.grey[600])),
                    ),
                  ],
                ],
              ),
            ],
            if (isEvent && announcement.location != null &&
                announcement.location!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.location_on_outlined,
                      size: 12, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      announcement.location!,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            if (announcement.content.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                announcement.content,
                style: TextStyle(
                    color: isDimmed ? colorScheme.onSurfaceVariant : null),
                maxLines: isEvent ? 2 : null,
                overflow: isEvent ? TextOverflow.ellipsis : null,
              ),
            ],
            // Announcement expiry
            if (!isEvent && announcement.expiresAt != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    isExpired
                        ? Icons.event_busy_outlined
                        : Icons.event_available_outlined,
                    size: 12,
                    color: isExpired
                        ? Colors.red[400]
                        : Colors.green[600],
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
                      color: isExpired
                          ? Colors.red[400]
                          : Colors.green[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
            // Event RSVP summary
            if (isEvent && announcement.rsvp.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                l.eventRsvpCount(announcement.rsvpYesCount,
                    announcement.rsvpNoCount, announcement.rsvpMaybeCount),
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
            if (hasReactions) ...[
              const SizedBox(height: 6),
              _AnnouncementReactionChips(
                reactions: announcement.reactions,
                currentUid: currentUid,
                onTap: (emoji) => ref
                    .read(organizationServiceProvider)
                    .reactToAnnouncement(
                        orgId, announcement.id, currentUid, emoji),
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
                  _formatDate(
                      announcement.updatedAt ?? announcement.createdAt),
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (isEvent) {
      return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => _EventDetailSheet(
            event: announcement,
            orgId: orgId,
            canManage: canManage,
          ),
        ),
        onLongPress: () => _showReactionPicker(context, ref, currentUid),
        child: card,
      );
    }
    return GestureDetector(
      onLongPress: () => _showReactionPicker(context, ref, currentUid),
      child: card,
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final ld = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(announcement.isEvent
              ? ld.eventDelete
              : ld.deleteAnnouncementTitle),
          content: Text(announcement.isEvent
              ? ld.eventDeleteConfirm
              : ld.deleteAnnouncementContent),
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

Future<void> _respond(BuildContext context, WidgetRef ref, String orgId,
    String eventId, String uid, RsvpStatus? status, AppLocalizations l) async {
  try {
    await ref.read(organizationServiceProvider).respondToEvent(orgId, eventId, uid, status);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.errorMessage(e.toString()))));
    }
  }
}

// ── Event Detail Sheet ────────────────────────────────────────────────────────

class _EventDetailSheet extends ConsumerWidget {
  final Announcement event;
  final String orgId;
  final bool canManage;

  const _EventDetailSheet({
    required this.event,
    required this.orgId,
    required this.canManage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final currentUid = ref.read(authStateProvider).value?.uid ?? '';

    // Shadow field with live data — only rebuilds when this specific event changes
    final event = ref.watch(announcementsProvider(orgId).select(
      (async) =>
          async.asData?.value.firstWhere((a) => a.id == this.event.id,
              orElse: () => this.event) ??
          this.event,
    ));

    final myStatus = event.rsvpStatusFor(currentUid);


    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, scrollCtrl) => Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              children: [
                // Title
                Text(event.title,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),

                // Date/time row
                if (event.eventDate != null)
                  _EventInfoRow(
                    icon: Icons.access_time_outlined,
                    text: _formatEventDate(event.eventDate!, event.eventEndDate),
                    color: event.isPastEvent
                        ? Colors.grey
                        : colorScheme.primary,
                  ),

                // Location
                if (event.location != null && event.location!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _EventInfoRow(
                    icon: Icons.location_on_outlined,
                    text: event.location!,
                    trailing: IconButton(
                      icon: const Icon(Icons.open_in_new, size: 16),
                      tooltip: l.eventOpenInMaps,
                      onPressed: () => _openInMaps(event.location!),
                    ),
                  ),
                ],

                // Description
                if (event.content.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(event.content,
                      style: TextStyle(color: colorScheme.onSurfaceVariant)),
                ],

                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 8),

                // RSVP buttons
                if (!event.isPastEvent) ...[
                  Text(l.eventRsvpAttendees,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _RsvpButton(
                        label: l.eventRsvpYes,
                        icon: Icons.check_circle_outline,
                        color: Colors.green,
                        selected: myStatus == RsvpStatus.yes,
                        onTap: () => _respond(context, ref, orgId, event.id,
                            currentUid, myStatus == RsvpStatus.yes ? null : RsvpStatus.yes, l),
                      ),
                      const SizedBox(width: 8),
                      _RsvpButton(
                        label: l.eventRsvpMaybe,
                        icon: Icons.help_outline,
                        color: Colors.orange,
                        selected: myStatus == RsvpStatus.maybe,
                        onTap: () => _respond(context, ref, orgId, event.id,
                            currentUid, myStatus == RsvpStatus.maybe ? null : RsvpStatus.maybe, l),
                      ),
                      const SizedBox(width: 8),
                      _RsvpButton(
                        label: l.eventRsvpNo,
                        icon: Icons.cancel_outlined,
                        color: Colors.red,
                        selected: myStatus == RsvpStatus.no,
                        onTap: () => _respond(context, ref, orgId, event.id,
                            currentUid, myStatus == RsvpStatus.no ? null : RsvpStatus.no, l),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // RSVP counts
                if (event.rsvp.isNotEmpty) ...[
                  Text(
                    l.eventRsvpCount(event.rsvpYesCount, event.rsvpNoCount,
                        event.rsvpMaybeCount),
                    style:
                        TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                ] else ...[
                  Text(l.eventNoRsvp,
                      style:
                          TextStyle(fontSize: 13, color: Colors.grey[500])),
                  const SizedBox(height: 8),
                ],

                // Admin/Mod or public event: detailed RSVP list
                if ((canManage || event.rsvpPublic) && event.rsvp.isNotEmpty) ...[
                  _RsvpDetailList(rsvp: event.rsvp, orgId: orgId, l: l),
                  const SizedBox(height: 8),
                ],

                // Guardian: show child's response
                if (!canManage)
                  _GuardianChildrenRsvp(
                      orgId: orgId,
                      currentUid: currentUid,
                      event: event,
                      l: l),

                const Divider(),
                const SizedBox(height: 8),

                // Calendar export
                if (event.eventDate != null)
                  FilledButton.icon(
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(l.eventAddToCalendar),
                    onPressed: () => _addToCalendar(context, l, event),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openInMaps(String location) async {
    final encoded = Uri.encodeComponent(location);
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$encoded');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _addToCalendar(
      BuildContext context, AppLocalizations l, Announcement ev) async {
    if (ev.eventDate == null) return;
    final start = ev.eventDate!;
    final end = ev.eventEndDate ?? start.add(const Duration(hours: 1));

    if (Platform.isWindows) {
      final ics = _buildIcs(start, end, ev);
      try {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/event_${ev.id}.ics');
        await file.writeAsString(ics);
        await OpenFilex.open(file.path);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l.eventCalendarExportSuccess)));
        }
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l.eventCalendarExportError)));
        }
      }
    } else {
      final calEvent = Event(
        title: ev.title,
        description: ev.content,
        location: ev.location ?? '',
        startDate: start,
        endDate: end,
        allDay: false,
      );
      Add2Calendar.addEvent2Cal(calEvent);
    }
  }

  String _buildIcs(DateTime start, DateTime end, Announcement ev) {
    String fmt(DateTime dt) {
      final u = dt.toUtc();
      return '${u.year.toString().padLeft(4, '0')}'
          '${u.month.toString().padLeft(2, '0')}'
          '${u.day.toString().padLeft(2, '0')}'
          'T${u.hour.toString().padLeft(2, '0')}'
          '${u.minute.toString().padLeft(2, '0')}00Z';
    }

    // RFC 5545: escape backslash, newline, comma, semicolon
    String esc(String v) => v
        .replaceAll('\\', '\\\\')
        .replaceAll('\r\n', '\\n')
        .replaceAll('\n', '\\n')
        .replaceAll(',', '\\,')
        .replaceAll(';', '\\;');

    return 'BEGIN:VCALENDAR\r\n'
        'VERSION:2.0\r\n'
        'BEGIN:VEVENT\r\n'
        'SUMMARY:${esc(ev.title)}\r\n'
        'DTSTART:${fmt(start)}\r\n'
        'DTEND:${fmt(end)}\r\n'
        'LOCATION:${esc(ev.location ?? '')}\r\n'
        'DESCRIPTION:${esc(ev.content)}\r\n'
        'END:VEVENT\r\n'
        'END:VCALENDAR';
  }

}

class _EventInfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  final Widget? trailing;

  const _EventInfoRow(
      {required this.icon, required this.text, this.color, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color ?? Colors.grey[600]),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  fontSize: 14,
                  color: color ?? Theme.of(context).colorScheme.onSurface)),
        ),
        // ignore: use_null_aware_elements
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _RsvpButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _RsvpButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: OutlinedButton.icon(
        icon: Icon(icon, size: 16, color: selected ? Colors.white : color),
        label: Text(label,
            style: TextStyle(
                fontSize: 12, color: selected ? Colors.white : color)),
        style: OutlinedButton.styleFrom(
          backgroundColor: selected ? color : null,
          side: BorderSide(color: color),
          padding: const EdgeInsets.symmetric(vertical: 8),
        ),
        onPressed: onTap,
      ),
    );
  }
}

class _RsvpDetailList extends ConsumerWidget {
  final Map<String, String> rsvp;
  final String orgId;
  final AppLocalizations l;

  const _RsvpDetailList(
      {required this.rsvp, required this.orgId, required this.l});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(orgMembersProvider(orgId));
    final memberMap = {
      for (final m in membersAsync.asData?.value ?? <OrgMember>[]) m.uid: m
    };

    final groups = <RsvpStatus, List<String>>{
      RsvpStatus.yes: [],
      RsvpStatus.maybe: [],
      RsvpStatus.no: [],
    };
    for (final entry in rsvp.entries) {
      final status = RsvpStatusX.fromString(entry.value);
      if (status != null) groups[status]!.add(entry.key);
    }

    Widget groupTile(RsvpStatus status, List<String> uids) {
      if (uids.isEmpty) return const SizedBox.shrink();
      final label = switch (status) {
        RsvpStatus.yes => l.eventRsvpYesLabel(uids.length),
        RsvpStatus.no => l.eventRsvpNoLabel(uids.length),
        RsvpStatus.maybe => l.eventRsvpMaybeLabel(uids.length),
      };
      final color = switch (status) {
        RsvpStatus.yes => Colors.green,
        RsvpStatus.no => Colors.red,
        RsvpStatus.maybe => Colors.orange,
      };
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: uids.map((uid) {
              final name = memberMap[uid]?.displayName ?? uid;
              return Chip(
                label: Text(name, style: const TextStyle(fontSize: 11)),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        groupTile(RsvpStatus.yes, groups[RsvpStatus.yes]!),
        groupTile(RsvpStatus.maybe, groups[RsvpStatus.maybe]!),
        groupTile(RsvpStatus.no, groups[RsvpStatus.no]!),
      ],
    );
  }
}

class _GuardianChildrenRsvp extends ConsumerWidget {
  final String orgId;
  final String currentUid;
  final Announcement event;
  final AppLocalizations l;

  const _GuardianChildrenRsvp({
    required this.orgId,
    required this.currentUid,
    required this.event,
    required this.l,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(orgMembersProvider(orgId));
    final myChildren = membersAsync.asData?.value
            .where((m) => m.guardianUids.contains(currentUid))
            .toList() ??
        [];
    if (myChildren.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const SizedBox(height: 8),
        Text(l.eventChildRsvp,
            style:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 6),
        for (final child in myChildren)
          _ChildRsvpRow(
              child: child,
              status: event.rsvpStatusFor(child.uid),
              l: l),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _ChildRsvpRow extends StatelessWidget {
  final OrgMember child;
  final RsvpStatus? status;
  final AppLocalizations l;

  const _ChildRsvpRow(
      {required this.child, required this.status, required this.l});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      RsvpStatus.yes => (l.eventRsvpYes, Colors.green),
      RsvpStatus.no => (l.eventRsvpNo, Colors.red),
      RsvpStatus.maybe => (l.eventRsvpMaybe, Colors.orange),
      null => ('–', Colors.grey),
    };
    return Row(
      children: [
        Text(child.displayName,
            style: const TextStyle(fontSize: 13)),
        const Spacer(),
        Text(label, style: TextStyle(fontSize: 13, color: color)),
      ],
    );
  }
}

// ── Ankündigungs-Reaktionen ───────────────────────────────────────────────────

class _AnnouncementReactionChips extends StatelessWidget {
  final Map<String, String> reactions;
  final String currentUid;
  final void Function(String? emoji) onTap;

  const _AnnouncementReactionChips({
    required this.reactions,
    required this.currentUid,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final emoji in reactions.values) {
      counts[emoji] = (counts[emoji] ?? 0) + 1;
    }
    final myEmoji = reactions[currentUid];

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: counts.entries.map((e) {
        final isMyReaction = myEmoji == e.key;
        return GestureDetector(
          onTap: () => onTap(isMyReaction ? null : e.key),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isMyReaction
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: isMyReaction
                  ? Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 1,
                    )
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(e.key, style: const TextStyle(fontSize: 13)),
                if (e.value > 1) ...[
                  const SizedBox(width: 3),
                  Text(
                    '${e.value}',
                    style: TextStyle(
                      fontSize: 11,
                      color: isMyReaction
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Änderungsprotokoll ────────────────────────────────────────────────────────

class _AuditLogSheet extends ConsumerWidget {
  final String orgId;
  const _AuditLogSheet({required this.orgId});

  String _actionLabel(AppLocalizations l, OrgAuditEntry e) {
    return switch (e.action) {
      AuditAction.invitationSent => l.auditActionInvitationSent,
      AuditAction.memberConfirmed => l.auditActionMemberConfirmed,
      AuditAction.memberRemoved => l.auditActionMemberRemoved,
      AuditAction.settingsChanged => l.auditActionSettingsChanged,
      AuditAction.roleChanged => l.auditActionRoleChanged,
      AuditAction.adminTransferred => l.auditActionAdminTransferred,
      AuditAction.keywordsChanged => l.auditActionKeywordsChanged,
      AuditAction.guardiansChanged => l.auditActionGuardiansChanged,
    };
  }

  String _detailLine(OrgAuditEntry e) {
    final d = e.details;
    return switch (e.action) {
      AuditAction.invitationSent =>
        '${d['name'] ?? d['email'] ?? ''}'
        '${d['role'] != null ? ' (${d['role']})' : ''}',
      AuditAction.memberConfirmed =>
        '${d['targetName'] ?? d['name'] ?? ''}${d['role'] != null ? ' (${d['role']})' : ''}',
      AuditAction.memberRemoved =>
        '${d['targetName'] ?? d['name'] ?? ''}${d['role'] != null ? ' (${d['role']})' : ''}',
      AuditAction.settingsChanged =>
        [
          if (d['name'] != null) d['name'],
          if (d['tag'] != null) d['tag'],
          if (d['messageRetentionDays'] != null) '${d['messageRetentionDays']} Tage',
        ].join(', '),
      AuditAction.roleChanged =>
        '${d['targetName'] ?? d['name'] ?? ''}: ${d['oldRole'] ?? ''} → ${d['newRole'] ?? ''}',
      AuditAction.adminTransferred => d['newAdminName'] as String? ?? '',
      AuditAction.keywordsChanged =>
        '${d['count'] ?? ''} Schlüsselwörter',
      AuditAction.guardiansChanged => d['childName'] as String? ?? '',
    };
  }

  String _formatTs(DateTime dt) {
    final now = DateTime.now();
    String pad2(int n) => n.toString().padLeft(2, '0');
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '${pad2(dt.hour)}:${pad2(dt.minute)}';
    }
    return '${pad2(dt.day)}.${pad2(dt.month)}.${dt.year} ${pad2(dt.hour)}:${pad2(dt.minute)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final entriesAsync = ref
        .watch(organizationServiceProvider)
        .watchAuditLog(orgId);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, controller) => Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.history_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(l.auditLog,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: StreamBuilder<List<OrgAuditEntry>>(
                stream: entriesAsync,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final entries = snap.data ?? [];
                  if (entries.isEmpty) {
                    return Center(
                      child: Text(l.auditNoEntries,
                          style: TextStyle(color: Colors.grey[500])),
                    );
                  }
                  return ListView.separated(
                    controller: controller,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final e = entries[i];
                      final detail = _detailLine(e);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(width: 4),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_actionLabel(l, e),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14)),
                                  if (detail.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(detail,
                                        style: const TextStyle(fontSize: 13)),
                                  ],
                                  const SizedBox(height: 4),
                                  Text(
                                    l.auditBy(e.actorName),
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _formatTs(e.timestamp),
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Org Help Button mit Glow-Animation ───────────────────────────────────────

class _OrgHelpButton extends StatefulWidget {
  final String orgId;
  final VoidCallback onTap;

  const _OrgHelpButton({required this.orgId, required this.onTap});

  @override
  State<_OrgHelpButton> createState() => _OrgHelpButtonState();
}

class _OrgHelpButtonState extends State<_OrgHelpButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow;
  bool _seen = true;

  static String _prefsKey(String orgId) => 'orgTourSeen_$orgId';

  @override
  void initState() {
    super.initState();
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _checkSeen();
  }

  Future<void> _checkSeen() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool(_prefsKey(widget.orgId)) ?? false;
    if (!seen && mounted) {
      _glow.repeat(reverse: true);
      setState(() => _seen = false);
    }
  }

  Future<void> _markSeen() async {
    if (_seen) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey(widget.orgId), true);
    if (mounted) {
      _glow.stop();
      setState(() => _seen = true);
    }
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _glow,
      builder: (context, child) {
        final opacity = _seen ? 0.0 : _glow.value * 0.55;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: opacity),
                blurRadius: 14,
                spreadRadius: 5,
              ),
            ],
          ),
          child: child,
        );
      },
      child: IconButton(
        icon: const Icon(Icons.help_outline),
        onPressed: () {
          _markSeen();
          widget.onTap();
        },
      ),
    );
  }
}
