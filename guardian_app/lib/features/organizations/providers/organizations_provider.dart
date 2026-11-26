import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/appwrite_client.dart';
import '../../../core/models/announcement.dart';
import '../../../core/models/app_user.dart';
import '../../../core/models/member_suggestion.dart';
import '../../../core/models/notification_settings.dart';
import '../../../core/models/organization.dart';
import '../../../core/models/org_member.dart';
import '../../../core/services/organization_service.dart';
import '../../auth/providers/auth_provider.dart';

final organizationServiceProvider = Provider<OrganizationService>((ref) {
  final user = ref.watch(authStateProvider).value;
  final client = ref.watch(appwriteClientProvider);
  return OrganizationService(
    client: client,
    broadcaster: ref.watch(appwriteRealtimeBroadcasterProvider),
    uid: user?.uid ?? '',
    displayName: user?.displayName ?? '',
    email: user?.email,
  );
});

final myOrganizationsProvider = StreamProvider<List<Organization>>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(organizationServiceProvider).watchMyOrganizations();
});

final organizationProvider =
    StreamProvider.family<Organization, String>((ref, orgId) {
  ref.watch(authStateProvider);
  return ref.watch(organizationServiceProvider).watchOrganization(orgId);
});

final orgMembersProvider =
    StreamProvider.family<List<OrgMember>, String>((ref, orgId) {
  ref.watch(authStateProvider);
  return ref.watch(organizationServiceProvider).watchMembers(orgId);
});

/// Aktueller eingeloggter AppUser — abgeleitet aus dem Appwrite Auth-State
final currentAppUserProvider = Provider<AsyncValue<AppUser?>>((ref) {
  final auth = ref.watch(authStateProvider);
  // Live-Stand des eigenen users-Docs bevorzugen (z. B. `isChild` wird
  // während der Sitzung true, wenn das Kind eine Eltern-Anfrage bestätigt);
  // sonst der Snapshot vom Login.
  final live = ref.watch(ownUserDocProvider);
  final liveUser = live.value;
  if (auth.hasValue && liveUser != null && liveUser.uid == auth.value?.uid) {
    return AsyncData(liveUser);
  }
  return auth;
});

/// Eigenes users-Doc live per Realtime (nur das eigene ist lesbar).
final ownUserDocProvider = StreamProvider<AppUser?>((ref) {
  final uid = ref.watch(authStateProvider.select((s) => s.value?.uid));
  if (uid == null) return Stream.value(null);
  return ref
      .watch(authServiceProvider)
      .watchOwnUser(uid, ref.watch(appwriteRealtimeBroadcasterProvider));
});

/// Ausstehende Kind-Einladungen für den aktuellen Guardian in einer Org
final pendingChildInvitesProvider =
    StreamProvider.family<List<OrgMember>, String>((ref, orgId) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return Stream.value([]);
  return ref
      .watch(organizationServiceProvider)
      .watchPendingChildInvites(orgId, uid);
});

/// Ausstehende Pre-Registration Einladungen für den aktuellen Guardian
final pendingPreRegInvitesProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String>((ref, orgId) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return Stream.value([]);
  return ref
      .watch(organizationServiceProvider)
      .watchPendingInvitationsForGuardian(orgId, uid);
});

/// Ausstehende Mitglied-Vorschläge (nur für Admins/Moderatoren sichtbar)
final pendingMemberSuggestionsProvider =
    StreamProvider.family<List<MemberSuggestion>, String>((ref, orgId) {
  ref.watch(authStateProvider);
  return ref
      .watch(organizationServiceProvider)
      .watchPendingSuggestions(orgId);
});

/// Globale Benachrichtigungseinstellungen des eingeloggten Nutzers
final notificationSettingsProvider =
    StreamProvider<NotificationSettings>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return Stream.value(const NotificationSettings());
  return ref.watch(authServiceProvider).watchNotificationSettings(
      uid, ref.watch(appwriteRealtimeBroadcasterProvider));
});

/// Benachrichtigungsintervall für eine bestimmte Org (eigener Member-Doc-Eintrag)
final orgMessageIntervalProvider =
    StreamProvider.family<MessageAlertInterval, String>((ref, orgId) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return Stream.value(MessageAlertInterval.always);
  return ref.watch(organizationServiceProvider).watchOrgMessageInterval(orgId);
});

final announcementsProvider =
    StreamProvider.family<List<Announcement>, String>((ref, orgId) {
  ref.watch(authStateProvider);
  return ref.watch(organizationServiceProvider).watchAnnouncements(orgId);
});

/// Anzeigename eines Org-Mitglieds aus dessen Member-Doc (gecacht pro
/// Org+UID). Fremde users-Docs sind für Clients nicht lesbar.
final memberDisplayNameProvider =
    FutureProvider.family<String, ({String orgId, String uid})>((ref, key) {
  return ref
      .watch(organizationServiceProvider)
      .getMemberDisplayName(key.orgId, key.uid);
});
