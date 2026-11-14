import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kKey = 'chatListSortMode';

/// Sortierung der eigenen Chats in der Chat-Übersicht einer Organisation.
/// Überwachte und archivierte Chats bleiben unabhängig davon gruppiert.
enum ChatListSortMode {
  /// Getrennt nach Gruppen und Einzel-Chats.
  grouped,

  /// Eine gemeinsame Liste, neueste Nachricht zuerst.
  recent,
}

class ChatListSortNotifier extends AsyncNotifier<ChatListSortMode> {
  @override
  Future<ChatListSortMode> build() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_kKey);
    return ChatListSortMode.values
            .where((m) => m.name == value)
            .firstOrNull ??
        ChatListSortMode.grouped;
  }

  Future<void> setMode(ChatListSortMode mode) async {
    state = AsyncData(mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, mode.name);
  }
}

final chatListSortProvider =
    AsyncNotifierProvider<ChatListSortNotifier, ChatListSortMode>(
  ChatListSortNotifier.new,
);
