import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/organization.dart';
import '../models/app_user.dart';
import '../models/org_member.dart';

class OrganizationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _uid => _auth.currentUser!.uid;

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

  Future<void> updateOrganization(String orgId,
      {String? name, OrgTag? tag, ChatMode? chatMode}) async {
    final updates = <String, dynamic>{
      if (name != null) 'name': name,
      if (tag != null) 'tag': tag.name,
      if (chatMode != null) 'chatMode': chatMode.name,
    };
    if (updates.isNotEmpty) {
      await _db.collection('organizations').doc(orgId).update(updates);
    }
  }

  Future<void> inviteMember(String orgId, String email, OrgRole role,
      {String? guardianUid}) async {
    final query = await _db
        .collection('users')
        .where('email', isEqualTo: email.toLowerCase().trim())
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      throw Exception(
        'Kein Benutzer mit dieser E-Mail gefunden.\n'
        'Die Person muss sich zuerst einmal in der App angemeldet haben.',
      );
    }

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

    // Kinder brauchen einen Guardian und starten mit Status "pending"
    final isChild = role == OrgRole.child;
    if (isChild && guardianUid == null) {
      throw Exception('Für ein Kind muss ein Guardian ausgewählt werden.');
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
        guardianUid: isChild ? guardianUid : null,
        status: memberStatus,
      ).toFirestore());
      // Kinder werden erst nach Guardian-Zustimmung zu memberUids hinzugefügt
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

    await _db.runTransaction((tx) async {
      tx.update(memberDoc, {'status': MemberStatus.active.name});
      tx.update(_db.collection('organizations').doc(orgId), {
        'memberUids': FieldValue.arrayUnion([childUid]),
      });
      tx.update(_db.collection('users').doc(childUid), {
        'memberships': FieldValue.arrayUnion([membership.toMap()]),
      });
    });
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
        .where('guardianUid', isEqualTo: guardianUid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((s) => s.docs.map(OrgMember.fromFirestore).toList());
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

    final role = OrgRole.values.byName(snap.data()!['role'] as String);
    final membership = OrgMembership(orgId: orgId, role: role);

    await _db.runTransaction((tx) async {
      tx.delete(memberDoc);
      tx.update(_db.collection('organizations').doc(orgId), {
        'memberUids': FieldValue.arrayRemove([targetUid]),
      });
      tx.update(_db.collection('users').doc(targetUid), {
        'memberships': FieldValue.arrayRemove([membership.toMap()]),
      });
    });
  }

  Future<void> updateMemberRole(String orgId, String targetUid, OrgRole newRole) async {
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

    await _db.runTransaction((tx) async {
      tx.update(memberDoc, {'role': newRole.name});
      tx.update(_db.collection('users').doc(targetUid), {
        'memberships': FieldValue.arrayRemove([oldMembership.toMap()]),
      });
      tx.update(_db.collection('users').doc(targetUid), {
        'memberships': FieldValue.arrayUnion([newMembership.toMap()]),
      });
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

  Stream<List<OrgMember>> watchMembers(String orgId) {
    return _db
        .collection('organizations')
        .doc(orgId)
        .collection('members')
        .snapshots()
        .map((snap) => snap.docs.map(OrgMember.fromFirestore).toList());
  }
}
