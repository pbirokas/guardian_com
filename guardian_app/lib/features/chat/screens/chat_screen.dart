import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/models/conversation.dart';
import '../../../core/models/message.dart';
import '../../../core/models/org_member.dart';
import '../../../core/models/organization.dart';
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
  int _knownMessageCount = 0;
  bool _atBottom = true;
  bool _mayHaveMore = true; // false sobald Firestore weniger als _limit zurückgibt
  // Scroll-Position vor dem Batch-Laden gespeichert (in _onScroll)
  double? _batchSavedPixels;
  double? _batchSavedMax;

  // ── Voice recording ────────────────────────────────────────────────────────
  final _recorder = AudioRecorder();
  bool _isRecording = false;
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;

  @override
  void initState() {
    super.initState();
    _markRead();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    final pos = _scrollController.position;
    _atBottom = pos.pixels >= pos.maxScrollExtent - 150;

    // Nur laden wenn der User aktiv nach oben scrollt oder ruhig oben sitzt —
    // nicht beim Rückprall (ScrollDirection.forward) nach einem Overscroll.
    if (pos.pixels <= 80 &&
        pos.userScrollDirection != ScrollDirection.forward &&
        !_loadingMore &&
        _knownMessageCount > 0 &&
        _mayHaveMore) {
      _batchSavedPixels = pos.pixels;
      _batchSavedMax    = pos.maxScrollExtent;
      setState(() {
        _loadingMore = true;
        _limit += 30;
      });
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() => _loadingMore = false);
          _batchSavedPixels = null;
          _batchSavedMax    = null;
        }
      });
    }
  }

  void _markRead() {
    ref.read(chatServiceProvider).markAsRead(widget.chatId).catchError((_) {});
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _recordingTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  // ── Voice recording methods ────────────────────────────────────────────────

  Future<void> _startRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Mikrofon-Zugriff wurde verweigert.')),
        );
      }
      return;
    }
    final String path;
    if (kIsWeb) {
      // Auf Web gibt der Recorder eine Blob-URL zurück — kein Pfad nötig
      path = '';
    } else {
      final dir = await getTemporaryDirectory();
      path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    }

    await _recorder.start(
      RecordConfig(
        encoder: kIsWeb ? AudioEncoder.opus : AudioEncoder.aacLc,
        bitRate: 64000,
      ),
      path: path,
    );

    setState(() {
      _isRecording = true;
      _recordingDuration = Duration.zero;
    });

    _recordingTimer =
        Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _recordingDuration += const Duration(seconds: 1));
      }
    });
  }

  Future<void> _stopAndSend() async {
    _recordingTimer?.cancel();
    final messenger = ScaffoldMessenger.of(context); // capture before await
    final path = await _recorder.stop();
    final durationMs = _recordingDuration.inMilliseconds;
    setState(() {
      _isRecording = false;
      _recordingDuration = Duration.zero;
    });
    if (path == null || durationMs < 500) return; // zu kurz → verwerfen
    try {
      // XFile works for both file paths (mobile) and blob URLs (web)
      final bytes = await XFile(path).readAsBytes();
      final contentType = kIsWeb ? 'audio/webm' : 'audio/m4a';
      await ref
          .read(chatServiceProvider)
          .sendVoiceMessage(widget.chatId, bytes, durationMs,
              contentType: contentType);
      _markRead();
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  Future<void> _showCreatePollDialog() async {
    final questionCtrl = TextEditingController();
    final optionCtrls = [
      TextEditingController(text: ''),
      TextEditingController(text: ''),
    ];
    var multipleChoice = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Umfrage erstellen'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: questionCtrl,
                  autofocus: true,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: 'Frage',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Antwortmöglichkeiten',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 6),
                ...optionCtrls.asMap().entries.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: e.value,
                              maxLength: 100,
                              decoration: InputDecoration(
                                labelText: 'Option ${e.key + 1}',
                                border: const OutlineInputBorder(),
                                counterText: '',
                              ),
                            ),
                          ),
                          if (optionCtrls.length > 2)
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline,
                                  color: Colors.red),
                              onPressed: () => setState(() =>
                                  optionCtrls.removeAt(e.key)),
                            ),
                        ],
                      ),
                    )),
                if (optionCtrls.length < 8)
                  TextButton.icon(
                    onPressed: () => setState(() =>
                        optionCtrls.add(TextEditingController())),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Option hinzufügen'),
                  ),
                SwitchListTile(
                  value: multipleChoice,
                  onChanged: (v) => setState(() => multipleChoice = v),
                  title: const Text('Mehrfachauswahl',
                      style: TextStyle(fontSize: 14)),
                  contentPadding: EdgeInsets.zero,
                ),
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

    if (confirmed != true || !mounted) return;
    final question = questionCtrl.text.trim();
    final options = optionCtrls
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    if (question.isEmpty || options.length < 2) return;

    try {
      await ref.read(chatServiceProvider).createPoll(
            widget.chatId,
            question: question,
            optionTexts: options,
            multipleChoice: multipleChoice,
          );
      _markRead();
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  Future<void> _cancelRecording() async {
    _recordingTimer?.cancel();
    await _recorder.stop();
    setState(() {
      _isRecording = false;
      _recordingDuration = Duration.zero;
    });
  }

  void _scrollToBottom({int attempt = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      if (max > 0) {
        _scrollController.jumpTo(max);
      } else if (attempt < 4) {
        _scrollToBottom(attempt: attempt + 1);
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
      final bytes = await picked.readAsBytes();
      await ref
          .read(chatServiceProvider)
          .sendImage(widget.chatId, bytes);
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

  Future<void> _sendFile() async {
    if (_pickingImage) return;
    setState(() => _pickingImage = true);
    try {
      final result = await FilePicker.pickFiles(
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty || !mounted) return;
      final picked = result.files.first;
      final bytes = picked.bytes;
      if (bytes == null) return;
      await ref
          .read(chatServiceProvider)
          .sendFile(widget.chatId, bytes, picked.name, bytes.length);
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
    final messenger = ScaffoldMessenger.of(context);
    // Nur Mitglieder anzeigen die noch nicht im Chat sind
    final available = allMembers
        .where((m) => !conv.participantUids.contains(m.uid))
        .toList();

    if (available.isEmpty) {
      messenger.showSnackBar(
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
          messenger.showSnackBar(SnackBar(
              content: Text('${selected.length} Mitglied(er) hinzugefügt.')));
        }
      } catch (e) {
        if (mounted) {
          messenger.showSnackBar(SnackBar(content: Text('Fehler: $e')));
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

    final isSheltered = conv != null &&
        ref.watch(organizationProvider(conv.orgId)).value?.chatMode ==
            ChatMode.sheltered;

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
          if (isModeratorOrAdmin && !isArchived)
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
                final isFirstLoad = _knownMessageCount == 0;
                final isNewMessage =
                    messages.length == _knownMessageCount + 1;
                if (isFirstLoad || (isNewMessage && _atBottom)) {
                  _scrollToBottom();
                } else if (_batchSavedPixels != null &&
                    messages.length > _knownMessageCount) {
                  final savedPixels = _batchSavedPixels!;
                  final savedMax    = _batchSavedMax!;
                  _batchSavedPixels = null;
                  _batchSavedMax    = null;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted || !_scrollController.hasClients) return;
                    final delta =
                        _scrollController.position.maxScrollExtent - savedMax;
                    if (delta > 0) _scrollController.jumpTo(savedPixels + delta);
                  });
                }
                _knownMessageCount = messages.length;
                if (messages.isEmpty) {
                  return const Center(
                    child: Text('Noch keine Nachrichten',
                        style: TextStyle(color: Colors.grey)),
                  );
                }
                final mayHaveMore = messages.length >= _limit;
                _mayHaveMore = mayHaveMore;
                return Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  child: ListView.builder(
                  controller: _scrollController,
                  physics: const ClampingScrollPhysics(),
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
                                  onPressed: () {
                                    if (_scrollController.hasClients) {
                                      _batchSavedPixels = _scrollController.position.pixels;
                                      _batchSavedMax    = _scrollController.position.maxScrollExtent;
                                    }
                                    setState(() => _limit += 30);
                                  },
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
                    final prev = mayHaveMore ? (i > 1 ? messages[i - 2] : null)
                                             : (i > 0 ? messages[i - 1] : null);
                    final showDate = prev == null ||
                        !_sameDay(prev.sentAt, msg.sentAt);
                    final showSender = !isMe &&
                        (prev == null || prev.senderUid != msg.senderUid);
                    return Column(
                      children: [
                        if (showDate) _DateDivider(date: msg.sentAt),
                        _MessageBubble(
                          message: msg,
                          isMe: isMe,
                          convId: widget.chatId,
                          showSenderName:
                              showSender && msg.senderName.isNotEmpty,
                          isModerating: isModeratorOrAdmin && !isMe,
                          onReport: isMe || conv == null || msg.pollId != null
                              ? null
                              : () => _confirmReport(conv, msg),
                          onEdit: msg.pollId == null &&
                                  msg.imageUrl == null &&
                                  msg.audioUrl == null &&
                                  msg.fileUrl == null &&
                                  (isMe || isModeratorOrAdmin)
                              ? () => _editMessage(
                                    msg,
                                    archive: isModeratorOrAdmin && !isMe,
                                  )
                              : null,
                          onImageTap: msg.imageUrl != null
                              ? () => _openImageFullscreen(context, msg.imageUrl!)
                              : null,
                        ),
                      ],
                    );
                  },
                  ),
                );
              },
            ),
          ),
          if (!isArchived)
            _InputBar(
              controller: _controller,
              onSend: _send,
              onSendImage: _pickingImage ? null : _sendImage,
              onSendFile: _pickingImage ? null : _sendFile,
              isRecording: _isRecording,
              recordingDuration: _recordingDuration,
              onStartRecording: _startRecording,
              onStopAndSend: _stopAndSend,
              onCancelRecording: _cancelRecording,
              onCreatePoll: isSheltered ? _showCreatePollDialog : null,
            ),
        ],
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _openImageFullscreen(BuildContext context, String imageUrl) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 5.0,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (_, child, progress) => progress == null
                      ? child
                      : const Center(
                          child: CircularProgressIndicator(color: Colors.white)),
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.broken_image, color: Colors.white, size: 64),
                ),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editMessage(Message msg, {bool archive = false}) async {
    final ctrl = TextEditingController(text: msg.text);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(archive ? 'Nachricht moderieren' : 'Nachricht bearbeiten'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: null,
          maxLength: 2000,
          decoration: const InputDecoration(border: OutlineInputBorder()),
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
    );
    if (confirmed != true || !mounted) return;
    final newText = ctrl.text.trim();
    if (newText.isEmpty || newText == msg.text) return;
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      await ref.read(chatServiceProvider).editMessage(
            widget.chatId,
            msg.id,
            newText,
            archive: archive,
            archivedByUid: archive ? currentUser?.uid : null,
            archivedByName: archive ? currentUser?.displayName : null,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

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
  final bool isModerating;
  final VoidCallback? onReport;
  final VoidCallback? onEdit;
  final VoidCallback? onImageTap;
  final String convId;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.convId,
    this.showSenderName = false,
    this.isModerating = false,
    this.onReport,
    this.onEdit,
    this.onImageTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final hasText = message.text.isNotEmpty &&
        message.pollId == null &&
        message.audioUrl == null &&
        message.imageUrl == null;

    return GestureDetector(
      onLongPress: () => showModalBottomSheet(
            context: context,
            builder: (_) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasText)
                    ListTile(
                      leading: const Icon(Icons.copy_outlined),
                      title: const Text('Text kopieren'),
                      onTap: () {
                        Navigator.pop(context);
                        Clipboard.setData(ClipboardData(text: message.text));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Text kopiert'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  if (onEdit != null)
                    ListTile(
                      leading: Icon(isModerating
                          ? Icons.shield_outlined
                          : Icons.edit_outlined),
                      title: Text(isModerating ? 'Moderieren' : 'Bearbeiten'),
                      onTap: () {
                        Navigator.pop(context);
                        onEdit!();
                      },
                    ),
                  if (onReport != null)
                    ListTile(
                      leading: const Icon(Icons.flag_outlined,
                          color: Colors.red),
                      title: const Text('Nachricht melden',
                          style: TextStyle(color: Colors.red)),
                      onTap: () {
                        Navigator.pop(context);
                        onReport!();
                      },
                    ),
                ],
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
            if (message.pollId != null)
              _PollBubble(
                convId: convId,
                pollId: message.pollId!,
                isMe: isMe,
              )
            else if (message.audioUrl != null)
              _VoicePlayer(
                audioUrl: message.audioUrl!,
                durationMs: message.audioDurationMs,
                isMe: isMe,
              )
            else if (message.imageUrl != null)
              // Feste Höhe verhindert, dass nachgeladene Bilder die
              // Listenhöhe ändern und so die Scroll-Position verschieben.
              GestureDetector(
                onTap: onImageTap,
                child: SizedBox(
                  width: 220,
                  height: 160,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      message.imageUrl!,
                      width: 220,
                      height: 160,
                      fit: BoxFit.cover,
                      loadingBuilder: (_, child, progress) => progress == null
                          ? child
                          : const Center(child: CircularProgressIndicator()),
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.broken_image),
                    ),
                  ),
                ),
              )
            else if (message.fileUrl != null)
              _FileBubble(message: message, isMe: isMe)
            else
              _LinkText(
                text: message.text,
                style: TextStyle(
                  color: message.isArchived
                      ? (isMe
                          ? colorScheme.onPrimary.withAlpha(160)
                          : Colors.grey[600])
                      : (isMe ? colorScheme.onPrimary : null),
                  fontStyle: message.isArchived
                      ? FontStyle.italic
                      : FontStyle.normal,
                ),
                linkColor: isMe
                    ? colorScheme.onPrimary
                    : colorScheme.primary,
              ),
            if (message.isArchived)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 11,
                      color: isMe
                          ? colorScheme.onPrimary.withAlpha(160)
                          : Colors.grey,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      message.archivedByName != null
                          ? 'von ${message.archivedByName} moderiert'
                          : 'von Moderator moderiert',
                      style: TextStyle(
                        fontSize: 10,
                        fontStyle: FontStyle.italic,
                        color: isMe
                            ? colorScheme.onPrimary.withAlpha(160)
                            : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.editedAt != null && !message.isArchived)
                  Text(
                    'bearbeitet · ',
                    style: TextStyle(
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                      color: isMe
                          ? colorScheme.onPrimary.withAlpha(160)
                          : Colors.grey,
                    ),
                  ),
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
  final VoidCallback? onSendFile;
  final bool isRecording;
  final Duration recordingDuration;
  final VoidCallback onStartRecording;
  final VoidCallback onStopAndSend;
  final VoidCallback onCancelRecording;
  final VoidCallback? onCreatePoll;

  const _InputBar({
    required this.controller,
    required this.onSend,
    this.onSendImage,
    this.onSendFile,
    required this.isRecording,
    required this.recordingDuration,
    required this.onStartRecording,
    required this.onStopAndSend,
    required this.onCancelRecording,
    this.onCreatePoll,
  });

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: isRecording ? _buildRecordingBar(context) : _buildNormalBar(context),
      ),
    );
  }

  Widget _buildRecordingBar(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          tooltip: 'Abbrechen',
          onPressed: onCancelRecording,
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.red.withAlpha(20),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.red.withAlpha(80)),
            ),
            child: Row(
              children: [
                const Icon(Icons.circle, color: Colors.red, size: 10),
                const SizedBox(width: 8),
                Text(
                  _formatDuration(recordingDuration),
                  style: const TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()]),
                ),
                const SizedBox(width: 8),
                const Text('Aufnahme läuft…',
                    style: TextStyle(color: Colors.grey, fontSize: 13)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: onStopAndSend,
          style: FilledButton.styleFrom(
            shape: const CircleBorder(),
            padding: const EdgeInsets.all(14),
          ),
          child: const Icon(Icons.send),
        ),
      ],
    );
  }

  void _showAttachMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Bild senden'),
              onTap: onSendImage == null
                  ? null
                  : () {
                      Navigator.pop(context);
                      onSendImage!();
                    },
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: const Text('Datei senden (max. 5 MB)'),
              onTap: onSendFile == null
                  ? null
                  : () {
                      Navigator.pop(context);
                      onSendFile!();
                    },
            ),
            ListTile(
              leading: const Icon(Icons.mic_outlined),
              title: const Text('Sprachaufnahme'),
              onTap: () {
                Navigator.pop(context);
                onStartRecording();
              },
            ),
            if (onCreatePoll != null)
              ListTile(
                leading: const Icon(Icons.poll_outlined),
                title: const Text('Umfrage erstellen'),
                onTap: () {
                  Navigator.pop(context);
                  onCreatePoll!();
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNormalBar(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          tooltip: 'Anhang',
          onPressed: () => _showAttachMenu(context),
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
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onSubmitted: (_) => onSend(),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.mic_outlined),
          tooltip: 'Sprachnachricht',
          onPressed: onStartRecording,
        ),
        FilledButton(
          onPressed: onSend,
          style: FilledButton.styleFrom(
            shape: const CircleBorder(),
            padding: const EdgeInsets.all(14),
          ),
          child: const Icon(Icons.send),
        ),
      ],
    );
  }
}

// ── Datei-Bubble ──────────────────────────────────────────────────────────────

class _FileBubble extends StatelessWidget {
  final Message message;
  final bool isMe;

  const _FileBubble({required this.message, required this.isMe});

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final nameColor = isMe ? colorScheme.onPrimary : colorScheme.onSurface;
    final subColor = isMe
        ? colorScheme.onPrimary.withAlpha(180)
        : colorScheme.onSurfaceVariant;

    return GestureDetector(
      onTap: () async {
        final uri = Uri.tryParse(message.fileUrl!);
        if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insert_drive_file_outlined, color: nameColor, size: 32),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.fileName ?? 'Datei',
                  style: TextStyle(
                    color: nameColor,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.underline,
                    decorationColor: nameColor,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (message.fileSizeBytes != null)
                  Text(
                    _formatSize(message.fileSizeBytes!),
                    style: TextStyle(fontSize: 11, color: subColor),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Link-fähiger Text ─────────────────────────────────────────────────────────

class _LinkText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final Color? linkColor;

  const _LinkText({required this.text, this.style, this.linkColor});

  static final _pattern = RegExp(
    r'(https?://[^\s]+|www\.[^\s]+|[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,})',
    caseSensitive: false,
  );

  Future<void> _launch(String raw) async {
    String urlStr = raw;
    if (!urlStr.startsWith('http') && urlStr.contains('@')) {
      urlStr = 'mailto:$urlStr';
    } else if (urlStr.startsWith('www.')) {
      urlStr = 'https://$urlStr';
    }
    final uri = Uri.tryParse(urlStr);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    int last = 0;
    for (final match in _pattern.allMatches(text)) {
      if (match.start > last) {
        spans.add(TextSpan(text: text.substring(last, match.start), style: style));
      }
      final raw = match.group(0)!;
      spans.add(TextSpan(
        text: raw,
        style: (style ?? const TextStyle()).copyWith(
          color: linkColor ?? Colors.blue,
          decoration: TextDecoration.underline,
          decorationColor: linkColor ?? Colors.blue,
        ),
        recognizer: TapGestureRecognizer()..onTap = () => _launch(raw),
      ));
      last = match.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last), style: style));
    }
    return RichText(text: TextSpan(children: spans));
  }
}

// ── Poll bubble ───────────────────────────────────────────────────────────────

class _PollBubble extends ConsumerStatefulWidget {
  final String convId;
  final String pollId;
  final bool isMe;

  const _PollBubble({
    required this.convId,
    required this.pollId,
    required this.isMe,
  });

  @override
  ConsumerState<_PollBubble> createState() => _PollBubbleState();
}

class _PollBubbleState extends ConsumerState<_PollBubble> {
  bool _voting = false;

  Future<void> _vote(String optionId) async {
    if (_voting) return;
    setState(() => _voting = true);
    try {
      await ref
          .read(chatServiceProvider)
          .castVote(widget.convId, widget.pollId, optionId);
    } finally {
      if (mounted) setState(() => _voting = false);
    }
  }

  Future<void> _close() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Umfrage beenden'),
        content: const Text(
            'Die Umfrage beenden? Danach kann nicht mehr abgestimmt werden.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Beenden')),
        ],
      ),
    );
    if (confirmed == true) {
      await ref
          .read(chatServiceProvider)
          .closePoll(widget.convId, widget.pollId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pollAsync = ref.watch(
        pollProvider((convId: widget.convId, pollId: widget.pollId)));
    final currentUid = FirebaseAuth.instance.currentUser!.uid;
    final scheme = Theme.of(context).colorScheme;
    final onColor = widget.isMe ? scheme.onPrimary : null;
    final labelColor = onColor ?? scheme.onSurface;
    final barColor = widget.isMe ? scheme.onPrimary.withAlpha(180) : scheme.primary;
    final barBg = widget.isMe
        ? scheme.onPrimary.withAlpha(40)
        : scheme.surfaceContainerHighest;

    return pollAsync.when(
      loading: () => const SizedBox(
          width: 200,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
      error: (e, _) =>
          Text('Fehler', style: TextStyle(fontSize: 12, color: onColor)),
      data: (poll) {
        if (poll == null) return const SizedBox.shrink();
        final hasVoted = poll.hasVoted(currentUid);
        final showResults = hasVoted || poll.isClosed;
        final canClose = !poll.isClosed && poll.createdBy == currentUid;

        return SizedBox(
          width: 260,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.poll_outlined,
                    size: 14, color: (onColor ?? Colors.grey).withAlpha(180)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    poll.isClosed ? 'Abgeschlossen' : 'Umfrage',
                    style: TextStyle(
                        fontSize: 11,
                        color: (onColor ?? Colors.grey).withAlpha(180)),
                  ),
                ),
                if (canClose)
                  GestureDetector(
                    onTap: _close,
                    child: Icon(Icons.stop_circle_outlined,
                        size: 16, color: onColor ?? Colors.red),
                  ),
              ]),
              const SizedBox(height: 6),
              Text(poll.question,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: labelColor)),
              const SizedBox(height: 8),
              ...poll.options.map((opt) {
                final count = poll.votesFor(opt.id).length;
                final total = poll.totalVoters;
                final pct = total > 0 ? count / total : 0.0;
                final myVote = poll.hasVotedFor(currentUid, opt.id);

                return GestureDetector(
                  onTap: (!poll.isClosed && !_voting) ? () => _vote(opt.id) : null,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(
                            myVote
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            size: 14,
                            color: myVote ? barColor : (onColor ?? Colors.grey),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                              child: Text(opt.text,
                                  style: TextStyle(
                                      fontSize: 13, color: labelColor))),
                          if (showResults)
                            Text('$count',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: (onColor ?? Colors.grey)
                                        .withAlpha(180))),
                        ]),
                        if (showResults) ...[
                          const SizedBox(height: 3),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: pct,
                              minHeight: 4,
                              backgroundColor: barBg,
                              valueColor: AlwaysStoppedAnimation<Color>(barColor),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }),
              Text(
                '${poll.totalVoters} '
                '${poll.totalVoters == 1 ? 'Stimme' : 'Stimmen'}',
                style: TextStyle(
                    fontSize: 11,
                    color: (onColor ?? Colors.grey).withAlpha(180)),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Voice message player ──────────────────────────────────────────────────────

class _VoicePlayer extends StatefulWidget {
  final String audioUrl;
  final int? durationMs;
  final bool isMe;

  const _VoicePlayer({
    required this.audioUrl,
    this.durationMs,
    required this.isMe,
  });

  @override
  State<_VoicePlayer> createState() => _VoicePlayerState();
}

class _VoicePlayerState extends State<_VoicePlayer> {
  final _player = AudioPlayer();
  PlayerState _state = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _total = Duration.zero;

  @override
  void initState() {
    super.initState();
    if (widget.durationMs != null) {
      _total = Duration(milliseconds: widget.durationMs!);
    }
    _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _state = s);
    });
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _total = d);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _position = Duration.zero);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_state == PlayerState.playing) {
      await _player.pause();
    } else {
      await _player.play(UrlSource(widget.audioUrl));
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = _state == PlayerState.playing;
    final progress = _total.inMilliseconds > 0
        ? (_position.inMilliseconds / _total.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final onColor =
        widget.isMe ? Theme.of(context).colorScheme.onPrimary : null;

    return SizedBox(
      width: 220,
      child: Row(
        children: [
          IconButton(
            icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow,
                color: onColor),
            onPressed: _togglePlay,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: progress,
                  backgroundColor: (onColor ?? Colors.grey).withAlpha(60),
                  color: onColor ?? Theme.of(context).colorScheme.primary,
                  minHeight: 3,
                  borderRadius: BorderRadius.circular(2),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_fmt(_position)} / ${_fmt(_total)}',
                  style: TextStyle(fontSize: 10, color: onColor ?? Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
