import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/announcement.dart';
import '../../../core/models/app_user.dart';
import '../../../core/models/member_suggestion.dart';
import '../../../core/models/notification_settings.dart';
import '../../../core/models/organization.dart';
import '../../../core/models/org_member.dart';
import '../../../core/services/organization_service.dart';
import '../../auth/providers/auth_provider.dart';

final organizationServiceProvider =
    Provider<OrganizationService>((ref) => OrganizationService());

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

/// Aktueller eingeloggter AppUser (mit Memberships)
final currentAppUserProvider = StreamProvider<AppUser?>((ref) {
  ref.watch(authStateProvider);
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(null);
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((s) => s.exists ? AppUser.fromFirestore(s) : null);
});

/// Ausstehende Kind-Einladungen für den aktuellen Guardian in einer Org
final pendingChildInvitesProvider =
    StreamProvider.family<List<OrgMember>, String>((ref, orgId) {
  ref.watch(authStateProvider);
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value([]);
  return ref
      .watch(organizationServiceProvider)
      .watchPendingChildInvites(orgId, uid);
});

/// Ausstehende Pre-Registration Einladungen für den aktuellen Guardian
final pendingPreRegInvitesProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String>((ref, orgId) {
  ref.watch(authStateProvider);
  final uid = FirebaseAuth.instance.currentUser?.uid;
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
  ref.watch(authStateProvider);
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(const NotificationSettings());
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((s) => NotificationSettings.fromMap(
            s.data()?['notificationSettings'] as Map<String, dynamic>?,
          ));
});

/// Benachrichtigungsintervall für eine bestimmte Org (eigener Member-Doc-Eintrag)
final orgMessageIntervalProvider =
    StreamProvider.family<MessageAlertInterval, String>((ref, orgId) {
  ref.watch(authStateProvider);
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(MessageAlertInterval.always);
  return FirebaseFirestore.instance
      .collection('organizations')
      .doc(orgId)
      .collection('members')
      .doc(uid)
      .snapshots()
      .map((s) {
    final data = s.data();
    // Legacy: if notificationsEnabled is false, treat as never
    if (data?['notificationsEnabled'] == false &&
        data?['messageAlertInterval'] == null) {
      return MessageAlertInterval.never;
    }
    final name = data?['messageAlertInterval'] as String?;
    return MessageAlertInterval.values
            .where((e) => e.name == name)
            .firstOrNull ??
        MessageAlertInterval.always;
  });
});

final announcementsProvider =
    StreamProvider.family<List<Announcement>, String>((ref, orgId) {
  ref.watch(authStateProvider);
  return ref.watch(organizationServiceProvider).watchAnnouncements(orgId);
});
