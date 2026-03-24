import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/organization.dart';
import '../../../core/models/org_member.dart';
import '../../../core/services/organization_service.dart';
import '../../auth/providers/auth_provider.dart';

final organizationServiceProvider =
    Provider<OrganizationService>((ref) => OrganizationService());

final myOrganizationsProvider = StreamProvider<List<Organization>>((ref) {
  // Neu laden wenn sich der eingeloggte User ändert
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
