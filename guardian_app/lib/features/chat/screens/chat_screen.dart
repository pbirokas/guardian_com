import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/models/conversation.dart';
import '../../../core/models/message.dart';
import '../../../core/models/org_member.dart';
import '../../../features/organizations/providers/organizations_provider.dart';
import '../providers/chat_provider.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String chatId;
  final String? partnerName;

  const ChatScreen({super.key, required this.chatId, this.partnerName});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  int _limit = 30;
  bool _loadingMore = false;
  bool _pickingImage = false;

  @override
  void initState() {
    super.initState();
    _markRead();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels <= 80 && !_loadingMore) {
      setState(() {
        _loadingMore = true;
        _limit += 30;
      });
      Future.delayed(const Duration(milliseconds: 300),
          () { if (mounted) setState(() => _loadingMore = false); });
    }
  }

  void _markRead() {
    ref.read(chatServiceProvider).markAsRead(widget.chatId).catchError((_) {});
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    try {
      await ref.read(chatServiceProvider).sendMessage(widget.chatId, text);
      _markRead();
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e')),
        );
      }
    }
  }

  Future<void> _sendImage() async {
    if (_pickingImage) return;
    setState(() => _pickingImage = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      if (picked == null || !mounted) return;
      await ref
          .read(chatServiceProvider)
          .sendImage(widget.chatId, File(picked.path));
      _markRead();
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Senden: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  Future<void> _showAddMemberDialog(BuildContext context, Conversation conv,
      List<OrgMember> allMembers) async {
    // Nur Mitglieder anzeigen die noch nicht im Chat sind
    final available = allMembers
        .where((m) => !conv.participantUids.contains(m.uid))
        .toList();

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alle Mitglieder sind bereits im Chat.')),
      );
      return;
    }

    final selected = <String>{};
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Mitglied hinzufügen'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: available
                  .map((m) => CheckboxListTile(
                        value: selected.contains(m.uid),
                        onChanged: (v) => setState(() =>
                            v == true
                                ? selected.add(m.uid)
                                : selected.remove(m.uid)),
                        title: Text(m.displayName),
                        subtitle: Text(m.email,
                            style: const TextStyle(fontSize: 12)),
                        secondary: CircleAvatar(
                          radius: 16,
                          backgroundImage: m.photoUrl != null
                              ? NetworkImage(m.photoUrl!)
                              : null,
                          child: m.photoUrl == null
                              ? Text((m.displayName.isNotEmpty
                                      ? m.displayName[0]
                                      : '?')
                                  .toUpperCase())
                              : null,
                        ),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ))
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: const Text('Hinzufügen'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && selected.isNotEmpty && mounted) {
      try {
        await ref.read(chatServiceProvider).addMembersToConversation(
              conv.id,
              conv.orgId,
              selected.toList(),
            );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    '${selected.length} Mitglied(er) hinzugefügt.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Fehler: $e')));
        }
      }
    }
  }

  Future<void> _showMembersDialog(
    Conversation conv,
    List<OrgMember> allMembers, {
    required bool canManage,
  }) async {
    final participants = allMembers
        .where((m) => conv.participantUids.contains(m.uid))
        .toList();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Mitglieder (${participants.length})'),
          content: SizedBox(
            width: double.maxFinite,
            child: participants.isEmpty
                ? const Text('Keine Mitglieder gefunden.')
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: participants.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final m = participants[i];
                      final isSelf =
                          m.uid == FirebaseAuth.instance.currentUser?.uid;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundImage: m.photoUrl != null
                              ? NetworkImage(m.photoUrl!)
                              : null,
                          child: m.photoUrl == null
                              ? Text((m.displayName.isNotEmpty
                                      ? m.displayName[0]
                                      : '?')
                                  .toUpperCase(),
                                  style: const TextStyle(fontSize: 14))
                              : null,
                        ),
                        title: Text(m.displayName),
                        subtitle: Text(m.email,
                            style: const TextStyle(fontSize: 12)),
                        trailing: canManage && !isSelf
                            ? IconButton(
                                icon: const Icon(Icons.remove_circle_outline,
                                    color: Colors.red),
                                tooltip: 'Entfernen',
                                onPressed: () async {
                                  final confirmed =
                                      await showDialog<bool>(
                                    context: ctx,
                                    builder: (c) => AlertDialog(
                                      title:
                                          const Text('Mitglied entfernen'),
                                      content: Text(
                                          '${m.displayName} aus dem Chat entfernen?'),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(c, false),
                                          child: const Text('Abbrechen'),
                                        ),
                                        FilledButton(
                                          style: FilledButton.styleFrom(
                                              backgroundColor: Colors.red),
                                          onPressed: () =>
                                              Navigator.pop(c, true),
                                          child: const Text('Entfernen'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmed == true && mounted) {
                                    final messenger =
                                        ScaffoldMessenger.of(context);
                                    try {
                                      await ref
                                          .read(chatServiceProvider)
                                          .removeMemberFromConversation(
                                              conv.id, m.uid);
                                      setDialogState(() =>
                                          participants.remove(m));
                                    } catch (e) {
                                      if (mounted) {
                                        messenger.showSnackBar(SnackBar(
                                            content: Text('Fehler: $e')));
                                      }
                                    }
                                  }
                                },
                              )
                            : null,
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Schließen'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(
        messagesProvider((convId: widget.chatId, limit: _limit)));
    final conv = ref.watch(conversationProvider(widget.chatId)).value;
    final isArchived = conv?.status == ConversationStatus.archived;
    final currentUid = FirebaseAuth.instance.currentUser!.uid;

    final members = conv == null
        ? null
        : ref.watch(orgMembersProvider(conv.orgId)).value;

    String title;
    if (conv == null) {
      title = widget.partnerName ?? 'Chat';
    } else if (conv.isGroup) {
      title = conv.name ?? 'Gruppe';
    } else {
      final otherUid = conv.participantUids.firstWhere(
          (uid) => uid != currentUid,
          orElse: () => '');
      final other = members?.where((m) => m.uid == otherUid).firstOrNull;
      title = other?.displayName ?? widget.partnerName ?? 'Chat';
    }

    final isGroupAdmin = conv != null &&
        conv.isGroup &&
        conv.orgAdminUid == currentUid;
    final isModeratorOrAdmin = conv != null &&
        conv.isGroup &&
        conv.canApproveUids.contains(currentUid);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (conv != null && conv.isGroup)
            IconButton(
              icon: const Icon(Icons.group_outlined),
              tooltip: 'Mitglieder anzeigen',
              onPressed: () => _showMembersDialog(
                conv,
                members ?? [],
                canManage: isModeratorOrAdmin,
              ),
            ),
          if (isGroupAdmin && !isArchived)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'add_member') {
                  _showAddMemberDialog(context, conv, members ?? []);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'add_member',
                  child: ListTile(
                    leading: Icon(Icons.person_add_outlined),
                    title: Text('Mitglied hinzufügen'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          if (isArchived)
            Container(
              width: double.infinity,
              color: Colors.grey[200],
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.archive_outlined, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 6),
                  Text('Archiviert – nur lesen',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
            ),
          Expanded(
            child: messagesAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Fehler: $e')),
              data: (messages) {
                if (messages.isNotEmpty && !_loadingMore) _scrollToBottom();
                if (messages.isEmpty) {
                  return const Center(
                    child: Text('Noch keine Nachrichten',
                        style: TextStyle(color: Colors.grey)),
                  );
                }
                final mayHaveMore = messages.length >= _limit;
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length + (mayHaveMore ? 1 : 0),
                  itemBuilder: (ctx, i) {
                    if (mayHaveMore && i == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Center(
                          child: _loadingMore
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : TextButton.icon(
                                  onPressed: () => setState(
                                      () => _limit += 30),
                                  icon: const Icon(Icons.expand_less,
                                      size: 16),
                                  label: const Text('Ältere Nachrichten',
                                      style: TextStyle(fontSize: 12)),
                                ),
                        ),
                      );
                    }
                    final msg = messages[mayHaveMore ? i - 1 : i];
                    final isMe = msg.senderUid == currentUid;
                    final showDate = i == 0 ||
                        !_sameDay(messages[i - 1].sentAt, msg.sentAt);
                    final showSender = !isMe &&
                        (i == 0 ||
                            messages[i - 1].senderUid != msg.senderUid);
                    return Column(
                      children: [
                        if (showDate) _DateDivider(date: msg.sentAt),
                        _MessageBubble(
                          message: msg,
                          isMe: isMe,
                          showSenderName:
                              showSender && msg.senderName.isNotEmpty,
                          onReport: isMe || conv == null
                              ? null
                              : () => _confirmReport(conv, msg),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          if (!isArchived)
            _InputBar(
              controller: _controller,
              onSend: _send,
              onSendImage: _pickingImage ? null : _sendImage,
            ),
        ],
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _confirmReport(Conversation conv, Message msg) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nachricht melden'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Diese Nachricht dem Admin/Moderator melden?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                msg.text,
                style: const TextStyle(fontSize: 13),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
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
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Melden'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      try {
        await ref.read(chatServiceProvider).reportMessage(
              convId: widget.chatId,
              orgId: conv.orgId,
              orgAdminUid: conv.orgAdminUid,
              message: msg,
            );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nachricht wurde gemeldet.')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
  }
}

class _MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;
  final bool showSenderName;
  final VoidCallback? onReport;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    this.showSenderName = false,
    this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onLongPress: onReport == null
          ? null
          : () => showModalBottomSheet(
                context: context,
                builder: (_) => SafeArea(
                  child: ListTile(
                    leading: const Icon(Icons.flag_outlined, color: Colors.red),
                    title: const Text('Nachricht melden',
                        style: TextStyle(color: Colors.red)),
                    onTap: () {
                      Navigator.pop(context);
                      onReport!();
                    },
                  ),
                ),
              ),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
        margin: EdgeInsets.only(
          top: 2,
          bottom: 2,
          left: isMe ? 64 : 0,
          right: isMe ? 0 : 64,
        ),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isMe
              ? colorScheme.primary
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (showSenderName)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  message.senderName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[600],
                  ),
                ),
              ),
            if (message.imageUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  message.imageUrl!,
                  width: 220,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, progress) => progress == null
                      ? child
                      : const SizedBox(
                          width: 220,
                          height: 140,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                  errorBuilder: (ctx, err, stack) =>
                      const Icon(Icons.broken_image),
                ),
              )
            else
              Text(
                message.text,
                style: TextStyle(
                  color: isMe ? colorScheme.onPrimary : null,
                ),
              ),
            const SizedBox(height: 2),
            Text(
              _formatTime(message.sentAt),
              style: TextStyle(
                fontSize: 10,
                color: isMe
                    ? colorScheme.onPrimary.withAlpha(180)
                    : Colors.grey,
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

class _DateDivider extends StatelessWidget {
  final DateTime date;

  const _DateDivider({required this.date});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    String label;
    if (date.day == now.day && date.month == now.month) {
      label = 'Heute';
    } else if (date.day == now.day - 1 && date.month == now.month) {
      label = 'Gestern';
    } else {
      label = '${date.day}.${date.month}.${date.year}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(label,
                style:
                    const TextStyle(fontSize: 12, color: Colors.grey)),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback? onSendImage;

  const _InputBar({
    required this.controller,
    required this.onSend,
    this.onSendImage,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.image_outlined),
              onPressed: onSendImage,
              tooltip: 'Bild senden',
            ),
            Expanded(
              child: TextField(
                controller: controller,
                textCapitalization: TextCapitalization.sentences,
                maxLines: null,
                decoration: InputDecoration(
                  hintText: 'Nachricht schreiben...',
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: onSend,
              style: FilledButton.styleFrom(
                shape: const CircleBorder(),
                padding: const EdgeInsets.all(14),
              ),
              child: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}
