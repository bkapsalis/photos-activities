import 'package:firebase_auth/firebase_auth.dart';

/// Moderators: may edit or delete anyone's photos and comments and bulk-delete
/// a location tab.
///
/// Mirrors the list in firestore.rules and storage.rules, which are what
/// actually enforce it. The app checks only so it never offers an action the
/// server will refuse; keep all three lists in sync.
const adminEmails = {'bkapsalis@gmail.com'};

/// True for a moderator. Like the rules, it requires the email to be
/// verified: Google sign-in verifies it, while a password account someone
/// registers with the same address does not.
bool isAdmin([User? user]) {
  user ??= FirebaseAuth.instance.currentUser;
  final email = user?.email?.toLowerCase();
  return user != null &&
      user.emailVerified &&
      email != null &&
      adminEmails.contains(email);
}

/// Whether the signed-in user may edit or delete something owned by
/// [ownerId]: its owner, or a moderator.
bool canModify(String ownerId, [User? user]) {
  user ??= FirebaseAuth.instance.currentUser;
  if (user == null) return false;
  return (ownerId.isNotEmpty && user.uid == ownerId) || isAdmin(user);
}
