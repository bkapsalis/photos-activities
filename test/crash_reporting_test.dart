import 'package:bills_bay_area/core/config/env_config.dart';
import 'package:bills_bay_area/core/services/crash_reporting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('offersTestCrash', () {
    test('dev offers it to everyone', () {
      expect(
        CrashReporting.offersTestCrash(Environment.dev, admin: false),
        isTrue,
      );
      expect(
        CrashReporting.offersTestCrash(Environment.dev, admin: true),
        isTrue,
      );
    });

    test('staging offers it to moderators only', () {
      expect(
        CrashReporting.offersTestCrash(Environment.staging, admin: true),
        isTrue,
      );
      expect(
        CrashReporting.offersTestCrash(Environment.staging, admin: false),
        isFalse,
      );
    });

    test('prod never offers it, not even to a moderator', () {
      expect(
        CrashReporting.offersTestCrash(Environment.prod, admin: true),
        isFalse,
      );
      expect(
        CrashReporting.offersTestCrash(Environment.prod, admin: false),
        isFalse,
      );
    });
  });
}
