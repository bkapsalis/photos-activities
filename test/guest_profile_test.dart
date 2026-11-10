import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter_test/flutter_test.dart';

import 'package:bills_bay_area/core/models/models.dart';

/// Minimal stand-in for a Firebase user; noSuchMethod covers the rest of the
/// interface, which UserProfile never touches.
class _FakeUser implements auth.User {
  @override
  final String uid;
  @override
  final bool isAnonymous;
  @override
  final String? displayName;
  @override
  final String? email;

  _FakeUser({
    required this.uid,
    this.isAnonymous = false,
    this.displayName,
    this.email,
  });

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group('UserProfile.guestName', () {
    test('tags a guest with the first four characters of their uid', () {
      expect(UserProfile.guestName('4f2a9c01'), 'Guest 4f2a');
    });

    test('keeps two guests apart', () {
      expect(
        UserProfile.guestName('aaaa1111'),
        isNot(UserProfile.guestName('bbbb2222')),
      );
    });

    test('tolerates a uid shorter than the suffix', () {
      expect(UserProfile.guestName('ab'), 'Guest ab');
      expect(UserProfile.guestName(''), 'Guest ');
    });
  });

  group('UserProfile.fromFirebaseUser', () {
    test('marks an anonymous user as a guest', () {
      final profile = UserProfile.fromFirebaseUser(
        _FakeUser(uid: '4f2a9c01', isAnonymous: true),
      );

      expect(profile.isGuest, isTrue);
      expect(profile.name, 'Guest 4f2a');
      expect(profile.initials, 'G');
      expect(profile.role, 'Guest');
      expect(profile.id, '4f2a9c01');
    });

    test('a registered user is not a guest', () {
      final profile = UserProfile.fromFirebaseUser(
        _FakeUser(
          uid: 'abc123',
          displayName: 'Maria Kelly',
          email: 'maria@example.com',
        ),
      );

      expect(profile.isGuest, isFalse);
      expect(profile.name, 'Maria Kelly');
      expect(profile.initials, 'MK');
      expect(profile.role, 'Contributor');
    });

    test('falls back to the email handle when there is no display name', () {
      final profile = UserProfile.fromFirebaseUser(
        _FakeUser(uid: 'abc123', email: 'billpics234@example.com'),
      );

      expect(profile.name, 'billpics234');
      expect(profile.isGuest, isFalse);
    });

    test('keeps the avatar colour stable across calls for one uid', () {
      final first = UserProfile.fromFirebaseUser(
        _FakeUser(uid: 'stable-uid', isAnonymous: true),
      );
      final second = UserProfile.fromFirebaseUser(
        _FakeUser(uid: 'stable-uid', isAnonymous: true),
      );

      expect(first.avatarColor, second.avatarColor);
    });

    test('a guest keeps their identity after registering', () {
      // Linking preserves the uid, so the profile that replaces the guest is
      // the same account, now named and no longer flagged as a guest.
      const uid = '4f2a9c01';
      final guest = UserProfile.fromFirebaseUser(
        _FakeUser(uid: uid, isAnonymous: true),
      );
      final registered = UserProfile.fromFirebaseUser(
        _FakeUser(uid: uid, displayName: 'Bill K', email: 'bill@example.com'),
      );

      expect(registered.id, guest.id);
      expect(guest.isGuest, isTrue);
      expect(registered.isGuest, isFalse);
      expect(registered.name, 'Bill K');
    });
  });
}
