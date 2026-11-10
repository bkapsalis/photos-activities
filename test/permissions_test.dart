import 'package:bills_bay_area/core/utils/permissions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeUser implements User {
  _FakeUser(this.uid, {this.email, this.emailVerified = false});

  @override
  final String uid;
  @override
  final String? email;
  @override
  final bool emailVerified;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final owner = _FakeUser('alice');
  final stranger = _FakeUser('bob');
  final admin = _FakeUser(
    'bill',
    email: 'bkapsalis@gmail.com',
    emailVerified: true,
  );

  group('canModify', () {
    test('the owner may', () => expect(canModify('alice', owner), isTrue));
    test('someone else may not', () {
      expect(canModify('alice', stranger), isFalse);
    });
    test('a moderator may modify anyone\'s', () {
      expect(canModify('alice', admin), isTrue);
    });
    test('an item with no recorded owner is not "owned" by anyone', () {
      expect(canModify('', _FakeUser('')), isFalse);
      expect(canModify('', admin), isTrue);
    });
  });

  group('isAdmin', () {
    test('a verified moderator email', () => expect(isAdmin(admin), isTrue));
    test('matches regardless of case', () {
      final shouted = _FakeUser(
        'bill',
        email: 'BKapsalis@Gmail.com',
        emailVerified: true,
      );
      expect(isAdmin(shouted), isTrue);
    });
    test('an unverified account with the same email is not', () {
      // Mirrors the rules: anyone can register a password account with this
      // address, but they cannot verify it.
      final lookalike = _FakeUser('mallory', email: 'bkapsalis@gmail.com');
      expect(isAdmin(lookalike), isFalse);
      expect(canModify('alice', lookalike), isFalse);
    });
    test('an ordinary or emailless account is not', () {
      expect(isAdmin(owner), isFalse);
      expect(
        isAdmin(_FakeUser('x', email: 'x@example.com', emailVerified: true)),
        isFalse,
      );
    });
  });

  group('canUpload', () {
    test('a moderator may, even while uploads are closed', () {
      expect(canUpload(uploadsOpen: false, user: admin), isTrue);
    });
    test('anyone else may not while uploads are closed', () {
      expect(canUpload(uploadsOpen: false, user: owner), isFalse);
    });
    test('an unverified lookalike of the moderator may not', () {
      final lookalike = _FakeUser('mallory', email: 'bkapsalis@gmail.com');
      expect(canUpload(uploadsOpen: false, user: lookalike), isFalse);
    });
    test('everyone may once uploads are open', () {
      expect(canUpload(uploadsOpen: true, user: owner), isTrue);
      expect(canUpload(uploadsOpen: true, user: admin), isTrue);
    });
  });
}
