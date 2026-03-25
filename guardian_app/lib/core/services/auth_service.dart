import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/app_user.dart';
import 'notification_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<AppUser> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) throw Exception('Sign-in abgebrochen');

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
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
      await NotificationService().initialize();
      return newUser;
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

    await NotificationService().initialize();
    return AppUser.fromFirestore(doc);
  }

  Future<AppUser> signInWithEmailPassword(String email, String password) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    return _ensureUserDocument(credential.user!);
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
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
