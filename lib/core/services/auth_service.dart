import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import '../config/env_config.dart';
import '../models/models.dart';

/// Outcome of an auth call, carrying a human-readable reason on failure.
class AuthResult {
  final User? user;
  final String? error;

  const AuthResult._({this.user, this.error});

  factory AuthResult.success(User? user) => AuthResult._(user: user);

  /// Every auth failure in this file funnels through here, so this is the one
  /// place that can guarantee a failure is visible in `flutter run` output.
  /// Without it a rejected sign-in shows a message on screen and leaves no
  /// trace in the logs, which makes it near-impossible to diagnose remotely.
  factory AuthResult.failure(String error) {
    debugPrint('[auth] FAILURE: $error');
    return AuthResult._(error: error);
  }

  bool get isSuccess => error == null;
}

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Current user stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Current user
  User? get currentUser => _auth.currentUser;

  // Check if logged in
  bool get isSignedIn => _auth.currentUser != null;

  // ── Google Sign-In (v7 API) ────────────────────────────

  /// google_sign_in 7.x requires initialize() to be awaited exactly once
  /// before any other call on the singleton. Skipping it makes authenticate()
  /// throw, which previously surfaced as a silent "cancelled".
  static Future<void>? _googleInit;

  /// Mobile only — web never reaches this, it uses Firebase's popup instead.
  Future<void> _ensureGoogleReady() {
    return _googleInit ??= GoogleSignIn.instance.initialize(
      // Android needs the web client id as serverClientId so the idToken is
      // issued for Firebase. iOS reads its own from GoogleService-Info.plist.
      serverClientId: EnvConfig.instance.googleServerClientId,
    );
  }

  Future<AuthResult> signInWithGoogle() async {
    // google_sign_in's authenticate() throws UnimplementedError on web — the
    // web plugin only offers its own rendered button. Firebase's popup gives
    // the same result while keeping our own button, as it does for Apple.
    if (kIsWeb) {
      try {
        final provider = GoogleAuthProvider()
          ..addScope('email')
          ..addScope('profile');
        final result = await _auth.signInWithPopup(provider);
        return AuthResult.success(result.user);
      } on FirebaseAuthException catch (e) {
        debugPrint('[auth] popup FirebaseAuthException code=${e.code} '
            'message=${e.message}');
        return AuthResult.failure(_popupErrorMessage(e));
      } catch (e) {
        debugPrint('[auth] popup unexpected ${e.runtimeType}: $e');
        return AuthResult.failure('Google sign-in did not complete: $e');
      }
    }

    try {
      await _ensureGoogleReady();
      final GoogleSignInAccount googleUser =
          await GoogleSignIn.instance.authenticate();

      final GoogleSignInAuthentication googleAuth = googleUser.authentication;
      final idToken = googleAuth.idToken;
      if (idToken == null) {
        return AuthResult.failure(
          'Google did not return an ID token. Check that the OAuth web client '
          'id for this environment is correct.',
        );
      }

      final credential = GoogleAuthProvider.credential(idToken: idToken);
      final result = await _auth.signInWithCredential(credential);
      return AuthResult.success(result.user);
    } on GoogleSignInException catch (e) {
      debugPrint('[auth] GoogleSignInException code=${e.code} '
          'description=${e.description} details=${e.details}');
      return AuthResult.failure(_googleErrorMessage(e));
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(e.message ?? 'Google sign-in did not complete.');
    } catch (e) {
      return AuthResult.failure('Google sign-in did not complete: $e');
    }
  }

  /// Browser popup failures, which are their own category on web.
  String _popupErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'popup-closed-by-user':
      case 'cancelled-popup-request':
      case 'user-cancelled':
        return 'Google sign-in was cancelled.';
      case 'popup-blocked':
        return 'Your browser blocked the sign-in popup. Allow popups for this '
            'site and try again.';
      case 'unauthorized-domain':
        return 'This address is not an authorized domain for Google sign-in. '
            'Add it in Firebase Console → Authentication → Settings.';
      case 'operation-not-allowed':
        return 'Google sign-in is turned off for this project.';
      default:
        return e.message ?? 'Google sign-in did not complete.';
    }
  }

  String _googleErrorMessage(GoogleSignInException e) {
    switch (e.code) {
      case GoogleSignInExceptionCode.canceled:
														return 'Google sign-in was cancelled.';
      case GoogleSignInExceptionCode.interrupted:
        return 'Google sign-in was interrupted. Please try again.';
      case GoogleSignInExceptionCode.clientConfigurationError:
        return 'Google sign-in is misconfigured for this build (check the '
            'SHA-1 fingerprint and OAuth client id).';
      case GoogleSignInExceptionCode.providerConfigurationError:
        return 'Google Play services is unavailable or out of date on this '
            'device.';
      case GoogleSignInExceptionCode.uiUnavailable:
        return 'No Google account is available on this device. Add one in '
            'Settings, then try again.';
      case GoogleSignInExceptionCode.userMismatch:
        return 'That Google account did not match the one expected.';
      case GoogleSignInExceptionCode.unknownError:
        return e.description ?? 'Google sign-in did not complete.';
    }
  }

  // ── Apple Sign-In ──────────────────────────────────────

  /// Apple returns name and email only on the very first authorization, so
  /// both scopes are requested up front.
  AppleAuthProvider get _appleProvider => AppleAuthProvider()
    ..addScope('email')
    ..addScope('name');

  /// Web uses a popup; iOS goes native and Android falls back to a Custom Tab,
  /// both of which signInWithProvider handles.
  Future<AuthResult> signInWithApple() async {
    try {
      final provider = _appleProvider;
      final credential = kIsWeb
          ? await _auth.signInWithPopup(provider)
          : await _auth.signInWithProvider(provider);
      return AuthResult.success(credential.user);
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(_appleErrorMessage(e));
    } catch (e) {
      return AuthResult.failure('Apple sign-in did not complete.');
    }
  }

  /// Attaches an Apple credential to the current guest account, preserving the
  /// uid — and so everything the guest has already posted.
  Future<AuthResult> linkGuestWithApple() async {
    final user = _auth.currentUser;
    if (user == null) {
      return AuthResult.failure('You are not signed in.');
    }
    if (!user.isAnonymous) {
      return AuthResult.failure('This account is already registered.');
    }

    try {
      final provider = _appleProvider;
      if (kIsWeb) {
        await user.linkWithPopup(provider);
      } else {
        await user.linkWithProvider(provider);
      }
      await _auth.currentUser?.reload();
      return AuthResult.success(_auth.currentUser);
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(_linkErrorMessage(e));
    } catch (e) {
      return AuthResult.failure('Could not create your account. Try again.');
    }
  }

  String _appleErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'operation-not-allowed':
        return 'Apple sign-in is turned off for this project. Enable the Apple '
            'provider in Firebase Console → Authentication → Sign-in method.';
      case 'canceled':
      case 'user-cancelled':
      case 'web-context-canceled':
      case 'popup-closed-by-user':
        return 'Apple sign-in was cancelled.';
      case 'account-exists-with-different-credential':
        return 'An account with that email already exists using a different '
            'sign-in method. Sign in with that method instead.';
      case 'invalid-credential':
        return 'Apple could not verify that sign-in. Please try again.';
      default:
        return e.message ?? 'Apple sign-in did not complete.';
    }
  }

  // ── Email/Password Sign-In ─────────────────────────────

  Future<AuthResult> signInWithEmail(String email, String password) async {
    try {
      final result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return AuthResult.success(result.user);
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(_emailSignInErrorMessage(e));
    }
  }

  /// Firebase deliberately collapses "no such user", "wrong password" and
  /// "this account has no password at all" into one `invalid-credential`
  /// code, so that an attacker cannot probe which emails are registered.
  /// That privacy win costs us diagnosability, so the message below names
  /// the case people actually hit: an account created through Google or
  /// Apple has no password to check, and every password will be rejected.
  String _emailSignInErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'That email and password did not match an account. If you '
            'first signed up with Google or Apple, use that button instead '
            '\u2014 those accounts have no password until you add one with '
            'Forgot Password.';
      case 'invalid-email':
        return 'That email address is not formatted correctly.';
      case 'user-disabled':
        return 'That account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Wait a moment and try again.';
      case 'network-request-failed':
        return 'No network connection. Check your connection and try again.';
      case 'operation-not-allowed':
        return 'Email and password sign-in is turned off for this project. '
            'Enable it in Firebase Console \u2192 Authentication \u2192 '
            'Sign-in method.';
      default:
        return e.message ?? 'Sign-in did not complete.';
    }
  }

  Future<AuthResult> createAccountWithEmail(
      String email, String password) async {
    try {
      final result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return AuthResult.success(result.user);
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(_createAccountErrorMessage(e));
    }
  }

  String _createAccountErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'An account already exists for that email. Sign in instead, '
            'or use the button for the method you signed up with.';
      case 'weak-password':
        return 'That password is too weak. Use at least 6 characters.';
      case 'invalid-email':
        return 'That email address is not formatted correctly.';
      case 'operation-not-allowed':
        return 'Email and password sign-up is turned off for this project. '
            'Enable it in Firebase Console \u2192 Authentication \u2192 '
            'Sign-in method.';
      case 'network-request-failed':
        return 'No network connection. Check your connection and try again.';
      default:
        return e.message ?? 'Account creation did not complete.';
    }
  }

  // ── Guest (Anonymous) Sign-In ──────────────────────────

  /// True while the session is an anonymous guest account.
  bool get isGuest => _auth.currentUser?.isAnonymous ?? false;

  /// Emits on sign-in, sign-out *and* profile/link changes.
  ///
  /// [authStateChanges] does not fire when a guest links a credential — the
  /// uid is unchanged — so anything that reacts to guest-vs-registered must
  /// listen here instead.
  Stream<User?> get userChanges => _auth.userChanges();

  Future<AuthResult> signInAsGuest() async {
    try {
      final credential = await _auth.signInAnonymously();
      return AuthResult.success(credential.user);
    } on FirebaseAuthException catch (e) {
      // Firebase reports a disabled Anonymous provider as
      // admin-restricted-operation, not operation-not-allowed.
      if (e.code == 'operation-not-allowed' ||
          e.code == 'admin-restricted-operation') {
        return AuthResult.failure(
          'Guest sign-in is turned off for this project. Enable the Anonymous '
          'provider in Firebase Console → Authentication → Sign-in method.',
        );
      }
      return AuthResult.failure(e.message ?? 'Could not start a guest session.');
    } catch (e) {
      return AuthResult.failure('Could not start a guest session.');
    }
  }

  // ── Upgrading a Guest to a Registered Account ──────────

  /// Attaches an email/password credential to the current guest account.
  ///
  /// Linking keeps the same uid, so everything the guest already posted stays
  /// attributed to them. Creating a fresh account instead would orphan it.
  Future<AuthResult> linkGuestWithEmail(String email, String password) async {
    final user = _auth.currentUser;
    if (user == null) {
      return AuthResult.failure('You are not signed in.');
    }
    if (!user.isAnonymous) {
      return AuthResult.failure('This account is already registered.');
    }

    try {
      final credential = EmailAuthProvider.credential(
        email: email,
        password: password,
      );
      final result = await user.linkWithCredential(credential);
      await result.user?.updateDisplayName(email.split('@').first);
      await _auth.currentUser?.reload();
      return AuthResult.success(_auth.currentUser);
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(_linkErrorMessage(e));
    } catch (e) {
      return AuthResult.failure('Could not create your account. Try again.');
    }
  }

  /// Attaches a Google credential to the current guest account.
  Future<AuthResult> linkGuestWithGoogle() async {
    final user = _auth.currentUser;
    if (user == null) {
      return AuthResult.failure('You are not signed in.');
    }
    if (!user.isAnonymous) {
      return AuthResult.failure('This account is already registered.');
    }

    if (kIsWeb) {
      try {
        final provider = GoogleAuthProvider()
          ..addScope('email')
          ..addScope('profile');
        await user.linkWithPopup(provider);
        await _auth.currentUser?.reload();
        return AuthResult.success(_auth.currentUser);
      } on FirebaseAuthException catch (e) {
        return AuthResult.failure(
          e.code.startsWith('popup') || e.code.contains('cancelled')
              ? _popupErrorMessage(e)
              : _linkErrorMessage(e),
        );
      } catch (e) {
        return AuthResult.failure('Could not create your account: $e');
      }
    }

    try {
      await _ensureGoogleReady();
      final googleUser = await GoogleSignIn.instance.authenticate();
      final googleAuth = googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );
      await user.linkWithCredential(credential);
      await _auth.currentUser?.reload();
      return AuthResult.success(_auth.currentUser);
    } on GoogleSignInException catch (e) {
      debugPrint('[auth] GoogleSignInException code=${e.code} '
          'description=${e.description} details=${e.details}');
      return AuthResult.failure(_googleErrorMessage(e));
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(_linkErrorMessage(e));
    } catch (e) {
      return AuthResult.failure('Could not create your account. Try again.');
    }
  }

  String _linkErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
      case 'credential-already-in-use':
      case 'account-exists-with-different-credential':
        return 'That account already exists. Sign out and sign in to it '
            'directly — activity from this guest session will stay behind.';
      case 'weak-password':
        return 'Please choose a password of at least 6 characters.';
      case 'invalid-email':
        return 'That email address does not look right.';
      case 'provider-already-linked':
        return 'This account is already registered.';
      case 'requires-recent-login':
        return 'Please sign in again before registering.';
      case 'canceled':
      case 'user-cancelled':
      case 'web-context-canceled':
      case 'popup-closed-by-user':
        return 'Sign-in was cancelled.';
      default:
        return e.message ?? 'Could not create your account. Try again.';
    }
  }

  // ── Sign Out ───────────────────────────────────────────

  Future<void> signOut() async {
    await _auth.signOut();
  }

  // ── Password Reset ────────────────────────────────────

  Future<String?> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return null; // success
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Failed to send reset email.';
    } catch (e) {
      return 'Failed to send reset email. Please try again.';
    }
  }

  // ── Helper: Get user display info ──────────────────────

  String get userName {
    final user = currentUser;
    if (user == null) return 'User';
    if (user.isAnonymous) return UserProfile.guestName(user.uid);
    return user.displayName ?? user.email?.split('@').first ?? 'User';
  }

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
