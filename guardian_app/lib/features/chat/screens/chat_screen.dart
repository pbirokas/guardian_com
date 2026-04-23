import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:guardian_app/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/models/conversation.dart';
import '../../../core/models/message.dart';
import '../../../core/widgets/help_sheet.dart';
import '../../../core/providers/chat_font_size_provider.dart';
import '../../../core/models/org_member.dart';
import '../../../core/models/organization.dart';
import '../../../core/models/scheduled_message.dart';
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
  Message? _replyingTo;

  // ── Geplante Nachrichten ───────────────────────────────────────────────────
  Timer? _scheduleTimer;

  // ── Tipp-Indikator ────────────────────────────────────────────────────────
  Timer? _typingTimer;
  bool _isTyping = false;

  // ── Suche ──────────────────────────────────────────────────────────────────
  bool _isSearching = false;
  String _searchQuery = '';
  final _searchController = TextEditingController();

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
    _controller.addListener(_onTextChanged);
    // Jede Minute prüfen ob eine geplante Nachricht fällig ist
    _scheduleTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _checkScheduledMessages(),
    );
  }

  void _onTextChanged() {
    if (!_isParticipant) return;
    if (_controller.text.trim().isNotEmpty) {
      if (!_isTyping) {
        _isTyping = true;
        ref.read(chatServiceProvider).setTyping(widget.chatId, true).catchError((_) {});
      }
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 4), () {
        _isTyping = false;
        ref.read(chatServiceProvider).setTyping(widget.chatId, false).catchError((_) {});
      });
    } else if (_isTyping) {
      _typingTimer?.cancel();
      _isTyping = false;
      ref.read(chatServiceProvider).setTyping(widget.chatId, false).catchError((_) {});
    }
  }

  Future<void> _setReaction(Message msg, String? emoji) async {
    try {
      await ref.read(chatServiceProvider).setReaction(widget.chatId, msg.id, emoji);
    } catch (_) {}
  }

  void _onScroll() {
    final pos = _scrollController.position;
    // Mit reverse:true ist pixels=0 unten (neueste Nachrichten).
    _atBottom = pos.pixels <= 150;

    // Nur laden wenn der User aktiv nach oben scrollt (hohe Pixel-Werte) —
    // nicht beim Rückprall (ScrollDirection.reverse) nach einem Overscroll.
    if (pos.pixels >= pos.maxScrollExtent - 80 &&
        pos.maxScrollExtent > 0 &&
        pos.userScrollDirection != ScrollDirection.reverse &&
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

  bool get _isParticipant {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    final conv = ref.read(conversationProvider(widget.chatId)).value;
    return conv == null || conv.participantUids.contains(uid);
  }

  void _markRead() {
    if (!_isParticipant) return;
    ref.read(chatServiceProvider).markAsRead(widget.chatId).catchError((_) {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _typingTimer?.cancel();
    if (_isTyping) {
      ref.read(chatServiceProvider).setTyping(widget.chatId, false).catchError((_) {});
    }
    _controller.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    _scheduleTimer?.cancel();
    _recordingTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _checkScheduledMessages() async {
    final now = DateTime.now();
    final service = ref.read(chatServiceProvider);
    try {
      final snapshot = await service.watchScheduledMessages(widget.chatId).first;
      for (final sm in snapshot) {
        if (sm.scheduledFor.isBefore(now) || sm.scheduledFor.isAtSameMomentAs(now)) {
          await service.sendScheduledMessage(sm);
        }
      }
    } catch (_) {}
  }

  Future<void> _showScheduleDialog() async {
    final l = AppLocalizations.of(context);
    final text = _controller.text.trim();

    // Datum wählen
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(hours: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;

    // Uhrzeit wählen
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
          DateTime.now().add(const Duration(hours: 1))),
    );
    if (time == null || !mounted) return;

    final scheduledFor = DateTime(
        date.year, date.month, date.day, time.hour, time.minute);

    if (scheduledFor.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.scheduleFor)),
      );
      return;
    }

    // Text aus Eingabefeld oder eigenen eingeben
    final textToSchedule = text.isNotEmpty ? text : await _askScheduleText();
    if (textToSchedule == null || textToSchedule.isEmpty || !mounted) return;

    try {
      await ref.read(chatServiceProvider)
          .scheduleMessage(widget.chatId, textToSchedule, scheduledFor);
      if (text.isNotEmpty) _controller.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l.scheduledAt(_formatScheduledTime(scheduledFor))),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.errorMessage(e.toString()))),
        );
      }
    }
  }

  Future<String?> _askScheduleText() async {
    final ctrl = TextEditingController();
    final l = AppLocalizations.of(context);
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        final ld = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(ld.scheduleMessage),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            maxLines: null,
            maxLength: 2000,
            decoration: InputDecoration(
              hintText: l.messageHint,
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(ld.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text(ld.create),
            ),
          ],
        );
      },
    );
  }

  String _formatScheduledTime(DateTime dt) {
    final d = '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
    final t = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '$d $t';
  }

  // ── Voice recording methods ────────────────────────────────────────────────

  Future<void> _startRecording() async {
    final l = AppLocalizations.of(context);
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.microphoneDenied)),
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
    final l = AppLocalizations.of(context);
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
        messenger.showSnackBar(SnackBar(content: Text(l.errorMessage(e.toString()))));
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
    var isAnonymous = false;
    DateTime? expiresAt;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final ld = AppLocalizations.of(ctx);
          return AlertDialog(
            title: Text(ld.createPollTitle),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: questionCtrl,
                    autofocus: true,
                    maxLength: 200,
                    decoration: InputDecoration(
                      labelText: ld.pollQuestion,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(ld.pollOptions,
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
                      label: Text(ld.addOption),
                    ),
                  SwitchListTile(
                    value: multipleChoice,
                    onChanged: (v) => setState(() => multipleChoice = v),
                    title: Text(ld.multipleChoice,
                        style: const TextStyle(fontSize: 14)),
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile(
                    value: isAnonymous,
                    onChanged: (v) => setState(() => isAnonymous = v),
                    title: Row(
                      children: [
                        Text(ld.anonymousPoll,
                            style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 6),
                        const Icon(Icons.lock_outline, size: 14,
                            color: Colors.grey),
                      ],
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const Divider(height: 16),
                  Row(
                    children: [
                      Icon(Icons.schedule_outlined,
                          size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          expiresAt == null
                              ? ld.noExpiry
                              : '${expiresAt!.day.toString().padLeft(2, '0')}.'
                                '${expiresAt!.month.toString().padLeft(2, '0')}.'
                                '${expiresAt!.year}  '
                                '${expiresAt!.hour.toString().padLeft(2, '0')}:'
                                '${expiresAt!.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey[700]),
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 0),
                            tapTargetSize:
                                MaterialTapTargetSize.shrinkWrap),
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: ctx,
                            initialDate: expiresAt ??
                                DateTime.now().add(
                                    const Duration(days: 1)),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now()
                                .add(const Duration(days: 365)),
                          );
                          if (date == null) return;
                          final time = await showTimePicker(
                            // ignore: use_build_context_synchronously
                            context: ctx,
                            initialTime: TimeOfDay(
                                hour: expiresAt?.hour ?? 23,
                                minute: expiresAt?.minute ?? 59),
                          );
                          if (time == null) return;
                          setState(() {
                            expiresAt = DateTime(date.year, date.month,
                                date.day, time.hour, time.minute);
                          });
                        },
                        child: Text(ld.addExpiry,
                            style: const TextStyle(fontSize: 12)),
                      ),
                      if (expiresAt != null)
                        IconButton(
                          icon: const Icon(Icons.close,
                              size: 16, color: Colors.grey),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () =>
                              setState(() => expiresAt = null),
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
                child: Text(ld.create),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true || !mounted) return;
    final question = questionCtrl.text.trim();
    final options = optionCtrls
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    if (question.isEmpty || options.length < 2) return;

    final l = AppLocalizations.of(context);
    try {
      await ref.read(chatServiceProvider).createPoll(
            widget.chatId,
            question: question,
            optionTexts: options,
            multipleChoice: multipleChoice,
            isAnonymous: isAnonymous,
            expiresAt: expiresAt,
          );
      _markRead();
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.errorMessage(e.toString()))));
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

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      // Mit reverse:true ist 0.0 immer die unterste Position – kein
      // Layout-Shift durch nachladende Bilder möglich.
      _scrollController.jumpTo(0);
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    _typingTimer?.cancel();
    if (_isTyping) {
      _isTyping = false;
      ref.read(chatServiceProvider).setTyping(widget.chatId, false).catchError((_) {});
    }
    final reply = _replyingTo;
    setState(() => _replyingTo = null);
    final l = AppLocalizations.of(context);
    try {
      await ref.read(chatServiceProvider).sendMessage(
            widget.chatId,
            text,
            replyToId: reply?.id,
            replyToSenderName: reply?.senderName,
            replyToText: reply != null
                ? (reply.imageUrl != null
                    ? '🖼'
                    : reply.audioUrl != null
                        ? '🎤'
                        : reply.fileUrl != null
                            ? reply.fileName ?? '📎'
                            : reply.text)
                : null,
          );
      _markRead();
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.sendError(e.toString()))),
        );
      }
    }
  }

  Future<void> _sendImage() async {
    if (_pickingImage) return;
    setState(() => _pickingImage = true);
    final l = AppLocalizations.of(context);
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
          SnackBar(content: Text(l.sendError(e.toString()))),
        );
      }
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  Future<void> _sendFile() async {
    if (_pickingImage) return;
    setState(() => _pickingImage = true);
    final l = AppLocalizations.of(context);
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
          SnackBar(content: Text(l.sendError(e.toString()))),
        );
      }
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  Future<void> _showAddMemberDialog(BuildContext context, Conversation conv,
      List<OrgMember> allMembers) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // Nur Mitglieder anzeigen die noch nicht im Chat sind
    final available = allMembers
        .where((m) => !conv.participantUids.contains(m.uid))
        .toList();

    if (available.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.allMembersInChat)),
      );
      return;
    }

    final selected = <String>{};
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final ld = AppLocalizations.of(ctx);
          return AlertDialog(
            title: Text(ld.addMemberTitle),
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
                child: Text(ld.cancel),
              ),
              FilledButton(
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.pop(ctx, true),
                child: Text(ld.add),
              ),
            ],
          );
        },
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
          messenger.showSnackBar(SnackBar(content: Text(l.errorMessage(e.toString()))));
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
        builder: (ctx, setDialogState) {
          final ld = AppLocalizations.of(ctx);
          return AlertDialog(
            title: Text('${ld.membersTooltip} (${participants.length})'),
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
                                  tooltip: ld.remove,
                                  onPressed: () async {
                                    final confirmed =
                                        await showDialog<bool>(
                                      context: ctx,
                                      builder: (c) {
                                        final lc = AppLocalizations.of(c);
                                        return AlertDialog(
                                          title: Text(lc.removeMembersTitle),
                                          content: Text(lc.removeMemberFromChat(m.displayName)),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(c, false),
                                              child: Text(lc.cancel),
                                            ),
                                            FilledButton(
                                              style: FilledButton.styleFrom(
                                                  backgroundColor: Colors.red),
                                              onPressed: () =>
                                                  Navigator.pop(c, true),
                                              child: Text(lc.remove),
                                            ),
                                          ],
                                        );
                                      },
                                    );
                                    if (confirmed == true && mounted) {
                                      final messenger =
                                          ScaffoldMessenger.of(context);
                                      try {
                                        await ref
                                            .read(chatServiceProvider)
                                            .removeMemberFromConversation(
                                                conv.id, m.uid,
                                                memberName: m.displayName);
                                        setDialogState(() =>
                                            participants.remove(m));
                                      } catch (e) {
                                        if (mounted) {
                                          messenger.showSnackBar(SnackBar(
                                              content: Text(ld.errorMessage(e.toString()))));
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
                child: Text(ld.close),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
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

    final scheduledMessages =
        ref.watch(scheduledMessagesProvider(widget.chatId)).value ?? [];

    return Scaffold(
      appBar: _isSearching
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() {
                  _isSearching = false;
                  _searchQuery = '';
                  _searchController.clear();
                }),
              ),
              title: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: l.searchHint,
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _searchQuery = v.trim()),
              ),
              actions: [
                if (_searchQuery.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      _searchQuery = '';
                      _searchController.clear();
                    }),
                  ),
              ],
            )
          : AppBar(
              title: Text(title),
              actions: [
                IconButton(
                  icon: const Icon(Icons.help_outline),
                  tooltip: '?',
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => HelpSheet(
                        screenTitle: l.helpChatTitle,
                        topics: [
                          HelpTopic(
                            icon: Icons.edit_outlined,
                            title: l.helpChatWriteTitle,
                            body: l.helpChatWriteBody,
                          ),
                          HelpTopic(
                            icon: Icons.attach_file_outlined,
                            title: l.helpChatMediaTitle,
                            body: l.helpChatMediaBody,
                          ),
                          HelpTopic(
                            icon: Icons.reply_outlined,
                            title: l.helpChatReactTitle,
                            body: l.helpChatReactBody,
                          ),
                          HelpTopic(
                            icon: Icons.schedule_outlined,
                            title: l.helpChatScheduleTitle,
                            body: l.helpChatScheduleBody,
                          ),
                          HelpTopic(
                            icon: Icons.manage_accounts_outlined,
                            title: l.helpChatModerateTitle,
                            body: l.helpChatModerateBody,
                          ),
                          HelpTopic(
                            icon: Icons.flag_outlined,
                            title: l.helpChatReportTitle,
                            body: l.helpChatReportBody,
                          ),
                        ],
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: l.searchMessages,
                  onPressed: () => setState(() => _isSearching = true),
                ),
                if (conv != null && conv.isGroup)
                  IconButton(
                    icon: const Icon(Icons.group_outlined),
                    tooltip: l.membersTooltip,
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
                      PopupMenuItem(
                        value: 'add_member',
                        child: ListTile(
                          leading: const Icon(Icons.person_add_outlined),
                          title: Text(l.addMemberTitle),
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
                  Text(l.archivedReadOnly,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
            ),
          if (conv != null && conv.pinnedMessageId != null)
            _PinnedMessageBanner(
              text: conv.pinnedMessageText ?? '',
              canManage: isModeratorOrAdmin,
              onUnpin: () => ref
                  .read(chatServiceProvider)
                  .unpinMessage(widget.chatId),
            ),
          if (scheduledMessages.isNotEmpty)
            _ScheduledMessagesBanner(
              messages: scheduledMessages,
              convId: widget.chatId,
            ),
          Expanded(
            child: messagesAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(l.errorMessage(e.toString()))),
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

                // Suche: Nachrichten filtern
                final query = _searchQuery.toLowerCase();
                final filtered = query.isEmpty
                    ? messages
                    : messages
                        .where((m) => m.text.toLowerCase().contains(query))
                        .toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      query.isNotEmpty ? l.searchNoResults : l.noMessages,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  );
                }
                final mayHaveMore =
                    query.isEmpty && messages.length >= _limit;
                _mayHaveMore = mayHaveMore;
                return Column(
                  children: [
                    if (query.isNotEmpty)
                      Container(
                        width: double.infinity,
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        child: Text(
                          filtered.isEmpty
                              ? l.searchNoResults
                              : l.searchResults(filtered.length),
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    Expanded(
                      child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  child: ListView.builder(
                  controller: _scrollController,
                  physics: const ClampingScrollPhysics(),
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length + (mayHaveMore ? 1 : 0),
                  itemBuilder: (ctx, i) {
                    // Mit reverse:true ist i=0 die unterste (neueste) Nachricht.
                    // Der „Ältere laden"-Button erscheint am Ende der Liste (oben).
                    if (mayHaveMore && i == filtered.length) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
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
                                  label: Text(l.olderMessages,
                                      style: const TextStyle(fontSize: 12)),
                                ),
                        ),
                      );
                    }
                    // Neueste Nachricht zuerst (i=0 → letzter Eintrag in filtered)
                    final msg = filtered[filtered.length - 1 - i];
                    final isMe = msg.senderUid == currentUid;
                    // „older" ist die Nachricht, die im reversed ListView darüber
                    // erscheint (also die chronologisch ältere).
                    final older = (i + 1 < filtered.length)
                        ? filtered[filtered.length - 2 - i]
                        : null;
                    final showDate = older == null ||
                        !_sameDay(older.sentAt, msg.sentAt);
                    final showSender = !isMe &&
                        (older == null || older.senderUid != msg.senderUid);
                    return Column(
                      children: [
                        if (showDate) _DateDivider(date: msg.sentAt),
                        _MessageBubble(
                          message: msg,
                          isMe: isMe,
                          convId: widget.chatId,
                          currentUid: currentUid,
                          showSenderName:
                              showSender && msg.senderName.isNotEmpty,
                          isModerating: isModeratorOrAdmin && !isMe,
                          readStatus: isMe && conv != null
                              ? _readStatus(conv, msg)
                              : null,
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
                          onReply: isArchived
                              ? null
                              : () => setState(() {
                                    _replyingTo = msg;
                                    _controller.selection =
                                        TextSelection.fromPosition(
                                      TextPosition(
                                          offset: _controller.text.length),
                                    );
                                  }),
                          onReact: isArchived
                              ? null
                              : (emoji) => _setReaction(msg, emoji),
                          onPin: isModeratorOrAdmin && !isArchived
                              ? () {
                                  final isPinned =
                                      conv.pinnedMessageId == msg.id;
                                  if (isPinned) {
                                    ref
                                        .read(chatServiceProvider)
                                        .unpinMessage(widget.chatId);
                                  } else {
                                    ref
                                        .read(chatServiceProvider)
                                        .pinMessage(widget.chatId, msg.id,
                                            msg.text);
                                  }
                                }
                              : null,
                          isPinned: conv?.pinnedMessageId == msg.id,
                          members: members,
                        ),
                      ],
                    );
                  },
                  ),
                ),
              ),
            ],
          );
              },
            ),
          ),
          if (!isArchived) ...[
            if (conv != null)
              _TypingIndicator(
                conv: conv,
                currentUid: currentUid,
                members: members,
              ),
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
              onSchedule: _showScheduleDialog,
              replyMessage: _replyingTo,
              onCancelReply: () => setState(() => _replyingTo = null),
            ),
          ],
        ],
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// null  = fremde Nachricht (kein Indikator)
  /// 0     = gesendet (noch kein anderer hat gelesen)
  /// 1     = mindestens einer hat gelesen
  /// 2     = alle haben gelesen
  int _readStatus(Conversation conv, Message msg) {
    final others = conv.participantUids
        .where((uid) => uid != FirebaseAuth.instance.currentUser!.uid)
        .toList();
    if (others.isEmpty) return 2;
    final readCount = others
        .where((uid) =>
            conv.lastReadAt[uid]?.isAfter(msg.sentAt) == true ||
            conv.lastReadAt[uid] == msg.sentAt)
        .length;
    if (readCount == 0) return 0;
    if (readCount < others.length) return 1;
    return 2;
  }

  void _openImageFullscreen(BuildContext context, String imageUrl) {
    showDialog<void>(
      context: context,
      builder: (_) => _FullscreenImageDialog(imageUrl: imageUrl),
    );
  }


  Future<void> _editMessage(Message msg, {bool archive = false}) async {
    final ctrl = TextEditingController(text: msg.text);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final ld = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(archive ? ld.moderate : 'Nachricht bearbeiten'),
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
              child: Text(ld.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ld.save),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    final newText = ctrl.text.trim();
    if (newText.isEmpty || newText == msg.text) return;
    final l = AppLocalizations.of(context);
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
            .showSnackBar(SnackBar(content: Text(l.errorMessage(e.toString()))));
      }
    }
  }

  Future<void> _confirmReport(Conversation conv, Message msg) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final ld = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(ld.reportMessage),
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
              child: Text(ld.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Melden'),
            ),
          ],
        );
      },
    );
    if (confirmed == true && mounted) {
      final l = AppLocalizations.of(context);
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
            .showSnackBar(SnackBar(content: Text(l.errorMessage(e.toString()))));
      }
    }
  }
}

class _MessageBubble extends ConsumerWidget {
  final Message message;
  final bool isMe;
  final bool showSenderName;
  final bool isModerating;
  final VoidCallback? onReport;
  final VoidCallback? onEdit;
  final VoidCallback? onImageTap;
  final VoidCallback? onReply;
  final void Function(String? emoji)? onReact;
  final VoidCallback? onPin;
  final bool isPinned;
  final String convId;
  final String currentUid;
  // null = fremde Nachricht, 0 = gesendet, 1 = teilweise gelesen, 2 = alle gelesen
  final int? readStatus;
  final List<OrgMember>? members;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.convId,
    required this.currentUid,
    this.showSenderName = false,
    this.isModerating = false,
    this.onReport,
    this.onEdit,
    this.onImageTap,
    this.onReply,
    this.onReact,
    this.onPin,
    this.isPinned = false,
    this.readStatus,
    this.members,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final chatFontSize = ref.watch(chatFontSizeProvider);

    // System-Nachrichten (Mitglied hinzugefügt/entfernt) separat rendern
    if (message.type == 'system') {
      final target = message.systemTargetName ?? '';
      final text = switch (message.systemEvent) {
        'memberAdded' => l.systemMemberAdded(target),
        'memberRemoved' => l.systemMemberRemoved(target),
        _ => target,
      };
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withAlpha(200),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

    final hasText = message.text.isNotEmpty &&
        message.pollId == null &&
        message.audioUrl == null &&
        message.imageUrl == null;

    final myReaction = message.reactions[currentUid];

    return GestureDetector(
      onLongPress: () => showModalBottomSheet(
            context: context,
            builder: (_) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onReact != null) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: ['👍', '❤️', '😂', '😮', '😢', '😡', '👎']
                            .map((e) => GestureDetector(
                                  onTap: () {
                                    Navigator.pop(context);
                                    onReact!(myReaction == e ? null : e);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: myReaction == e
                                          ? Theme.of(context)
                                              .colorScheme
                                              .primaryContainer
                                          : null,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(e,
                                        style: const TextStyle(fontSize: 26)),
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                    const Divider(height: 1),
                  ],
                  if (onReply != null)
                    ListTile(
                      leading: const Icon(Icons.reply_outlined),
                      title: Text(l.reply),
                      onTap: () {
                        Navigator.pop(context);
                        onReply!();
                      },
                    ),
                  if (onPin != null)
                    ListTile(
                      leading: Icon(isPinned
                          ? Icons.push_pin
                          : Icons.push_pin_outlined),
                      title: Text(isPinned ? l.unpinMessage : l.pinMessage),
                      onTap: () {
                        Navigator.pop(context);
                        onPin!();
                      },
                    ),
                  if (hasText)
                    ListTile(
                      leading: const Icon(Icons.copy_outlined),
                      title: Text(l.copyText),
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
                      title: Text(isModerating ? l.moderate : l.edit),
                      onTap: () {
                        Navigator.pop(context);
                        onEdit!();
                      },
                    ),
                  if (onReport != null)
                    ListTile(
                      leading: const Icon(Icons.flag_outlined,
                          color: Colors.red),
                      title: Text(l.reportMessage,
                          style: const TextStyle(color: Colors.red)),
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
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
        Container(
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
              : colorScheme.secondaryContainer,
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
                    color: isMe
                        ? colorScheme.onPrimary.withAlpha(200)
                        : colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            if (message.replyToId != null)
              _ReplyQuote(
                senderName: message.replyToSenderName ?? '',
                text: message.replyToText ?? '',
                isMe: isMe,
              ),
            if (message.pollId != null)
              _PollBubble(
                convId: convId,
                pollId: message.pollId!,
                isMe: isMe,
                members: members,
              )
            else if (message.audioUrl != null)
              _VoicePlayer(
                audioUrl: message.audioUrl!,
                durationMs: message.audioDurationMs,
                isMe: isMe,
              )
            else if (message.imageUrl != null)
              GestureDetector(
                onTap: onImageTap,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: message.imageUrl!,
                    width: 220,
                    height: 160,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => const SizedBox(
                      width: 220,
                      height: 160,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    errorWidget: (_, _, _) => const SizedBox(
                      width: 220,
                      height: 160,
                      child: Icon(Icons.broken_image),
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
                  fontSize: chatFontSize,
                  color: message.isArchived
                      ? (isMe
                          ? colorScheme.onPrimary.withAlpha(160)
                          : colorScheme.onSecondaryContainer.withAlpha(160))
                      : (isMe
                          ? colorScheme.onPrimary
                          : colorScheme.onSecondaryContainer),
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
                          : colorScheme.onSecondaryContainer.withAlpha(160),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      message.archivedByName != null
                          ? l.moderatedBy(message.archivedByName!)
                          : l.moderatedByModerator,
                      style: TextStyle(
                        fontSize: 10,
                        fontStyle: FontStyle.italic,
                        color: isMe
                            ? colorScheme.onPrimary.withAlpha(160)
                            : colorScheme.onSecondaryContainer.withAlpha(160),
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
                    l.editedPrefix,
                    style: TextStyle(
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                      color: isMe
                          ? colorScheme.onPrimary.withAlpha(160)
                          : colorScheme.onSecondaryContainer.withAlpha(160),
                    ),
                  ),
                Text(
                  _formatTime(message.sentAt),
                  style: TextStyle(
                    fontSize: 10,
                    color: isMe
                        ? colorScheme.onPrimary.withAlpha(180)
                        : colorScheme.onSecondaryContainer.withAlpha(180),
                  ),
                ),
                if (readStatus != null) ...[
                  const SizedBox(width: 3),
                  _ReadTicks(
                    status: readStatus!,
                    color: colorScheme.onPrimary,
                  ),
                ],
              ],
            ),
          ],
        ),
        ),
        if (message.reactions.isNotEmpty)
          _ReactionChips(
            reactions: message.reactions,
            currentUid: currentUid,
            isMe: isMe,
            onTap: onReact,
          ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

// ── Geplante Nachrichten Banner ───────────────────────────────────────────────

class _ScheduledMessagesBanner extends ConsumerWidget {
  final List<ScheduledMessage> messages;
  final String convId;

  const _ScheduledMessagesBanner(
      {required this.messages, required this.convId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return ExpansionTile(
      leading: Icon(Icons.schedule_outlined,
          size: 18, color: colorScheme.primary),
      title: Text(
        l.scheduledMessages(messages.length),
        style: TextStyle(fontSize: 13, color: colorScheme.primary),
      ),
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      childrenPadding: EdgeInsets.zero,
      children: messages.map((sm) {
        final time =
            '${sm.scheduledFor.day.toString().padLeft(2, '0')}.${sm.scheduledFor.month.toString().padLeft(2, '0')}.${sm.scheduledFor.year} '
            '${sm.scheduledFor.hour.toString().padLeft(2, '0')}:${sm.scheduledFor.minute.toString().padLeft(2, '0')}';
        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: const Icon(Icons.access_time, size: 16),
          title: Text(sm.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13)),
          subtitle: Text(l.scheduledAt(time),
              style: const TextStyle(fontSize: 11)),
          trailing: IconButton(
            icon: const Icon(Icons.close, size: 16),
            tooltip: l.cancelScheduled,
            onPressed: () => ref
                .read(chatServiceProvider)
                .deleteScheduledMessage(convId, sm.id),
          ),
        );
      }).toList(),
    );
  }
}

// ── Reply-Zitat in der Bubble ─────────────────────────────────────────────────

class _ReplyQuote extends StatelessWidget {
  final String senderName;
  final String text;
  final bool isMe;

  const _ReplyQuote({
    required this.senderName,
    required this.text,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bgColor = isMe
        ? colorScheme.onPrimary.withAlpha(40)
        : colorScheme.onSecondaryContainer.withAlpha(25);
    final borderColor = isMe
        ? colorScheme.onPrimary.withAlpha(120)
        : colorScheme.onSecondaryContainer.withAlpha(120);
    final nameColor = isMe
        ? colorScheme.onPrimary
        : colorScheme.onSecondaryContainer;
    final textColor = isMe
        ? colorScheme.onPrimary.withAlpha(200)
        : colorScheme.onSecondaryContainer.withAlpha(180);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border(
          left: BorderSide(color: borderColor, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            senderName,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: nameColor,
            ),
          ),
          Text(
            text,
            style: TextStyle(fontSize: 12, color: textColor),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ── Lesebestätigung ───────────────────────────────────────────────────────────

class _ReadTicks extends StatelessWidget {
  final int status; // 0 = gesendet, 1 = teilweise gelesen, 2 = alle gelesen
  final Color color;

  const _ReadTicks({required this.status, required this.color});

  @override
  Widget build(BuildContext context) {
    if (status == 0) {
      // Einzelner Haken — gesendet
      return Icon(Icons.done, size: 12, color: color.withAlpha(160));
    }
    // Doppelter Haken — status 1: grau (teilweise), status 2: blau (alle)
    final tickColor = status == 2 ? Colors.lightBlueAccent : color.withAlpha(160);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(Icons.done, size: 12, color: tickColor),
        Positioned(
          left: 5,
          child: Icon(Icons.done, size: 12, color: tickColor),
        ),
        const SizedBox(width: 17, height: 12),
      ],
    );
  }
}

class _DateDivider extends StatelessWidget {
  final DateTime date;

  const _DateDivider({required this.date});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final now = DateTime.now();
    String label;
    if (date.day == now.day && date.month == now.month) {
      label = l.today;
    } else if (date.day == now.day - 1 && date.month == now.month) {
      label = l.yesterday;
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

// ── Angepinnte Nachricht ──────────────────────────────────────────────────────

class _PinnedMessageBanner extends StatelessWidget {
  final String text;
  final bool canManage;
  final VoidCallback onUnpin;

  const _PinnedMessageBanner({
    required this.text,
    required this.canManage,
    required this.onUnpin,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.primaryContainer.withAlpha(180),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(Icons.push_pin, size: 14, color: colorScheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.pinnedMessage,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary),
                ),
                Text(
                  text,
                  style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onPrimaryContainer),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (canManage)
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: l.unpinMessage,
              onPressed: onUnpin,
            ),
        ],
      ),
    );
  }
}

// ── Tipp-Indikator ────────────────────────────────────────────────────────────

class _TypingIndicator extends StatelessWidget {
  final Conversation conv;
  final String currentUid;
  final List<OrgMember>? members;

  const _TypingIndicator({
    required this.conv,
    required this.currentUid,
    required this.members,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final now = DateTime.now();
    final active = conv.typingUsers.entries
        .where((e) =>
            e.key != currentUid &&
            now.difference(e.value).inSeconds < 10)
        .map((e) {
          final m = members?.where((m) => m.uid == e.key).firstOrNull;
          return m?.displayName ?? '…';
        })
        .toList();

    if (active.isEmpty) return const SizedBox.shrink();

    final label = active.length == 1
        ? l.typingOne(active.first)
        : l.typingMultiple(active.join(', '));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          _DotsAnimation(),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DotsAnimation extends StatefulWidget {
  @override
  State<_DotsAnimation> createState() => _DotsAnimationState();
}

class _DotsAnimationState extends State<_DotsAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = (_ctrl.value * 3 - i).clamp(0.0, 1.0);
            final opacity = (phase < 0.5 ? phase : 1.0 - phase) * 2;
            return Container(
              width: 5,
              height: 5,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withAlpha((opacity * 200).toInt()),
              ),
            );
          }),
        );
      },
    );
  }
}

// ── Nachrichten-Reaktionen ────────────────────────────────────────────────────

class _ReactionChips extends StatelessWidget {
  final Map<String, String> reactions;
  final String currentUid;
  final bool isMe;
  final void Function(String? emoji)? onTap;

  const _ReactionChips({
    required this.reactions,
    required this.currentUid,
    required this.isMe,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Group by emoji
    final counts = <String, int>{};
    for (final emoji in reactions.values) {
      counts[emoji] = (counts[emoji] ?? 0) + 1;
    }
    final myEmoji = reactions[currentUid];

    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 4),
      child: Wrap(
        alignment: isMe ? WrapAlignment.end : WrapAlignment.start,
        spacing: 4,
        children: counts.entries.map((e) {
          final isMyReaction = myEmoji == e.key;
          return GestureDetector(
            onTap: () => onTap?.call(isMyReaction ? null : e.key),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
  final VoidCallback? onSchedule;
  final Message? replyMessage;
  final VoidCallback? onCancelReply;

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
    this.onSchedule,
    this.replyMessage,
    this.onCancelReply,
  });

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (replyMessage != null)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                border: Border(
                  top: BorderSide(color: colorScheme.outlineVariant),
                  left: BorderSide(color: colorScheme.primary, width: 3),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.replyingTo(replyMessage!.senderName),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                        Text(
                          replyMessage!.imageUrl != null
                              ? '🖼'
                              : replyMessage!.audioUrl != null
                                  ? '🎤'
                                  : replyMessage!.fileUrl != null
                                      ? replyMessage!.fileName ?? '📎'
                                      : replyMessage!.text,
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: onCancelReply,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: isRecording
                ? _buildRecordingBar(context)
                : _buildNormalBar(context),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingBar(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          tooltip: l.cancel,
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
                Text(l.recordingIndicator,
                    style: const TextStyle(color: Colors.grey, fontSize: 13)),
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
    final l = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: Text(l.sendImage),
              onTap: onSendImage == null
                  ? null
                  : () {
                      Navigator.pop(context);
                      onSendImage!();
                    },
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: Text(l.sendFile),
              onTap: onSendFile == null
                  ? null
                  : () {
                      Navigator.pop(context);
                      onSendFile!();
                    },
            ),
            ListTile(
              leading: const Icon(Icons.mic_outlined),
              title: Text(l.voiceRecording),
              onTap: () {
                Navigator.pop(context);
                onStartRecording();
              },
            ),
            if (onCreatePoll != null)
              ListTile(
                leading: const Icon(Icons.poll_outlined),
                title: Text(l.createPoll),
                onTap: () {
                  Navigator.pop(context);
                  onCreatePoll!();
                },
              ),
            ListTile(
              leading: const Icon(Icons.schedule_outlined),
              title: Text(l.scheduleMessage),
              onTap: () {
                Navigator.pop(context);
                onSchedule?.call();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNormalBar(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          tooltip: l.attachmentTooltip,
          onPressed: () => _showAttachMenu(context),
        ),
        Expanded(
          child: TextField(
            controller: controller,
            textCapitalization: TextCapitalization.sentences,
            maxLines: null,
            decoration: InputDecoration(
              hintText: l.messageHint,
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
    final nameColor = isMe
        ? colorScheme.onPrimary
        : colorScheme.onSecondaryContainer;
    final subColor = isMe
        ? colorScheme.onPrimary.withAlpha(180)
        : colorScheme.onSecondaryContainer.withAlpha(180);

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
  final List<OrgMember>? members;

  const _PollBubble({
    required this.convId,
    required this.pollId,
    required this.isMe,
    this.members,
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
      builder: (ctx) {
        final ld = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(ld.endPollTitle),
          content: Text(ld.endPollContent),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(ld.cancel)),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(ld.endPoll)),
          ],
        );
      },
    );
    if (confirmed == true) {
      await ref
          .read(chatServiceProvider)
          .closePoll(widget.convId, widget.pollId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
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
        final isExpired = poll.expiresAt != null &&
            DateTime.now().isAfter(poll.expiresAt!);
        final effectivelyClosed = poll.isClosed || isExpired;
        final hasVoted = poll.hasVoted(currentUid);
        final showResults = hasVoted || effectivelyClosed;
        final canClose = !effectivelyClosed && poll.createdBy == currentUid;
        final dimColor = (onColor ?? Colors.grey).withAlpha(180);

        void showVoters(String optionText, List<String> voterUids) {
          final names = voterUids.map((uid) {
            final m = widget.members?.where((m) => m.uid == uid).firstOrNull;
            return m?.displayName ?? uid;
          }).toList()..sort();
          showDialog<void>(
            context: context,
            builder: (ctx) {
              final ld = AppLocalizations.of(ctx);
              return AlertDialog(
                title: Text(ld.pollVotersTitle),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(optionText,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    if (names.isEmpty)
                      Text('—',
                          style: TextStyle(color: Colors.grey[600]))
                    else
                      ...names.map((n) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(n, style: const TextStyle(fontSize: 14)),
                          )),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(ld.close),
                  ),
                ],
              );
            },
          );
        }

        return SizedBox(
          width: 260,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.poll_outlined, size: 14, color: dimColor),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    effectivelyClosed
                        ? (isExpired && !poll.isClosed
                            ? l.pollExpired
                            : l.pollClosed)
                        : l.poll,
                    style: TextStyle(fontSize: 11, color: dimColor),
                  ),
                ),
                if (poll.isAnonymous) ...[
                  Icon(Icons.lock_outline, size: 13, color: dimColor),
                  const SizedBox(width: 4),
                ],
                if (canClose)
                  GestureDetector(
                    onTap: _close,
                    child: Icon(Icons.stop_circle_outlined,
                        size: 16, color: onColor ?? Colors.red),
                  ),
              ]),
              if (poll.expiresAt != null && !effectivelyClosed) ...[
                const SizedBox(height: 2),
                Text(
                  l.pollExpiresOn(
                    '${poll.expiresAt!.day.toString().padLeft(2, '0')}.'
                    '${poll.expiresAt!.month.toString().padLeft(2, '0')}.'
                    '${poll.expiresAt!.year}  '
                    '${poll.expiresAt!.hour.toString().padLeft(2, '0')}:'
                    '${poll.expiresAt!.minute.toString().padLeft(2, '0')}',
                  ),
                  style: TextStyle(fontSize: 10, color: dimColor),
                ),
              ],
              const SizedBox(height: 6),
              Text(poll.question,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: labelColor)),
              const SizedBox(height: 8),
              ...poll.options.map((opt) {
                final voterUids = poll.votesFor(opt.id);
                final count = voterUids.length;
                final total = poll.totalVoters;
                final pct = total > 0 ? count / total : 0.0;
                final myVote = poll.hasVotedFor(currentUid, opt.id);
                final canShowVoters =
                    showResults && !poll.isAnonymous && count > 0;

                return GestureDetector(
                  onTap: (!effectivelyClosed && !_voting) ? () => _vote(opt.id) : null,
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
                            InkWell(
                              onTap: canShowVoters
                                  ? () => showVoters(opt.text, voterUids)
                                  : null,
                              borderRadius: BorderRadius.circular(6),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                child: Text(
                                  '$count',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: canShowVoters
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: canShowVoters ? barColor : dimColor,
                                    decoration: canShowVoters
                                        ? TextDecoration.underline
                                        : null,
                                    decorationColor:
                                        canShowVoters ? barColor : null,
                                  ),
                                ),
                              ),
                            ),
                        ]),
                        if (showResults) ...[
                          const SizedBox(height: 3),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: pct,
                              minHeight: 4,
                              backgroundColor: barBg,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(barColor),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }),
              Text(
                poll.totalVoters == 1 ? l.oneVote : l.votes(poll.totalVoters),
                style: TextStyle(fontSize: 11, color: dimColor),
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

// ── Fullscreen-Bildbetrachter mit Speichern-Option ────────────────────────────

class _FullscreenImageDialog extends StatefulWidget {
  final String imageUrl;
  const _FullscreenImageDialog({required this.imageUrl});

  @override
  State<_FullscreenImageDialog> createState() => _FullscreenImageDialogState();
}

class _FullscreenImageDialogState extends State<_FullscreenImageDialog> {
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final l = AppLocalizations.of(context);
    try {
      final uri = Uri.parse(widget.imageUrl);
      var fileName = uri.pathSegments.last.split('?').first;
      if (!RegExp(r'\.(jpe?g|png|webp|gif)$', caseSensitive: false)
          .hasMatch(fileName)) {
        fileName = 'image_${DateTime.now().millisecondsSinceEpoch}.jpg';
      }

      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final savedPath = await FilePicker.saveFile(
        fileName: fileName,
        bytes: response.bodyBytes,
      );

      if (savedPath != null && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.imageSaved)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.errorMessage(e.toString()))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 5.0,
              child: CachedNetworkImage(
                imageUrl: widget.imageUrl,
                fit: BoxFit.contain,
                placeholder: (_, _) => const Center(
                    child: CircularProgressIndicator(color: Colors.white)),
                errorWidget: (_, _, _) => const Icon(
                    Icons.broken_image, color: Colors.white, size: 64),
              ),
            ),
          ),
          Positioned(
            top: 16,
            right: 16,
            child: Row(
              children: [
                Tooltip(
                  message: l.saveImage,
                  child: _saving
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          icon: const Icon(Icons.download,
                              color: Colors.white),
                          onPressed: _save,
                        ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
