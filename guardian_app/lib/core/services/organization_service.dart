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

  Future<void> inviteMember(String orgId, String email, OrgRole role) async {
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

    final membership = OrgMembership(orgId: orgId, role: role);

    await _db.runTransaction((tx) async {
      tx.set(memberDoc, OrgMember(
        uid: targetUid,
        displayName: userData['displayName'] as String,
        email: userData['email'] as String,
        photoUrl: userData['photoUrl'] as String?,
        role: role,
        joinedAt: DateTime.now(),
      ).toFirestore());
      // memberUids Array im Org-Dokument synchron halten
      tx.update(_db.collection('organizations').doc(orgId), {
        'memberUids': FieldValue.arrayUnion([targetUid]),
      });
      tx.update(_db.collection('users').doc(targetUid), {
        'memberships': FieldValue.arrayUnion([membership.toMap()]),
      });
    });
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
