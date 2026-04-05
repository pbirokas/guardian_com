import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/app_user.dart';
import 'notification_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

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
    try {
      final callable = FirebaseFunctions.instance
          .httpsCallable('processMyInvitations');
      await callable.call();
    } catch (_) {
      // Einladungsverarbeitung ist nicht kritisch – Fehler still ignorieren
    }
  }

  Future<void> signOut() async {
    await GoogleSignIn.instance.initialize(
      serverClientId:
          '689565503451-msp7j89869cr9ojvc2uhaph0ordri5vr.apps.googleusercontent.com',
    );
    await GoogleSignIn.instance.signOut();
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
