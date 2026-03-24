import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/conversation.dart';
import '../../../core/models/message.dart';
import '../../../core/services/chat_service.dart';
import '../../auth/providers/auth_provider.dart';

final chatServiceProvider =
    Provider<ChatService>((ref) => ChatService());

final orgConversationsProvider =
    StreamProvider.family<List<Conversation>, String>((ref, orgId) {
  ref.watch(authStateProvider);
  return ref.watch(chatServiceProvider).watchOrgConversations(orgId);
});

final adminConversationsProvider =
    StreamProvider.family<List<Conversation>, String>((ref, orgId) {
  ref.watch(authStateProvider);
  return ref.watch(chatServiceProvider).watchAdminConversations(orgId);
});

final pendingRequestsProvider =
    StreamProvider.family<List<Conversation>, String>((ref, orgId) {
  ref.watch(authStateProvider);
  return ref.watch(chatServiceProvider).watchPendingRequests(orgId);
});

final messagesProvider =
    StreamProvider.family<List<Message>, String>((ref, convId) {
  ref.watch(authStateProvider);
  return ref.watch(chatServiceProvider).watchMessages(convId);
});
