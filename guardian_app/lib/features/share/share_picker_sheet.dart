import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/conversation.dart';
import '../../core/providers/share_provider.dart';
import '../../core/services/share_service.dart';
import '../../l10n/app_localizations.dart';
import '../chat/providers/chat_provider.dart';
import '../organizations/providers/organizations_provider.dart';

class SharePickerSheet extends ConsumerStatefulWidget {
  final ShareData shareData;

  const SharePickerSheet({super.key, required this.shareData});

  @override
  ConsumerState<SharePickerSheet> createState() => _SharePickerSheetState();
}

class _SharePickerSheetState extends ConsumerState<SharePickerSheet> {
  String? _sendingConvId;

  String _partnerUid(Conversation conv) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return conv.participantUids.firstWhere((u) => u != uid, orElse: () => uid);
  }

  Future<void> _send(Conversation conv, String convTitle) async {
    if (_sendingConvId != null) return;
    setState(() => _sendingConvId = conv.id);

    final shareService = ref.read(shareServiceProvider);
    final chatService = ref.read(chatServiceProvider);
    final data = widget.shareData;

    try {
      if (data.isText) {
        await chatService.sendMessage(conv.id, data.text!);
      } else {
        for (var i = 0; i < data.uris.length; i++) {
          final bytes = await shareService.readUri(data.uris[i]);
          if (bytes == null) continue;
          final fileName = data.fileNames.length > i ? data.fileNames[i] : 'file';
          if (data.isImage) {
            await chatService.sendImage(conv.id, bytes);
          } else {
            await chatService.sendFile(conv.id, bytes, fileName, bytes.length);
          }
        }
      }

      if (mounted) {
        ref.read(pendingShareProvider.notifier).clear();
        Navigator.of(context).pop();
        context.push('/chat/${conv.id}', extra: convTitle);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _sendingConvId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final conversations = ref.watch(allMyConversationsProvider);
    final myOrgs = ref.watch(myOrganizationsProvider);
    final myOrgIds = myOrgs.value?.map((o) => o.id).toSet() ?? {};

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l.sharePickerTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      ref.read(pendingShareProvider.notifier).clear();
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
            ),
            _SharePreview(shareData: widget.shareData),
            const Divider(height: 1),
            Expanded(
              child: conversations.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text(e.toString())),
                data: (convs) {
                  final filtered = myOrgIds.isEmpty
                      ? convs
                      : convs.where((c) => myOrgIds.contains(c.orgId)).toList();
                  if (filtered.isEmpty) {
                    return Center(child: Text(l.noConversations));
                  }
                  return ListView.builder(
                    controller: scrollController,
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final conv = filtered[i];
                      return _ShareConvTile(
                        conv: conv,
                        partnerUid: conv.isGroup ? null : _partnerUid(conv),
                        isSending: _sendingConvId == conv.id,
                        isBlocked: _sendingConvId != null && _sendingConvId != conv.id,
                        onSend: _send,
                      );
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
}

/// Einzelner Eintrag in der Konversationsliste.
/// Ist ein eigenes ConsumerWidget, damit der userDisplayNameProvider
/// per UID gecacht und unabhängig vom Parent rebuildet werden kann.
class _ShareConvTile extends ConsumerWidget {
  final Conversation conv;
  final String? partnerUid;
  final bool isSending;
  final bool isBlocked;
  final Future<void> Function(Conversation, String) onSend;

  const _ShareConvTile({
    required this.conv,
    required this.partnerUid,
    required this.isSending,
    required this.isBlocked,
    required this.onSend,
  });

  String _resolveTitle(WidgetRef ref) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    // Persönlicher Name hat höchste Priorität
    final personal = conv.personalNames[uid];
    if (personal != null && personal.isNotEmpty) return personal;
    // Gruppenname
    if (conv.isGroup) return conv.name ?? '';
    // Direktchat: Display-Name des Partners
    if (partnerUid != null) {
      final nameAsync = ref.watch(userDisplayNameProvider(partnerUid!));
      return nameAsync.value ?? conv.name ?? partnerUid!;
    }
    return conv.name ?? conv.id;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final title = _resolveTitle(ref);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: colorScheme.primaryContainer,
        child: Icon(
          conv.isGroup ? Icons.group_outlined : Icons.person_outline,
          color: colorScheme.onPrimaryContainer,
        ),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: conv.lastMessage != null && conv.lastMessage!.isNotEmpty
          ? Text(
              conv.lastMessage!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
            )
          : null,
      trailing: isSending
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : isBlocked
              ? null
              : const Icon(Icons.send_outlined),
      onTap: isSending || isBlocked ? null : () => onSend(conv, title),
    );
  }
}

class _SharePreview extends StatelessWidget {
  final ShareData shareData;

  const _SharePreview({required this.shareData});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isText = shareData.isText;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            isText
                ? Icons.text_fields
                : shareData.isImage
                    ? Icons.image_outlined
                    : Icons.attach_file,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isText ? (shareData.text ?? '') : shareData.fileNames.join(', '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
