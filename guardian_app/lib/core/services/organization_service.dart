import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/enums.dart';
import 'package:appwrite/models.dart' as aw;
import '../appwrite_client.dart' show RealtimeBroadcaster;
import '../models/announcement.dart';
import '../models/app_user.dart';
import '../models/member_suggestion.dart';
import '../models/notification_settings.dart';
import '../models/organization.dart';
import '../models/org_member.dart';
import '../models/org_invite_consent.dart';
import '../models/org_audit_entry.dart';

class OrganizationService {
  OrganizationService({
    required Client client,
    required RealtimeBroadcaster broadcaster,
    required String uid,
    required String displayName,
    String? email,
  })  : _db = Databases(client),
        _functions = Functions(client),
        _broadcaster = broadcaster,
        _uid = uid,
        _displayName = displayName,
        _email = email ?? '';

  final Databases _db;
  final Functions _functions;
  final RealtimeBroadcaster _broadcaster;
  final String _uid;
  final String _displayName;
  final String _email;

  static const _adminMemberActionId = 'admin-member-action';

  static const _dbId = 'guardian';
  static const _colOrgs = 'organizations';
  static const _colMembers = 'members';
  static const _colInvitations = 'invitations';
  static const _colAnnouncements = 'announcements';
  static const _colOrgConsents = 'org_invite_consents';
  static const _colAuditLog = 'audit_log';

  // ── Realtime helper ────────────────────────────────────────────────────────

  Stream<List<T>> _watchCollection<T>(
    String collectionId,
    T Function(Map<String, dynamic>) fromDoc,
    List<String> queries,
  ) {
    late StreamController<List<T>> ctrl;
    StreamSubscription? realtimeSub;

    Future<void> reload() async {
      if (ctrl.isClosed) return;
      try {
        final result = await _db.listDocuments(
          databaseId: _dbId,
          collectionId: collectionId,
          queries: [...queries, Query.limit(500)],
        );
        final items = result.documents
            .map((d) => fromDoc({r'$id': d.$id, ...d.data}))
            .toList();
        if (!ctrl.isClosed) ctrl.add(items);
      } catch (e) {
        if (!ctrl.isClosed) ctrl.addError(e);
      }
    }

    void dispose() {
      realtimeSub?.cancel();
      ctrl.close();
    }

    ctrl = StreamController(onCancel: dispose);
    realtimeSub = _broadcaster
        .stream('databases.$_dbId.collections.$collectionId.documents')
        .listen((_) => reload(), onDone: dispose, onError: (_) {});
    reload();
    return ctrl.stream;
  }

  // ── Organisations-CRUD ─────────────────────────────────────────────────────

  Future<Organization> createOrganization(String name, OrgTag tag) async {
    final now = DateTime.now().toUtc();
    final orgId = ID.unique();

    final org = Organization(
      id: orgId,
      name: name,
      adminUid: _uid,
      tag: tag,
      memberUids: [_uid],
      createdAt: now,
    );

    final membership = OrgMembership(orgId: orgId, role: OrgRole.admin);
    final memberId = '${orgId}_$_uid';
    final memberData = OrgMember(
      uid: _uid,
      displayName: _displayName,
      email: _email,
      role: OrgRole.admin,
      joinedAt: now,
    ).toAppwrite();

    // Appwrite hat keine Client-Transaktionen — sequenzielle Writes
    await _db.createDocument(
      databaseId: _dbId,
      collectionId: _colOrgs,
      documentId: orgId,
      data: org.toAppwrite(),
      permissions: [
        Permission.read(Role.users()),
        Permission.update(Role.user(_uid)),
        Permission.delete(Role.user(_uid)),
      ],
    );
    await _db.createDocument(
      databaseId: _dbId,
      collectionId: _colMembers,
      documentId: memberId,
      data: {...memberData, 'orgId': orgId},
      permissions: [
        Permission.read(Role.users()),
        Permission.update(Role.user(_uid)),
        Permission.delete(Role.user(_uid)),
      ],
    );
    await _updateMembershipsJson(_uid, membership, add: true);

    return org;
  }

  Future<void> updateOrganization(String orgId,
      {String? name, OrgTag? tag, int? messageRetentionDays}) async {
    final clampedRetention = messageRetentionDays?.clamp(
        Organization.retentionMin, Organization.retentionMax);
    final updates = <String, dynamic>{
      if (name != null) 'name': name,
      if (tag != null) 'tag': tag.name,
      if (clampedRetention != null)
        'messageRetentionDays': clampedRetention,
    };
    if (updates.isNotEmpty) {
      await _db.updateDocument(
          databaseId: _dbId,
          collectionId: _colOrgs,
          documentId: orgId,
          data: updates);
      unawaited(_logAuditEvent(orgId, AuditAction.settingsChanged, updates));
    }
  }

  Future<void> archiveOrganization(String orgId) =>
      _db.updateDocument(
          databaseId: _dbId,
          collectionId: _colOrgs,
          documentId: orgId,
          data: {'isArchived': true});

  Future<void> unarchiveOrganization(String orgId) =>
      _db.updateDocument(
          databaseId: _dbId,
          collectionId: _colOrgs,
          documentId: orgId,
          data: {'isArchived': false});

  Future<void> deleteOrganization(String orgId) async {
    // xasync: true — Funktion läuft im Hintergrund, kein 30s-Client-Timeout.
    // Die Org verschwindet aus der UI über den Realtime-Listener sobald
    // das Dokument tatsächlich gelöscht wurde.
    await _functions.createExecution(
      functionId: _adminMemberActionId,
      body: jsonEncode({'action': 'deleteOrg', 'orgId': orgId}),
      method: ExecutionMethod.pOST,
      xasync: true,
    );
  }

  Stream<List<Organization>> watchMyOrganizations() {
    late StreamController<List<Organization>> ctrl;
    final subs = <StreamSubscription>[];

    Future<void> reload() async {
      if (ctrl.isClosed) return;
      try {
        final result = await _db.listDocuments(
          databaseId: _dbId,
          collectionId: _colOrgs,
          queries: [Query.contains('memberUids', [_uid]), Query.limit(500)],
        );
        if (!ctrl.isClosed) {
          ctrl.add(result.documents
              .map((d) => Organization.fromAppwrite({r'$id': d.$id, ...d.data}))
              .toList());
        }
      } catch (e) {
        if (!ctrl.isClosed) ctrl.addError(e);
      }
    }

    void dispose() {
      for (final s in subs) s.cancel();
      ctrl.close();
    }

    ctrl = StreamController(onCancel: dispose);

    // Auf beide Collections lauschen: wenn ein Org-Doc ODER ein Member-Doc
    // geändert/gelöscht wird (z.B. beim Org-Delete), wird die Liste neu geladen.
    // Zwei unabhängige Trigger erhöhen die Zuverlässigkeit gegenüber Realtime-
    // Eventausfall bei API-Key-Operationen.
    for (final col in [_colOrgs, _colMembers]) {
      subs.add(
        _broadcaster
            .stream('databases.$_dbId.collections.$col.documents')
            .listen((_) => reload(), onDone: dispose, onError: (_) {}),
      );
    }

    reload();
    return ctrl.stream;
  }

  Stream<Organization> watchOrganization(String orgId) {
    final ctrl = StreamController<Organization>();
    StreamSubscription? realtimeSub;

    Future<void> reload() async {
      if (ctrl.isClosed) return;
      try {
        final doc = await _db.getDocument(
            databaseId: _dbId, collectionId: _colOrgs, documentId: orgId);
        if (!ctrl.isClosed) {
          ctrl.add(Organization.fromAppwrite({r'$id': doc.$id, ...doc.data}));
        }
      } catch (e) {
        if (!ctrl.isClosed) ctrl.addError(e);
      }
    }

    void dispose() {
      realtimeSub?.cancel();
      ctrl.close();
    }

    ctrl.onCancel = dispose;
    realtimeSub = _broadcaster
        .stream('databases.$_dbId.collections.$_colOrgs.documents.$orgId')
        .listen((_) => reload(), onDone: dispose, onError: (_) {});
    reload();
    return ctrl.stream;
  }

  // ── Mitglieder ─────────────────────────────────────────────────────────────

  Stream<List<OrgMember>> watchMembers(String orgId) {
    return _watchCollection(
      _colMembers,
      OrgMember.fromAppwrite,
      [Query.equal('orgId', orgId)],
    );
  }

  Future<void> removeMember(String orgId, String targetUid) async {
    // Vor dem CF-Aufruf den Anzeigenamen für das Audit-Log laden
    final memberId = '${orgId}_$targetUid';
    String targetName = targetUid;
    String roleStr = '';
    try {
      final doc = await _db.getDocument(
          databaseId: _dbId, collectionId: _colMembers, documentId: memberId);
      targetName = doc.data['displayName'] as String? ?? targetUid;
      roleStr = doc.data['role'] as String? ?? '';
    } catch (_) {}

    final result = await _callAdminMemberAction('removeMember', orgId,
        targetUid: targetUid);
    if (result['error'] != null) throw Exception(result['error'] as String);

    unawaited(_logAuditEvent(orgId, AuditAction.memberRemoved,
        {'targetUid': targetUid, 'targetName': targetName, 'role': roleStr}));
  }

  Future<void> leaveOrganization(String orgId) async {
    final result = await _callAdminMemberAction('leaveOrg', orgId);
    if (result['error'] != null) throw Exception(result['error'] as String);
  }

  Future<void> updateMemberRole(
      String orgId, String targetUid, OrgRole newRole) async {
    if (newRole != OrgRole.child) {
      final userDoc = await _db.getDocument(
          databaseId: _dbId, collectionId: 'users', documentId: targetUid);
      if (userDoc.data['isChild'] as bool? ?? false) {
        throw Exception('child_account_role_locked');
      }
    }

    // Anzeigenamen vor dem CF-Aufruf laden (für Audit-Log)
    String targetName = targetUid;
    try {
      final doc = await _db.getDocument(
          databaseId: _dbId,
          collectionId: _colMembers,
          documentId: '${orgId}_$targetUid');
      targetName = doc.data['displayName'] as String? ?? targetUid;
    } catch (_) {}

    final result = await _callAdminMemberAction('updateRole', orgId,
        targetUid: targetUid, payload: {'newRole': newRole.name});
    if (result['error'] != null) throw Exception(result['error'] as String);

    final oldRole = result['oldRole'] as String? ?? '';
    unawaited(_logAuditEvent(orgId, AuditAction.roleChanged, {
      'targetUid': targetUid,
      'targetName': targetName,
      'oldRole': oldRole,
      'newRole': newRole.name,
    }));
  }

  Future<void> transferAdmin(String orgId, String newAdminUid) async {
    // Anzeigenamen vor dem CF-Aufruf laden (für Audit-Log)
    String newAdminName = newAdminUid;
    try {
      final snap = await _db.getDocument(
          databaseId: _dbId,
          collectionId: _colMembers,
          documentId: '${orgId}_$newAdminUid');
      newAdminName = snap.data['displayName'] as String? ?? newAdminUid;
    } catch (_) {}

    final result = await _callAdminMemberAction('transferAdmin', orgId,
        targetUid: newAdminUid);
    if (result['error'] != null) throw Exception(result['error'] as String);

    unawaited(_logAuditEvent(orgId, AuditAction.adminTransferred,
        {'newAdminUid': newAdminUid, 'newAdminName': newAdminName}));
  }

  Future<void> updateGuardians(
      String orgId, String childUid, List<String> guardianUids) async {
    // Anzeigenamen vor dem CF-Aufruf laden (für Audit-Log)
    String childName = childUid;
    try {
      final doc = await _db.getDocument(
          databaseId: _dbId,
          collectionId: _colMembers,
          documentId: '${orgId}_$childUid');
      childName = doc.data['displayName'] as String? ?? childUid;
    } catch (_) {}

    final result = await _callAdminMemberAction('updateGuardians', orgId,
        targetUid: childUid, payload: {'guardianUids': guardianUids});
    if (result['error'] != null) throw Exception(result['error'] as String);

    unawaited(_logAuditEvent(orgId, AuditAction.guardiansChanged, {
      'childUid': childUid,
      'childName': childName,
      'guardianUids': guardianUids,
    }));
  }

  Future<void> approveChildInvite(String orgId, String childUid) async {
    final result = await _callAdminMemberAction('approveChild', orgId,
        targetUid: childUid);
    if (result['error'] != null) throw Exception(result['error'] as String);
  }

  Future<void> rejectChildInvite(String orgId, String childUid) async {
    await _db.deleteDocument(
        databaseId: _dbId,
        collectionId: _colMembers,
        documentId: '${orgId}_$childUid');
  }

  Stream<List<OrgMember>> watchPendingChildInvites(
      String orgId, String guardianUid) {
    return _watchCollection(
      _colMembers,
      OrgMember.fromAppwrite,
      [
        Query.equal('orgId', orgId),
        Query.contains('guardianUids', [guardianUid]),
        Query.equal('status', 'pending'),
      ],
    );
  }

  // ── Einladungen ────────────────────────────────────────────────────────────

  Future<void> inviteMember(String orgId, String email, OrgRole role,
      {List<String> guardianUids = const []}) async {
    final normalizedEmail = email.toLowerCase().trim();
    var isChild = role == OrgRole.child;
    if (isChild && guardianUids.isEmpty) {
      throw Exception(
          'Für ein Kind muss mindestens ein Guardian ausgewählt werden.');
    }

    // Org-Name laden
    final orgDoc = await _db.getDocument(
        databaseId: _dbId, collectionId: _colOrgs, documentId: orgId);
    final orgName = orgDoc.data['name'] as String? ?? '';

    // Prüfen ob User bereits in Appwrite registriert ist
    final usersResult = await _db.listDocuments(
      databaseId: _dbId,
      collectionId: 'users',
      queries: [Query.equal('email', normalizedEmail), Query.limit(1)],
    );

    if (usersResult.documents.isEmpty) {
      // Noch nicht registriert → Einladung anlegen
      final existing = await _db.listDocuments(
        databaseId: _dbId,
        collectionId: _colInvitations,
        queries: [
          Query.equal('email', normalizedEmail),
          Query.equal('orgId', orgId),
          Query.equal('status', 'pending'),
          Query.limit(1),
        ],
      );
      if (existing.documents.isNotEmpty) {
        throw Exception(
            'Für diese E-Mail gibt es bereits eine ausstehende Einladung.');
      }
      await _db.createDocument(
        databaseId: _dbId,
        collectionId: _colInvitations,
        documentId: ID.unique(),
        data: {
          'email': normalizedEmail,
          'orgId': orgId,
          'orgName': orgName,
          'role': role.name,
          'guardianUids': guardianUids,
          'inviterName': _displayName,
          'invitedByUid': _uid,
          'status': 'pending',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      );
      return;
    }

    // Bereits registriert → direkt hinzufügen
    final userDoc = usersResult.documents.first;
    final userData = userDoc.data;
    final targetUid = userDoc.$id;

    final isChildAccount = userData['isChild'] as bool? ?? false;
    if (isChildAccount && role != OrgRole.child) {
      throw Exception('child_account_role_locked');
    }
    final effectiveRole = isChildAccount ? OrgRole.child : role;
    isChild = effectiveRole == OrgRole.child;
    if (isChild && guardianUids.isEmpty) {
      throw Exception(
          'Für ein Kind muss mindestens ein Guardian ausgewählt werden.');
    }

    final memberId = '${orgId}_$targetUid';
    final existing = await _safeGetDocument(_colMembers, memberId);
    if (existing != null) {
      throw Exception('Dieser Benutzer ist bereits Mitglied.');
    }

    // Eltern des Kindes → OrgInviteConsent einholen
    final parentUids =
        List<String>.from(userData['verifiedParentUids'] as List? ?? []);
    if (parentUids.isNotEmpty) {
      final now = DateTime.now().toUtc();
      await _db.createDocument(
        databaseId: _dbId,
        collectionId: _colOrgConsents,
        documentId: ID.unique(),
        data: OrgInviteConsent(
          id: '',
          childUid: targetUid,
          childName: userData['displayName'] as String? ?? '',
          orgId: orgId,
          orgName: orgName,
          invitedByUid: _uid,
          invitedByName: _displayName,
          proposedGuardianUids: guardianUids,
          parentUids: parentUids,
          status: OrgInviteConsentStatus.pending,
          createdAt: now,
          expiresAt: now.add(const Duration(days: 7)),
        ).toAppwrite(),
      );
      return;
    }

    final memberStatus = isChild ? MemberStatus.pending : MemberStatus.active;

    final memberData = {
      ...OrgMember(
        uid: targetUid,
        displayName: userData['displayName'] as String? ??
            userData['email'] as String,
        // Email nur für Nicht-Kinder speichern — Minderjährigendaten werden nicht
        // in für alle Org-Mitglieder lesbaren Docs persistiert (HIGH #3 / DSGVO).
        email: isChild ? '' : (userData['email'] as String? ?? ''),
        photoUrl: userData['photoUrl'] as String?,
        role: effectiveRole,
        joinedAt: DateTime.now().toUtc(),
        guardianUids: isChild ? guardianUids : [],
        status: memberStatus,
      ).toAppwrite(),
      'orgId': orgId,
    };

    // Cloud Function erstellt den Member-Doc mit korrekten per-user Permissions
    // (admin-member-action mit API-Key). Client kann keine user:targetUid Permissions
    // für fremde UIDs setzen (Appwrite-Einschränkung).
    final result = await _callAdminMemberAction('addMember', orgId,
        targetUid: targetUid, payload: {'memberData': memberData, 'isChild': isChild});
    if (result['error'] == 'already_member') {
      throw Exception('Dieser Benutzer ist bereits Mitglied.');
    }
    if (result['error'] != null) {
      throw Exception(result['error'] as String);
    }

    final targetName = userData['displayName'] as String? ?? normalizedEmail;
    unawaited(_logAuditEvent(orgId, AuditAction.memberConfirmed, {
      'targetUid': targetUid,
      'targetName': targetName,
      'role': effectiveRole.name,
    }));
  }

  Future<void> cancelInvitation(String inviteId) async {
    await _db.updateDocument(
        databaseId: _dbId,
        collectionId: _colInvitations,
        documentId: inviteId,
        data: {'status': 'cancelled'});
  }

  Stream<List<Map<String, dynamic>>> watchPendingInvitationsForGuardian(
      String orgId, String guardianUid) {
    return _watchCollection<Map<String, dynamic>>(
      _colInvitations,
      (data) => {r'$id': data[r'$id'], ...data},
      [
        Query.equal('orgId', orgId),
        Query.contains('guardianUids', [guardianUid]),
        Query.equal('status', 'pending'),
      ],
    );
  }

  // ── Member-Profil ──────────────────────────────────────────────────────────

  Future<void> updateMyMemberProfile(String displayName,
      {String? photoUrl}) async {
    final userDoc = await _db.getDocument(
        databaseId: _dbId, collectionId: 'users', documentId: _uid);
    final membershipsJson = userDoc.data['membershipsJson'] as String?;
    if (membershipsJson == null || membershipsJson.isEmpty) return;

    final memberships =
        List<Map<String, dynamic>>.from(_decodeMemberships(membershipsJson));
    for (final m in memberships) {
      final orgId = m['orgId'] as String?;
      if (orgId == null) continue;
      final memberId = '${orgId}_$_uid';
      try {
        final updates = <String, dynamic>{'displayName': displayName};
        if (photoUrl != null) updates['photoUrl'] = photoUrl;
        await _db.updateDocument(
            databaseId: _dbId,
            collectionId: _colMembers,
            documentId: memberId,
            data: updates);
      } catch (_) {}
    }
  }

  Future<void> setHideEmail(bool hideEmail) async {
    await _db.updateDocument(
        databaseId: _dbId,
        collectionId: 'users',
        documentId: _uid,
        data: {'hideEmail': hideEmail});

    final userDoc = await _db.getDocument(
        databaseId: _dbId, collectionId: 'users', documentId: _uid);
    final membershipsJson = userDoc.data['membershipsJson'] as String?;
    if (membershipsJson == null || membershipsJson.isEmpty) return;
    final memberships =
        List<Map<String, dynamic>>.from(_decodeMemberships(membershipsJson));
    for (final m in memberships) {
      final orgId = m['orgId'] as String?;
      if (orgId == null) continue;
      try {
        await _db.updateDocument(
            databaseId: _dbId,
            collectionId: _colMembers,
            documentId: '${orgId}_$_uid',
            data: {'hideEmail': hideEmail});
      } catch (_) {}
    }
  }

  Future<void> updateChildAlertInterval(
      String orgId, ChildAlertInterval interval) async {
    await _db.updateDocument(
      databaseId: _dbId,
      collectionId: _colMembers,
      documentId: '${orgId}_$_uid',
      data: {'childAlertInterval': interval.name},
    );
  }

  Future<void> setOrgMessageInterval(
      String orgId, MessageAlertInterval interval) async {
    await _db.updateDocument(
      databaseId: _dbId,
      collectionId: _colMembers,
      documentId: '${orgId}_$_uid',
      data: {
        'messageAlertInterval': interval.name,
        'notificationsEnabled': interval != MessageAlertInterval.never,
      },
    );
  }

  Future<void> updateKeywords(String orgId, List<String> keywords) async {
    await _db.updateDocument(
        databaseId: _dbId,
        collectionId: _colOrgs,
        documentId: orgId,
        data: {'keywords': keywords});
  }

  // ── Adressbuch ─────────────────────────────────────────────────────────────

  Future<List<OrgMember>> getAddressBook(String excludeOrgId) async {
    final userDoc = await _db.getDocument(
        databaseId: _dbId, collectionId: 'users', documentId: _uid);
    final membershipsJson = userDoc.data['membershipsJson'] as String?;
    if (membershipsJson == null || membershipsJson.isEmpty) return [];
    final memberships =
        List<Map<String, dynamic>>.from(_decodeMemberships(membershipsJson));

    // Aktuelle Org-Mitglieder ermitteln (zum Ausschluss)
    final currentOrgResult = await _db.listDocuments(
      databaseId: _dbId,
      collectionId: _colMembers,
      queries: [Query.equal('orgId', excludeOrgId), Query.limit(500)],
    );
    final currentOrgUids =
        currentOrgResult.documents.map((d) => d.data['uid'] as String).toSet();

    final Map<String, OrgMember> result = {};
    for (final m in memberships) {
      final orgId = m['orgId'] as String?;
      if (orgId == null || orgId == excludeOrgId) continue;
      try {
        final snap = await _db.listDocuments(
          databaseId: _dbId,
          collectionId: _colMembers,
          queries: [
            Query.equal('orgId', orgId),
            Query.equal('status', 'active'),
            Query.limit(200),
          ],
        );
        for (final doc in snap.documents) {
          final uid = doc.data['uid'] as String;
          if (uid == _uid || currentOrgUids.contains(uid)) continue;
          result.putIfAbsent(uid,
              () => OrgMember.fromAppwrite({r'$id': doc.$id, ...doc.data}));
        }
      } catch (_) {}
    }
    return result.values.toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
  }

  // ── Mitglied-Vorschläge (stub) ─────────────────────────────────────────────

  Future<void> suggestMember(String orgId, String email, OrgRole role,
      {List<String> guardianUids = const []}) async {
    // TODO: add member_suggestions collection to Appwrite schema
  }

  Stream<List<MemberSuggestion>> watchPendingSuggestions(String orgId) =>
      Stream.value([]);

  Future<void> approveSuggestion(String orgId, String suggestionId,
      String email, OrgRole role, List<String> guardianUids) async {
    await inviteMember(orgId, email, role, guardianUids: guardianUids);
  }

  Future<void> rejectSuggestion(String orgId, String suggestionId) async {}

  // ── Ankündigungen ──────────────────────────────────────────────────────────

  Stream<List<Announcement>> watchAnnouncements(String orgId) {
    return _watchCollection<Announcement>(
      _colAnnouncements,
      Announcement.fromAppwrite,
      [
        Query.equal('orgId', orgId),
        Query.orderDesc('createdAt'),
      ],
    );
  }

  Future<void> createAnnouncement(String orgId, String title, String content,
      {DateTime? expiresAt}) async {
    final ann = Announcement(
      id: '',
      title: title,
      content: content,
      authorUid: _uid,
      authorName: _displayName,
      createdAt: DateTime.now().toUtc(),
      expiresAt: expiresAt,
    );
    await _db.createDocument(
      databaseId: _dbId,
      collectionId: _colAnnouncements,
      documentId: ID.unique(),
      data: {...ann.toAppwrite(), 'orgId': orgId},
      permissions: [Permission.read(Role.users())],
    );
  }

  Future<void> editAnnouncement(
      String orgId, String annId, String title, String content,
      {DateTime? expiresAt, bool clearExpiry = false}) async {
    final updates = <String, dynamic>{
      'title': title,
      'content': content,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      if (expiresAt != null) 'expiresAt': expiresAt.toUtc().toIso8601String(),
      if (clearExpiry) 'expiresAt': null,
    };
    await _db.updateDocument(
        databaseId: _dbId,
        collectionId: _colAnnouncements,
        documentId: annId,
        data: updates);
  }

  Future<void> deleteAnnouncement(String orgId, String annId) async {
    await _db.deleteDocument(
        databaseId: _dbId, collectionId: _colAnnouncements, documentId: annId);
  }

  Future<void> reactToAnnouncement(
      String orgId, String annId, String uid, String? emoji) async {
    final doc = await _db.getDocument(
        databaseId: _dbId, collectionId: _colAnnouncements, documentId: annId);
    final ann = Announcement.fromAppwrite({r'$id': doc.$id, ...doc.data});
    final reactions = Map<String, String>.from(ann.reactions);
    if (emoji == null) {
      reactions.remove(uid);
    } else {
      reactions[uid] = emoji;
    }
    await _db.updateDocument(
        databaseId: _dbId,
        collectionId: _colAnnouncements,
        documentId: annId,
        data: {'reactionsJson': _encodeJson(reactions)});
  }

  // ── Termine (Events) ───────────────────────────────────────────────────────

  Future<void> createEvent(
    String orgId,
    String title,
    DateTime eventDate, {
    String content = '',
    DateTime? eventEndDate,
    String? location,
    bool rsvpPublic = false,
  }) async {
    final ann = Announcement(
      id: '',
      title: title,
      content: content,
      authorUid: _uid,
      authorName: _displayName,
      createdAt: DateTime.now().toUtc(),
      type: AnnouncementType.event,
      eventDate: eventDate,
      eventEndDate: eventEndDate,
      location: location,
      rsvpPublic: rsvpPublic,
    );
    await _db.createDocument(
      databaseId: _dbId,
      collectionId: _colAnnouncements,
      documentId: ID.unique(),
      data: {...ann.toAppwrite(), 'orgId': orgId},
      permissions: [Permission.read(Role.users())],
    );
  }

  Future<void> editEvent(
    String orgId,
    String annId,
    String title,
    DateTime eventDate, {
    String content = '',
    DateTime? eventEndDate,
    String? location,
    bool rsvpPublic = false,
  }) async {
    await _db.updateDocument(
        databaseId: _dbId,
        collectionId: _colAnnouncements,
        documentId: annId,
        data: {
          'title': title,
          'content': content,
          'eventDate': eventDate.toUtc().toIso8601String(),
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
          'eventEndDate': eventEndDate?.toUtc().toIso8601String(),
          'location':
              (location != null && location.isNotEmpty) ? location : null,
          'rsvpPublic': rsvpPublic,
        });
  }

  Future<void> respondToEvent(
      String orgId, String annId, String uid, RsvpStatus? status) async {
    final doc = await _db.getDocument(
        databaseId: _dbId, collectionId: _colAnnouncements, documentId: annId);
    final ann = Announcement.fromAppwrite({r'$id': doc.$id, ...doc.data});
    final rsvp = Map<String, String>.from(ann.rsvp);
    if (status == null) {
      rsvp.remove(uid);
    } else {
      rsvp[uid] = status.toJson();
    }
    await _db.updateDocument(
        databaseId: _dbId,
        collectionId: _colAnnouncements,
        documentId: annId,
        data: {'rsvpJson': _encodeJson(rsvp)});
  }

  // ── Benachrichtigungsintervall (Realtime) ──────────────────────────────────

  Stream<MessageAlertInterval> watchOrgMessageInterval(String orgId) {
    final memberId = '${orgId}_$_uid';
    StreamController<MessageAlertInterval>? ctrl;
    StreamSubscription? realtimeSub;

    Future<void> reload() async {
      if (ctrl == null || ctrl.isClosed) return;
      try {
        final doc = await _db.getDocument(
            databaseId: _dbId,
            collectionId: _colMembers,
            documentId: memberId);
        final name = doc.data['messageAlertInterval'] as String?;
        final interval = MessageAlertInterval.values
                .where((e) => e.name == name)
                .firstOrNull ??
            MessageAlertInterval.always;
        if (!ctrl.isClosed) ctrl.add(interval);
      } catch (_) {
        if (ctrl != null && !ctrl.isClosed) {
          ctrl.add(MessageAlertInterval.always);
        }
      }
    }

    void dispose() {
      realtimeSub?.cancel();
      ctrl?.close();
    }

    ctrl = StreamController(onCancel: dispose);
    realtimeSub = _broadcaster
        .stream('databases.$_dbId.collections.$_colMembers.documents.$memberId')
        .listen((_) => reload(), onDone: dispose, onError: (_) {});
    reload();
    return ctrl.stream;
  }

  // ── User Display Name ──────────────────────────────────────────────────────

  Future<String> getUserDisplayName(String uid) async {
    try {
      final doc = await _db.getDocument(
          databaseId: _dbId, collectionId: 'users', documentId: uid);
      return doc.data['displayName'] as String? ?? uid;
    } catch (_) {
      return uid;
    }
  }

  // ── Hilfsmethoden ──────────────────────────────────────────────────────────

  /// Ruft die admin-member-action Cloud Function auf und gibt den geparsten Body zurück.
  /// Bei HTTP-Fehler oder CF-Fehler enthält das Ergebnis `{'error': '...'}`.
  Future<Map<String, dynamic>> _callAdminMemberAction(
    String action,
    String orgId, {
    String? targetUid,
    Map<String, dynamic> payload = const {},
  }) async {
    try {
      final execution = await _functions.createExecution(
        functionId: _adminMemberActionId,
        body: jsonEncode({
          'action': action,
          'orgId': orgId,
          if (targetUid != null) 'targetUid': targetUid,
          if (payload.isNotEmpty) 'payload': payload,
        }),
        method: ExecutionMethod.pOST,
        xasync: false,
      );
      final body = execution.responseBody;
      if (body.isEmpty) return {'error': 'Empty response from function'};
      return Map<String, dynamic>.from(jsonDecode(body) as Map);
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<void> _updateMembershipsJson(
      String targetUid, OrgMembership membership,
      {required bool add}) async {
    try {
      final doc = await _db.getDocument(
          databaseId: _dbId, collectionId: 'users', documentId: targetUid);
      final raw = doc.data['membershipsJson'] as String?;
      final memberships = raw != null && raw.isNotEmpty
          ? List<Map<String, dynamic>>.from(_decodeMemberships(raw))
          : <Map<String, dynamic>>[];
      if (add) {
        if (!memberships.any((m) => m['orgId'] == membership.orgId)) {
          memberships.add(membership.toMap());
        }
      } else {
        memberships.removeWhere((m) =>
            m['orgId'] == membership.orgId &&
            m['role'] == membership.role.name);
      }
      await _db.updateDocument(
          databaseId: _dbId,
          collectionId: 'users',
          documentId: targetUid,
          data: {'membershipsJson': _encodeJson(memberships)});
    } catch (_) {}
  }

  Future<aw.Document?> _safeGetDocument(String col, String docId) async {
    try {
      return await _db.getDocument(
          databaseId: _dbId, collectionId: col, documentId: docId);
    } on AppwriteException catch (e) {
      if (e.code == 404) return null;
      rethrow;
    }
  }

  static List<dynamic> _decodeMemberships(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : [];
    } catch (_) {
      return [];
    }
  }

  static String _encodeJson(dynamic obj) => jsonEncode(obj);

  Stream<List<OrgAuditEntry>> watchAuditLog(String orgId) {
    return _watchCollection<OrgAuditEntry>(
      _colAuditLog,
      (data) => OrgAuditEntry.fromAppwrite(data),
      [Query.equal('orgId', orgId), Query.orderDesc('timestamp'), Query.limit(100)],
    );
  }

  Future<void> _logAuditEvent(
      String orgId, AuditAction action, Map<String, dynamic> details) async {
    try {
      final entry = OrgAuditEntry(
        id: ID.unique(),
        actorUid: _uid,
        actorName: _displayName,
        action: action,
        details: details,
        timestamp: DateTime.now().toUtc(),
      );
      await _db.createDocument(
        databaseId: _dbId,
        collectionId: _colAuditLog,
        documentId: entry.id,
        data: entry.toAppwrite(orgId),
      );
    } catch (e) {
      debugPrint('[AuditLog] _logAuditEvent failed: $e');
    }
  }
}
