import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/announcement.dart';
import '../models/org_audit_entry.dart';
import '../models/organization.dart';
import '../models/app_user.dart';
import '../models/org_member.dart';
import '../models/member_suggestion.dart';
import '../models/notification_settings.dart';
import '../models/org_invite_consent.dart';

class OrganizationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _uid => _auth.currentUser!.uid;

  /// Schreibt einen Eintrag ins Änderungsprotokoll der Organisation.
  Future<void> _logAudit(
      String orgId, AuditAction action, Map<String, dynamic> details) async {
    final user = _auth.currentUser;
    await _db
        .collection('organizations')
        .doc(orgId)
        .collection('auditLog')
        .add({
      'actorUid': _uid,
      'actorName': user?.displayName ?? user?.email ?? '',
      'action': action.name,
      'details': details,
      'timestamp': Timestamp.now(),
    });
  }

  Stream<List<OrgAuditEntry>> watchAuditLog(String orgId) {
    return _db
        .collection('organizations')
        .doc(orgId)
        .collection('auditLog')
        .orderBy('timestamp', descending: true)
        .limit(100)
        .snapshots()
        .map((s) => s.docs.map(OrgAuditEntry.fromFirestore).toList());
  }

  Future<Organization> createOrganization(
      String name, OrgTag tag, ChatMode chatMode) async {
    final orgRef = _db.collection('organizations').doc();
    final now = DateTime.now();
    final currentUser = _auth.currentUser!;

    final org = Organization(
      id: orgRef.id,
      name: name,
      adminUid: _uid,
      tag: tag,
      chatMode: chatMode,
      memberUids: [_uid],
      createdAt: now,
    );

    final membership = OrgMembership(orgId: orgRef.id, role: OrgRole.admin);
    final memberDoc = orgRef.collection('members').doc(_uid);

    await _db.runTransaction((tx) async {
      tx.set(orgRef, org.toFirestore());
      tx.set(memberDoc, OrgMember(
        uid: _uid,
        displayName: currentUser.displayName ?? currentUser.email!,
        email: currentUser.email!,
        photoUrl: currentUser.photoURL,
        role: OrgRole.admin,
        joinedAt: now,
      ).toFirestore());
      tx.update(_db.collection('users').doc(_uid), {
        'memberships': FieldValue.arrayUnion([membership.toMap()]),
      });
    });

    return org;
  }

  /// Synchronisiert displayName und photoUrl in allen Member-Dokumenten des Nutzers.
  /// Liest die orgIds aus users/{uid}.memberships und batch-updated jeden Eintrag.
  Future<void> updateMyMemberProfile(
      String displayName, {String? photoUrl}) async {
    final userDoc = await _db.collection('users').doc(_uid).get();
    final memberships = List<Map<String, dynamic>>.from(
        userDoc.data()?['memberships'] as List? ?? []);
    if (memberships.isEmpty) return;

    final batch = _db.batch();
    for (final m in memberships) {
      final orgId = m['orgId'] as String?;
      if (orgId == null) continue;
      final memberRef = _db
          .collection('organizations')
          .doc(orgId)
          .collection('members')
          .doc(_uid);
      final updates = <String, dynamic>{'displayName': displayName};
      if (photoUrl != null) updates['photoUrl'] = photoUrl;
      batch.update(memberRef, updates);
    }
    await batch.commit();
  }

  Future<void> updateOrganization(String orgId,
      {String? name, OrgTag? tag, ChatMode? chatMode}) async {
    final updates = <String, dynamic>{
      'name': ?name,
      if (tag != null) 'tag': tag.name,
      if (chatMode != null) 'chatMode': chatMode.name,
    };
    if (updates.isNotEmpty) {
      await _db.collection('organizations').doc(orgId).update(updates);
      await _logAudit(orgId, AuditAction.settingsChanged, {
        if (name != null) 'name': name,
        if (tag != null) 'tag': tag.name,
      });
    }
  }

  Future<void> inviteMember(String orgId, String email, OrgRole role,
      {List<String> guardianUids = const []}) async {
    final normalizedEmail = email.toLowerCase().trim();
    final isChild = role == OrgRole.child;
    if (isChild && guardianUids.isEmpty) {
      throw Exception('Für ein Kind muss mindestens ein Guardian ausgewählt werden.');
    }

    // Org-Name laden für die Einladungs-Anzeige
    final orgDoc = await _db.collection('organizations').doc(orgId).get();
    final orgName = orgDoc.data()?['name'] as String? ?? '';

    // Prüfen ob User bereits registriert ist
    final query = await _db
        .collection('users')
        .where('email', isEqualTo: normalizedEmail)
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      // User noch nicht registriert → Einladung erstellen
      final existingInvite = await _db
          .collection('invitations')
          .where('email', isEqualTo: normalizedEmail)
          .where('orgId', isEqualTo: orgId)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();
      if (existingInvite.docs.isNotEmpty) {
        throw Exception('Für diese E-Mail gibt es bereits eine ausstehende Einladung.');
      }
      final inviteRef = await _db.collection('invitations').add({
        'email': normalizedEmail,
        'orgId': orgId,
        'orgName': orgName,
        'role': role.name,
        'guardianUids': guardianUids,
        'invitedBy': _uid,
        'status': 'pending',
        'createdAt': Timestamp.now(),
      });
      await _writeInvitationLookup(normalizedEmail, inviteRef.id);
      await _logAudit(orgId, AuditAction.invitationSent,
          {'email': normalizedEmail, 'role': role.name});
      return;
    }

    // User bereits registriert → direkt hinzufügen
    final userDoc = query.docs.first;
    final userData = userDoc.data();
    final targetUid = userDoc.id;

    final memberDoc = _db
        .collection('organizations')
        .doc(orgId)
        .collection('members')
        .doc(targetUid);

    final existing = await memberDoc.get();
    if (existing.exists) {
      throw Exception('Dieser Benutzer ist bereits Mitglied.');
    }

    // Wenn der Nutzer verifizierte Eltern hat → Einwilligung einholen
    final parentUids = List<String>.from(
        userData['verifiedParentUids'] as List? ?? []);
    if (parentUids.isNotEmpty) {
      final currentUser = _auth.currentUser!;
      final now = DateTime.now();
      await _db.collection('orgInviteConsents').add(
        OrgInviteConsent(
          id: '',
          childUid: targetUid,
          childName: userData['displayName'] as String? ?? '',
          orgId: orgId,
          orgName: orgName,
          invitedByUid: _uid,
          invitedByName:
              currentUser.displayName ?? currentUser.email ?? '',
          proposedGuardianUids: guardianUids,
          parentUids: parentUids,
          status: OrgInviteConsentStatus.pending,
          createdAt: now,
          expiresAt: now.add(const Duration(days: 7)),
        ).toFirestore(),
      );
      return;
    }

    final memberStatus = isChild ? MemberStatus.pending : MemberStatus.active;
    final membership = OrgMembership(orgId: orgId, role: role);

    await _db.runTransaction((tx) async {
      tx.set(memberDoc, OrgMember(
        uid: targetUid,
        displayName: userData['displayName'] as String,
        email: userData['email'] as String,
        photoUrl: userData['photoUrl'] as String?,
        role: role,
        joinedAt: DateTime.now(),
        guardianUids: isChild ? guardianUids : [],
        status: memberStatus,
      ).toFirestore());
      if (!isChild) {
        tx.update(_db.collection('organizations').doc(orgId), {
          'memberUids': FieldValue.arrayUnion([targetUid]),
        });
        tx.update(_db.collection('users').doc(targetUid), {
          'memberships': FieldValue.arrayUnion([membership.toMap()]),
        });
      }
    });
    await _logAudit(orgId, AuditAction.invitationSent, {
      'email': normalizedEmail,
      'name': userData['displayName'] as String? ?? normalizedEmail,
      'role': role.name,
    });
  }

  Future<void> updateGuardians(
      String orgId, String childUid, List<String> guardianUids) async {
    await _db
        .collection('organizations')
        .doc(orgId)
        .collection('members')
        .doc(childUid)
        .update({'guardianUids': guardianUids});
  }

  Future<void> approveChildInvite(String orgId, String childUid) async {
    final memberDoc = _db
        .collection('organizations')
        .doc(orgId)
        .collection('members')
        .doc(childUid);

    final snap = await memberDoc.get();
    if (!snap.exists) return;

    final role = OrgRole.values.byName(snap.data()!['role'] as String);
    final membership = OrgMembership(orgId: orgId, role: role);

    final childName = snap.data()!['displayName'] as String? ?? '';
    await _db.runTransaction((tx) async {
      tx.update(memberDoc, {'status': MemberStatus.active.name});
      tx.update(_db.collection('organizations').doc(orgId), {
        'memberUids': FieldValue.arrayUnion([childUid]),
      });
      tx.update(_db.collection('users').doc(childUid), {
        'memberships': FieldValue.arrayUnion([membership.toMap()]),
        'isChild': true,
      });
    });
    await _logAudit(orgId, AuditAction.memberConfirmed, {'name': childName});
  }

  Future<void> rejectChildInvite(String orgId, String childUid) async {
    final memberDoc = _db
        .collection('organizations')
        .doc(orgId)
        .collection('members')
        .doc(childUid);
    await memberDoc.delete();
  }

  Stream<List<OrgMember>> watchPendingChildInvites(
      String orgId, String guardianUid) {
    return _db
        .collection('organizations')
        .doc(orgId)
        .collection('members')
        .where('guardianUids', arrayContains: guardianUid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((s) => s.docs.map(OrgMember.fromFirestore).toList());
  }

  Stream<List<Map<String, dynamic>>> watchPendingInvitationsForGuardian(
      String orgId, String guardianUid) {
    return _db
        .collection('invitations')
        .where('orgId', isEqualTo: orgId)
        .where('guardianUids', arrayContains: guardianUid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((s) => s.docs
            .map((d) => {'id': d.id, ...d.data()})
            .toList());
  }

  Future<void> cancelInvitation(String inviteId) async {
    await _db.collection('invitations').doc(inviteId).update({'status': 'cancelled'});
  }

  Future<void> updateChildAlertInterval(
      String orgId, ChildAlertInterval interval) async {
    await _db
        .collection('organizations')
        .doc(orgId)
        .collection('members')
        .doc(_uid)
        .update({'childAlertInterval': interval.name});
  }

  Future<void> updateKeywords(String orgId, List<String> keywords) async {
    await _db.collection('organizations').doc(orgId).update({'keywords': keywords});
    await _logAudit(orgId, AuditAction.keywordsChanged,
        {'count': keywords.length});
  }

  Future<void> archiveOrganization(String orgId) async {
    await _db.collection('organizations').doc(orgId).update({'isArchived': true});
  }

  Future<void> unarchiveOrganization(String orgId) async {
    await _db.collection('organizations').doc(orgId).update({'isArchived': false});
  }

  Future<void> deleteOrganization(String orgId) async {
    final membersSnap = await _db
        .collection('organizations')
        .doc(orgId)
        .collection('members')
        .get();

    final batch = _db.batch();
    for (final memberDoc in membersSnap.docs) {
      final role = OrgRole.values.byName(memberDoc.data()['role'] as String);
      final membership = OrgMembership(orgId: orgId, role: role);
      batch.delete(memberDoc.reference);
      batch.update(_db.collection('users').doc(memberDoc.id), {
        'memberships': FieldValue.arrayRemove([membership.toMap()]),
      });
    }
    batch.delete(_db.collection('organizations').doc(orgId));
    await batch.commit();
  }

  Future<void> removeMember(String orgId, String targetUid) async {
    final memberDoc = _db
        .collection('organizations')
        .doc(orgId)
        .collection('members')
        .doc(targetUid);

    final snap = await memberDoc.get();
    if (!snap.exists) return;

    final memberName = snap.data()!['displayName'] as String? ?? '';
    final role = OrgRole.values.byName(snap.data()!['role'] as String);
    final membership = OrgMembership(orgId: orgId, role: role);
    final userDoc = _db.collection('users').doc(targetUid);

    await _db.runTransaction((tx) async {
      // User-Dokument innerhalb der Transaction lesen – es könnte bereits
      // gelöscht worden sein (z. B. manuell in der Firebase Console).
      final userSnap = await tx.get(userDoc);
      tx.delete(memberDoc);
      tx.update(_db.collection('organizations').doc(orgId), {
        'memberUids': FieldValue.arrayRemove([targetUid]),
      });
      if (userSnap.exists) {
        tx.update(userDoc, {
          'memberships': FieldValue.arrayRemove([membership.toMap()]),
        });
      }
    });
    await _logAudit(orgId, AuditAction.memberRemoved, {'name': memberName});
  }

  Future<void> leaveOrganization(String orgId) async {
    final memberDoc = _db
        .collection('organizations')
        .doc(orgId)
        .collection('members')
        .doc(_uid);

    final snap = await memberDoc.get();
    if (!snap.exists) return;

    final role = OrgRole.values.byName(snap.data()!['role'] as String);
    if (role == OrgRole.admin) {
      throw Exception(
          'Als Admin kannst du die Organisation nicht verlassen. '
          'Übertrage zuerst die Admin-Rolle an ein anderes Mitglied.');
    }

    final membership = OrgMembership(orgId: orgId, role: role);

    await _db.runTransaction((tx) async {
      tx.delete(memberDoc);
      tx.update(_db.collection('organizations').doc(orgId), {
        'memberUids': FieldValue.arrayRemove([_uid]),
      });
      tx.update(_db.collection('users').doc(_uid), {
        'memberships': FieldValue.arrayRemove([membership.toMap()]),
      });
    });
  }

  Future<void> transferAdmin(String orgId, String newAdminUid) async {
    final oldAdminUid = _uid;

    final newAdminMemberRef = _db
        .collection('organizations')
        .doc(orgId)
        .collection('members')
        .doc(newAdminUid);

    final snap = await newAdminMemberRef.get();
    if (!snap.exists) throw Exception('Mitglied nicht gefunden.');

    final newAdminOldRole =
        OrgRole.values.byName(snap.data()!['role'] as String);

    final oldAdminOldMembership = OrgMembership(orgId: orgId, role: OrgRole.admin);
    final oldAdminNewMembership = OrgMembership(orgId: orgId, role: OrgRole.member);
    final newAdminOldMembership = OrgMembership(orgId: orgId, role: newAdminOldRole);
    final newAdminNewMembership = OrgMembership(orgId: orgId, role: OrgRole.admin);

    await _db.runTransaction((tx) async {
      // Org: adminUid aktualisieren
      tx.update(_db.collection('organizations').doc(orgId), {
        'adminUid': newAdminUid,
      });
      // Alter Admin → Member
      tx.update(
        _db.collection('organizations').doc(orgId).collection('members').doc(oldAdminUid),
        {'role': OrgRole.member.name},
      );
      // Neuer Admin → admin
      tx.update(newAdminMemberRef, {'role': OrgRole.admin.name});
      // Memberships alter Admin
      tx.update(_db.collection('users').doc(oldAdminUid), {
        'memberships': FieldValue.arrayRemove([oldAdminOldMembership.toMap()]),
      });
      tx.update(_db.collection('users').doc(oldAdminUid), {
        'memberships': FieldValue.arrayUnion([oldAdminNewMembership.toMap()]),
      });
      // Memberships neuer Admin
      tx.update(_db.collection('users').doc(newAdminUid), {
        'memberships': FieldValue.arrayRemove([newAdminOldMembership.toMap()]),
      });
      tx.update(_db.collection('users').doc(newAdminUid), {
        'memberships': FieldValue.arrayUnion([newAdminNewMembership.toMap()]),
      });
    });
    final newAdminName = snap.data()!['displayName'] as String? ?? '';
    await _logAudit(orgId, AuditAction.adminTransferred,
        {'newAdminName': newAdminName});
  }

  Future<void> updateMemberRole(String orgId, String targetUid, OrgRole newRole) async {
    // Block non-child roles for child accounts.
    if (newRole != OrgRole.child) {
      final userSnap = await _db.collection('users').doc(targetUid).get();
      final isChildAccount = userSnap.data()?['isChild'] as bool? ?? false;
      if (isChildAccount) {
        throw Exception('child_account_role_locked');
      }
    }

    final memberDoc = _db
        .collection('organizations')
        .doc(orgId)
        .collection('members')
        .doc(targetUid);

    final snap = await memberDoc.get();
    if (!snap.exists) return;

    final oldRole = OrgRole.values.byName(snap.data()!['role'] as String);
    final oldMembership = OrgMembership(orgId: orgId, role: oldRole);
    final newMembership = OrgMembership(orgId: orgId, role: newRole);

    final memberName = snap.data()!['displayName'] as String? ?? '';
    await _db.runTransaction((tx) async {
      tx.update(memberDoc, {'role': newRole.name});
      tx.update(_db.collection('users').doc(targetUid), {
        'memberships': FieldValue.arrayRemove([oldMembership.toMap()]),
      });
      tx.update(_db.collection('users').doc(targetUid), {
        'memberships': FieldValue.arrayUnion([newMembership.toMap()]),
      });
    });
    await _logAudit(orgId, AuditAction.roleChanged, {
      'name': memberName,
      'oldRole': oldRole.name,
      'newRole': newRole.name,
    });
  }

  Stream<List<Organization>> watchMyOrganizations() {
    return _db
        .collection('organizations')
        .where('memberUids', arrayContains: _uid)
        .snapshots()
        .map((snap) => snap.docs.map(Organization.fromFirestore).toList());
  }

  Stream<Organization> watchOrganization(String orgId) {
    return _db
        .collection('organizations')
        .doc(orgId)
        .snapshots()
        .map(Organization.fromFirestore);
  }

  Future<void> setOrgMessageInterval(
      String orgId, MessageAlertInterval interval) async {
    await _db
        .collection('organizations')
        .doc(orgId)
        .collection('members')
        .doc(_uid)
        .update({
      'messageAlertInterval': interval.name,
      'notificationsEnabled': interval != MessageAlertInterval.never,
    });
  }

  Stream<List<OrgMember>> watchMembers(String orgId) {
    return _db
        .collection('organizations')
        .doc(orgId)
        .collection('members')
        .snapshots()
        .map((snap) => snap.docs.map(OrgMember.fromFirestore).toList());
  }

  // ── Mitglied-Vorschläge ──────────────────────────────────────────────────

  Future<void> suggestMember(String orgId, String email, OrgRole role,
      {List<String> guardianUids = const []}) async {
    final normalizedEmail = email.toLowerCase().trim();
    final currentUser = _auth.currentUser!;

    await _db
        .collection('organizations')
        .doc(orgId)
        .collection('memberSuggestions')
        .add({
      'email': normalizedEmail,
      'role': role.name,
      'guardianUids': guardianUids,
      'suggestedByUid': _uid,
      'suggestedByName': currentUser.displayName ?? currentUser.email ?? '',
      'orgId': orgId,
      'status': 'pending',
      'createdAt': Timestamp.now(),
    });
  }

  Stream<List<MemberSuggestion>> watchPendingSuggestions(String orgId) {
    return _db
        .collection('organizations')
        .doc(orgId)
        .collection('memberSuggestions')
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt')
        .snapshots()
        .map((s) => s.docs.map(MemberSuggestion.fromFirestore).toList());
  }

  Future<void> approveSuggestion(String orgId, String suggestionId,
      String email, OrgRole role, List<String> guardianUids) async {
    final normalizedEmail = email.toLowerCase().trim();
    final isChild = role == OrgRole.child;

    // Prüfen ob User bereits registriert ist
    final query = await _db
        .collection('users')
        .where('email', isEqualTo: normalizedEmail)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      // ── Bereits registriert → direkt hinzufügen ──────────────────────────
      final userDoc = query.docs.first;
      final targetUid = userDoc.id;
      final userData = userDoc.data();

      final memberDoc = _db
          .collection('organizations')
          .doc(orgId)
          .collection('members')
          .doc(targetUid);

      final existing = await memberDoc.get();
      if (!existing.exists) {
        final membership = OrgMembership(orgId: orgId, role: role);
        await _db.runTransaction((tx) async {
          tx.set(
            memberDoc,
            OrgMember(
              uid: targetUid,
              displayName: userData['displayName'] as String,
              email: userData['email'] as String,
              photoUrl: userData['photoUrl'] as String?,
              role: role,
              joinedAt: DateTime.now(),
              guardianUids: isChild ? guardianUids : [],
              status: isChild ? MemberStatus.pending : MemberStatus.active,
            ).toFirestore(),
          );
          if (!isChild) {
            tx.update(_db.collection('organizations').doc(orgId), {
              'memberUids': FieldValue.arrayUnion([targetUid]),
            });
            tx.update(_db.collection('users').doc(targetUid), {
              'memberships': FieldValue.arrayUnion([membership.toMap()]),
            });
          }
        });
      }
    } else {
      // ── Noch nicht registriert → Einladung anlegen / aktualisieren ───────
      final orgDoc =
          await _db.collection('organizations').doc(orgId).get();
      final orgName = orgDoc.data()?['name'] as String? ?? '';

      final existingInvite = await _db
          .collection('invitations')
          .where('email', isEqualTo: normalizedEmail)
          .where('orgId', isEqualTo: orgId)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();

      if (existingInvite.docs.isNotEmpty) {
        // Vorhandene Einladung aktualisieren (kein Fehler bei Duplikat)
        final existingId = existingInvite.docs.first.id;
        await existingInvite.docs.first.reference.update({
          'role': role.name,
          'guardianUids': guardianUids,
          'invitedBy': _uid,
          'updatedAt': Timestamp.now(),
        });
        await _writeInvitationLookup(normalizedEmail, existingId);
      } else {
        final inviteRef = await _db.collection('invitations').add({
          'email': normalizedEmail,
          'orgId': orgId,
          'orgName': orgName,
          'role': role.name,
          'guardianUids': guardianUids,
          'invitedBy': _uid,
          'status': 'pending',
          'createdAt': Timestamp.now(),
        });
        await _writeInvitationLookup(normalizedEmail, inviteRef.id);
      }
    }

    // Vorschlag als angenommen markieren
    await _db
        .collection('organizations')
        .doc(orgId)
        .collection('memberSuggestions')
        .doc(suggestionId)
        .update({'status': 'approved'});
  }

  Future<void> rejectSuggestion(String orgId, String suggestionId) async {
    await _db
        .collection('organizations')
        .doc(orgId)
        .collection('memberSuggestions')
        .doc(suggestionId)
        .update({'status': 'rejected'});
  }

  /// Speichert eine Einladungs-ID in einem Lookup-Dokument, das direkt per
  /// E-Mail-Adresse abrufbar ist (kein List-Query nötig → keine Regel-Probleme).
  Future<void> _writeInvitationLookup(
      String normalizedEmail, String invitationId) async {
    await _db.collection('invitationLookup').doc(normalizedEmail).set(
      {'invitationIds': FieldValue.arrayUnion([invitationId])},
      SetOptions(merge: true),
    );
  }

  // ── Ankündigungen (Pinnwand) ───────────────────────────────────────────────

  Stream<List<Announcement>> watchAnnouncements(String orgId) {
    return _db
        .collection('organizations')
        .doc(orgId)
        .collection('announcements')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(Announcement.fromFirestore).toList());
  }

  Future<void> createAnnouncement(
      String orgId, String title, String content,
      {DateTime? expiresAt}) async {
    final user = _auth.currentUser!;
    final ref = _db
        .collection('organizations')
        .doc(orgId)
        .collection('announcements')
        .doc();
    await ref.set(Announcement(
      id: ref.id,
      title: title,
      content: content,
      authorUid: user.uid,
      authorName: user.displayName ?? user.email ?? '',
      createdAt: DateTime.now(),
      expiresAt: expiresAt,
    ).toFirestore());
  }

  Future<void> editAnnouncement(
      String orgId, String announcementId, String title, String content,
      {DateTime? expiresAt, bool clearExpiry = false}) async {
    await _db
        .collection('organizations')
        .doc(orgId)
        .collection('announcements')
        .doc(announcementId)
        .update({
      'title': title,
      'content': content,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
      if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt),
      if (clearExpiry) 'expiresAt': FieldValue.delete(),
    });
  }

  Future<void> deleteAnnouncement(
      String orgId, String announcementId) async {
    await _db
        .collection('organizations')
        .doc(orgId)
        .collection('announcements')
        .doc(announcementId)
        .delete();
  }

  Future<void> reactToAnnouncement(
      String orgId, String announcementId, String uid, String? emoji) async {
    final ref = _db
        .collection('organizations')
        .doc(orgId)
        .collection('announcements')
        .doc(announcementId);
    if (emoji == null) {
      await ref.update({'reactions.$uid': FieldValue.delete()});
    } else {
      await ref.update({'reactions.$uid': emoji});
    }
  }
}
