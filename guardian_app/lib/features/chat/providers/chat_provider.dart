import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/appwrite_client.dart';
import '../../../core/models/conversation.dart';
import '../../../core/models/message.dart';
import '../../../core/models/poll.dart';
import '../../../core/models/scheduled_message.dart';
import '../../../core/services/chat_service.dart';
import '../../auth/providers/auth_provider.dart';

final chatServiceProvider = Provider<ChatService>((ref) {
  final user = ref.watch(authStateProvider).value;
  final client = ref.watch(appwriteClientProvider);
  return ChatService(
    client: client,
    uid: user?.uid ?? '',
    displayName: user?.displayName ?? '',
  );
});

final orgConversationsProvider =
    StreamProvider.family<List<Conversation>, String>((ref, orgId) {
  return ref.watch(chatServiceProvider).watchOrgConversations(orgId);
});

final adminConversationsProvider =
    StreamProvider.family<List<Conversation>, String>((ref, orgId) {
  return ref.watch(chatServiceProvider).watchAdminConversations(orgId);
});

final pendingRequestsProvider =
    StreamProvider.family<List<Conversation>, String>((ref, orgId) {
  return ref.watch(chatServiceProvider).watchPendingRequests(orgId);
});

final guardianPendingRequestsProvider =
    StreamProvider.family<List<Conversation>, String>((ref, orgId) {
  return ref.watch(chatServiceProvider).watchGuardianPendingRequests(orgId);
});

final moderatorPendingRequestsProvider =
    StreamProvider.family<List<Conversation>, String>((ref, orgId) {
  return ref.watch(chatServiceProvider).watchModeratorPendingRequests(orgId);
});

final supervisorConversationsProvider =
    StreamProvider.family<List<Conversation>, String>((ref, orgId) {
  return ref.watch(chatServiceProvider).watchSupervisorConversations(orgId);
});

final guardianSupervisorConversationsProvider =
    StreamProvider.family<List<Conversation>, String>((ref, orgId) {
  return ref
      .watch(chatServiceProvider)
      .watchGuardianSupervisorConversations(orgId);
});

final shelteredModeratorConversationsProvider = StreamProvider.family<
    List<Conversation>, ({String orgId, String adminUid})>((ref, params) {
  return ref
      .watch(chatServiceProvider)
      .watchShelteredModeratorConversations(params.orgId, params.adminUid);
});

/// Anzahl ungelesener Chats in einer Org (für Badge auf dem Startbildschirm)
final unreadOrgCountProvider = Provider.family<int, String>((ref, orgId) {
  final currentUid = ref.watch(authStateProvider).value?.uid ?? '';
  final ownConvs = ref.watch(orgConversationsProvider(orgId)).value ?? [];
  final adminConvs =
      ref.watch(adminConversationsProvider(orgId)).value ?? [];
  final seen = <String>{};
  final all = [...ownConvs, ...adminConvs].where((c) => seen.add(c.id)).toList();
  return all
      .where((c) =>
          c.status == ConversationStatus.approved && c.hasUnread(currentUid))
      .length;
});

final allMyConversationsProvider = StreamProvider<List<Conversation>>((ref) {
  return ref.watch(chatServiceProvider).watchAllMyApprovedConversations();
});

final conversationProvider =
    StreamProvider.family<Conversation?, String>((ref, convId) {
  return ref.watch(chatServiceProvider).watchConversation(convId);
});

final messagesProvider = StreamProvider.family<List<Message>,
    ({String convId, int limit})>((ref, params) {
  return ref
      .watch(chatServiceProvider)
      .watchMessages(params.convId, limit: params.limit);
});

final pollProvider = StreamProvider.family<Poll?,
    ({String convId, String pollId})>((ref, params) {
  return ref
      .watch(chatServiceProvider)
      .watchPoll(params.convId, params.pollId);
});

final scheduledMessagesProvider =
    StreamProvider.family<List<ScheduledMessage>, String>((ref, convId) {
  return ref.watch(chatServiceProvider).watchScheduledMessages(convId);
});
