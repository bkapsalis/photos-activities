import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Current user stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Current user
  User? get currentUser => _auth.currentUser;

  // Check if logged in
  bool get isSignedIn => _auth.currentUser != null;

  // ── Google Sign-In (v7 API) ────────────────────────────

  Future<UserCredential?> signInWithGoogle() async {
    try {
      // google_sign_in v7 uses the singleton instance + authenticate()
      final googleSignIn = GoogleSignIn.instance;
      final GoogleSignInAccount googleUser = await googleSignIn.authenticate();

      // Get the ID token for Firebase credential
      final GoogleSignInAuthentication googleAuth =
          googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      return await _auth.signInWithCredential(credential);
    } on GoogleSignInException {
      // User cancelled the sign-in flow
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('Error signing in with Google: $e');
      return null;
    }
  }

  // ── Email/Password Sign-In ─────────────────────────────

  Future<UserCredential?> signInWithEmail(String email, String password) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      // ignore: avoid_print
      print('Error signing in with email: ${e.message}');
      return null;
    }
  }

  Future<UserCredential?> createAccountWithEmail(
      String email, String password) async {
    try {
      return await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      // ignore: avoid_print
      print('Error creating account: ${e.message}');
      return null;
    }
  }

  // ── Sign Out ───────────────────────────────────────────

  Future<void> signOut() async {
    await _auth.signOut();
  }

  // ── Helper: Get user display info ──────────────────────

  String get userName => currentUser?.displayName ?? 'User';

  String get userInitials {
    final name = userName;
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length.clamp(0, 2)).toUpperCase();
  }

  String? get userPhotoUrl => currentUser?.photoURL;
  String? get userEmail => currentUser?.email;
}
