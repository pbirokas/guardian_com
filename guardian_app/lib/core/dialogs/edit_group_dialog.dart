import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/app_localizations.dart';
import '../models/conversation.dart';
import '../widgets/group_avatar.dart';
import '../../../features/chat/providers/chat_provider.dart';

Future<void> showEditGroupDialog({
  required BuildContext context,
  required WidgetRef ref,
  required Conversation conv,
}) async {
  final l = AppLocalizations.of(context);
  final nameController = TextEditingController(text: conv.name ?? '');
  Uint8List? pickedImageBytes;
  bool removeImage = false;
  bool pickingImage = false;

  try {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(l.editGroup),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () async {
                    if (pickingImage) return;
                    setDialogState(() => pickingImage = true);
                    try {
                      final picker = ImagePicker();
                      final picked =
                          await picker.pickImage(source: ImageSource.gallery);
                      if (picked == null) return;
                      final bytes = await picked.readAsBytes();
                      setDialogState(() {
                        pickedImageBytes = bytes;
                        removeImage = false;
                      });
                    } finally {
                      setDialogState(() => pickingImage = false);
                    }
                  },
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundImage: pickedImageBytes != null
                            ? MemoryImage(pickedImageBytes!) as ImageProvider
                            : (conv.imageUrl != null &&
                                    !removeImage &&
                                    isStorageTrustedUrl(conv.imageUrl!)
                                ? CachedNetworkImageProvider(conv.imageUrl!)
                                : null),
                        backgroundColor:
                            Theme.of(ctx).colorScheme.secondaryContainer,
                        child: (pickedImageBytes == null &&
                                (conv.imageUrl == null ||
                                    removeImage ||
                                    !isStorageTrustedUrl(conv.imageUrl!)))
                            ? Icon(Icons.group,
                                size: 40,
                                color: Theme.of(ctx)
                                    .colorScheme
                                    .onSecondaryContainer)
                            : null,
                      ),
                      CircleAvatar(
                        radius: 13,
                        backgroundColor: Theme.of(ctx).colorScheme.primary,
                        child: Icon(Icons.camera_alt,
                            size: 14,
                            color: Theme.of(ctx).colorScheme.onPrimary),
                      ),
                    ],
                  ),
                ),
                if (conv.imageUrl != null &&
                    !removeImage &&
                    pickedImageBytes == null)
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    label: Text(l.removeGroupImage),
                    onPressed: () => setDialogState(() => removeImage = true),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  maxLength: 40,
                  decoration: InputDecoration(hintText: l.chatNameHint),
                ),
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
              child: Text(l.save),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    final service = ref.read(chatServiceProvider);
    try {
      String? newImageUrl;
      if (pickedImageBytes != null) {
        newImageUrl = await service.uploadGroupImage(conv.id, pickedImageBytes!);
      }
      final trimmedName = nameController.text.trim();
      await service.updateGroupInfo(
        conv.id,
        name: trimmedName.isEmpty ? null : trimmedName,
        imageUrl: newImageUrl,
        removeImage: removeImage,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  AppLocalizations.of(context).errorMessage(e.toString()))),
        );
      }
    }
  } finally {
    nameController.dispose();
  }
}
