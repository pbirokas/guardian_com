import 'dart:convert';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_user.dart';
import '../models/org_member.dart';
import 'notification_service.dart';

bool get _isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const _kPendingEmail = 'emailLinkPendingEmail';

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<AppUser> signInWithGoogle() async {
    await GoogleSignIn.instance.initialize(
      serverClientId:
          '689565503451-msp7j89869cr9ojvc2uhaph0ordri5vr.apps.googleusercontent.com',
    );
    final googleAccount = await GoogleSignIn.instance.authenticate();
    final googleAuth = googleAccount.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );

    final userCredential = await _auth.signInWithCredential(credential);
    final user = userCredential.user!;

    return _ensureUserDocument(user);
  }

  // ── E-Mail-Link (Passwordless) ─────────────────────────────────────────────

  // Firebase Web API Key (identisch mit android apiKey)
  static const _webApiKey = 'AIzaSyBtuspjIwhor6w_SwnHynY4AJrGCqvGWI4';

  /// Sendet einen Anmeldelink an die angegebene E-Mail-Adresse.
  Future<void> sendSignInLink(String email) async {
    if (_isDesktop) {
      // Firebase C++ SDK unterstützt sendSignInLinkToEmail nicht →
      // direkt über die Identity Toolkit REST API senden.
      final uri = Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode'
        '?key=$_webApiKey',
      );
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'requestType': 'EMAIL_SIGNIN',
          'email': email,
          'continueUrl':
              'https://guardian-app-b0f6c.firebaseapp.com/emailLogin',
          'canHandleCodeInApp': true,
        }),
      );
      if (response.statusCode != 200) {
        final body = jsonDecode(response.body);
        final message =
            body['error']?['message'] as String? ?? 'Unbekannter Fehler';
        throw Exception('E-Mail-Link senden fehlgeschlagen: $message');
      }
    } else {
      await _auth.sendSignInLinkToEmail(
        email: email,
        actionCodeSettings: ActionCodeSettings(
          url: 'https://guardian-app-b0f6c.firebaseapp.com/emailLogin',
          handleCodeInApp: true,
          androidPackageName: 'com.guardianapp.guardian_app',
          androidInstallApp: true,
          androidMinimumVersion: '21',
        ),
      );
    }

    // E-Mail lokal speichern — wird beim Öffnen des Links gebraucht
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPendingEmail, email.toLowerCase().trim());
  }

  /// Prüft ob ein Deep Link ein E-Mail-Login-Link ist und meldet an.
  Future<AppUser?> handleEmailLink(Uri link) async {
    final linkStr = link.toString();

    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString(_kPendingEmail);
    if (email == null || email.isEmpty) return null;

    if (_isDesktop) {
      return _handleEmailLinkViaRest(email, linkStr, prefs);
    }

    if (!_auth.isSignInWithEmailLink(linkStr)) return null;

    final userCredential = await _auth.signInWithEmailLink(
      email: email,
      emailLink: linkStr,
    );

    await prefs.remove(_kPendingEmail);
    return _ensureUserDocument(userCredential.user!);
  }

  /// Sign-in per E-Mail-Link auf Desktop (Windows/Linux).
  ///
  /// Da das Firebase C++ SDK signInWithEmailLink nicht unterstützt:
  /// 1. oobCode aus URL extrahieren
  /// 2. REST API: oobCode → idToken
  /// 3. Cloud Function: idToken → Custom Token
  /// 4. SDK: signInWithCustomToken → normaler Auth-Flow
  Future<AppUser?> _handleEmailLinkViaRest(
      String email, String linkStr, SharedPreferences prefs) async {
    final oobCode = Uri.parse(linkStr).queryParameters['oobCode'];
    if (oobCode == null || oobCode.isEmpty) {
      throw Exception(
          'Ungültiger Link — kein oobCode gefunden.\nBitte kopiere die vollständige URL aus dem Browser.');
    }

    // Schritt 1: oobCode → idToken via REST
    final signInResponse = await http.post(
      Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/accounts:signInWithEmailLink'
        '?key=$_webApiKey',
      ),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'oobCode': oobCode}),
    );

    if (signInResponse.statusCode != 200) {
      final errBody = jsonDecode(signInResponse.body) as Map<String, dynamic>;
      final message = errBody['error']?['message'] as String? ?? 'Fehler';
      throw Exception('Anmeldung fehlgeschlagen: $message');
    }

    final signInData = jsonDecode(signInResponse.body) as Map<String, dynamic>;
    final idToken = signInData['idToken'] as String?;
    if (idToken == null) throw Exception('Kein idToken erhalten.');

    // Schritt 2: idToken → Custom Token via Cloud Function
    final customTokenResponse = await http.post(
      Uri.parse(
        'https://us-central1-guardian-app-b0f6c.cloudfunctions.net/getCustomToken',
      ),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'idToken': idToken}),
    );

    if (customTokenResponse.statusCode != 200) {
      throw Exception('Custom Token Fehler: ${customTokenResponse.body}');
    }

    final customTokenData =
        jsonDecode(customTokenResponse.body) as Map<String, dynamic>;
    final customToken = customTokenData['customToken'] as String?;
    if (customToken == null) throw Exception('Kein Custom Token erhalten.');

    // Schritt 3: SDK-Login mit Custom Token
    final userCredential = await _auth.signInWithCustomToken(customToken);

    await prefs.remove(_kPendingEmail);
    return _ensureUserDocument(userCredential.user!);
  }

  /// Gibt die gespeicherte E-Mail zurück (für UI-Anzeige nach Link-Versand).
  Future<String?> getPendingEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kPendingEmail);
  }

  /// Stellt sicher dass ein Firestore-Dokument für den User existiert.
  /// Wird bei jedem Login aufgerufen, damit fehlende Dokumente nacherstellt werden.
  Future<AppUser> _ensureUserDocument(User user) async {
    final docRef = _db.collection('users').doc(user.uid);
    final doc = await docRef.get();

    if (!doc.exists) {
      final newUser = AppUser(
        uid: user.uid,
        email: user.email!.toLowerCase(),
        displayName: (user.displayName?.isNotEmpty == true)
            ? user.displayName!
            : user.email!,
        photoUrl: user.photoURL,
        memberships: [],
        createdAt: DateTime.now(),
      );
      await docRef.set(newUser.toFirestore());
      await _processPendingInvitations(user.uid, user.email!.toLowerCase());
      await NotificationService().initialize();
      // Aktualisiertes Dokument laden (Einladungen können isChild gesetzt haben)
      final updatedDoc = await docRef.get();
      return AppUser.fromFirestore(updatedDoc);
    }

    final data = doc.data() as Map<String, dynamic>;
    final updates = <String, dynamic>{};

    // E-Mail normalisieren
    final storedEmail = data['email'] as String? ?? '';
    if (storedEmail != storedEmail.toLowerCase()) {
      updates['email'] = storedEmail.toLowerCase();
    }

    // DisplayName auffüllen falls leer
    final storedName = data['displayName'] as String? ?? '';
    if (storedName.isEmpty) {
      updates['displayName'] = (user.displayName?.isNotEmpty == true)
          ? user.displayName!
          : user.email!;
    }

    if (updates.isNotEmpty) await docRef.update(updates);

    // Ausstehende Einladungen auch bei existierenden Usern prüfen
    await _processPendingInvitations(user.uid, user.email!.toLowerCase());
    await NotificationService().initialize();
    final updatedDoc = await docRef.get();
    return AppUser.fromFirestore(updatedDoc);
  }

  Future<void> _processPendingInvitations(String uid, String email) async {
    // Einladungs-IDs ermitteln: zuerst per Lookup-Dokument (schnell, keine
    // List-Query nötig), danach Fallback auf direkte Abfrage für ältere
    // Einladungen, die vor Einführung des Lookups erstellt wurden.
    final invitationIds = <String>[];

    try {
      final lookupDoc =
          await _db.collection('invitationLookup').doc(email).get();
      if (lookupDoc.exists) {
        final ids = (lookupDoc.data()
                as Map<String, dynamic>)['invitationIds'] as List? ??
            [];
        invitationIds.addAll(ids.cast<String>());
        // Lookup-Dokument bereinigen
        await lookupDoc.reference.delete().catchError((_) {});
      }
    } catch (_) {}

    // Fallback: direkte E-Mail-Abfrage für Einladungen ohne Lookup-Eintrag
    if (invitationIds.isEmpty) {
      try {
        final query = await _db
            .collection('invitations')
            .where('email', isEqualTo: email)
            .where('status', isEqualTo: 'pending')
            .get();
        invitationIds.addAll(query.docs.map((d) => d.id));
      } catch (_) {}
    }

    if (invitationIds.isEmpty) return;

    for (final inviteId in invitationIds) {
      try {
        final inviteDoc =
            await _db.collection('invitations').doc(inviteId).get();
        if (!inviteDoc.exists) continue;

        final data = inviteDoc.data() as Map<String, dynamic>;
        if (data['status'] != 'pending') continue;

        final orgId = data['orgId'] as String;
        final role = OrgRole.values.byName(data['role'] as String);
        final guardianUids = (data['guardianUids'] as List? ?? [])
            .map((e) => e as String)
            .toList();
        final isChild = role == OrgRole.child;

        final user = _auth.currentUser!;
        final displayName = (user.displayName?.isNotEmpty == true)
            ? user.displayName!
            : email;

        final memberRef = _db
            .collection('organizations')
            .doc(orgId)
            .collection('members')
            .doc(uid);

        final existing = await memberRef.get();
        if (existing.exists) {
          await inviteDoc.reference
              .update({'status': 'processed'})
              .catchError((_) {});
          continue;
        }

        final membership = OrgMembership(orgId: orgId, role: role);

        // Transaktion: kritische Schreiboperationen (Mitglied + Org + User)
        await _db.runTransaction((tx) async {
          tx.set(
            memberRef,
            OrgMember(
              uid: uid,
              displayName: displayName,
              email: email,
              role: role,
              joinedAt: DateTime.now(),
              guardianUids: isChild ? guardianUids : [],
              status: isChild ? MemberStatus.pending : MemberStatus.active,
            ).toFirestore(),
          );

          if (!isChild) {
            tx.update(_db.collection('organizations').doc(orgId), {
              'memberUids': FieldValue.arrayUnion([uid]),
            });
            tx.update(_db.collection('users').doc(uid), {
              'memberships': FieldValue.arrayUnion([membership.toMap()]),
            });
          } else {
            tx.update(_db.collection('users').doc(uid), {'isChild': true});
          }
        });

        // Einladung separat als verarbeitet markieren (Best-Effort)
        await inviteDoc.reference
            .update({'status': 'processed'})
            .catchError((_) {});
      } catch (_) {
        // Eine einzelne Einladung fehlgeschlagen – mit den anderen weitermachen
      }
    }

  }

  Future<void> signOut() async {
    // Google Sign-In abmelden (nur wenn Google-Provider verwendet wurde)
    try {
      await GoogleSignIn.instance.initialize(
        serverClientId:
            '689565503451-msp7j89869cr9ojvc2uhaph0ordri5vr.apps.googleusercontent.com',
      );
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
    await _auth.signOut();
  }

  Future<AppUser?> getCurrentAppUser() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    final doc = await _db.collection('users').doc(user.uid).get();
    if (!doc.exists) {
      return _ensureUserDocument(user);
    }
    return AppUser.fromFirestore(doc);
  }
}
