import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../config/env_config.dart';
import '../utils/permissions.dart';

/// Sends crashes and errors to Firebase Crashlytics.
///
/// Android and iOS only: Crashlytics has no web SDK, so on web every call is
/// a no-op and errors stay in the browser console.
class CrashReporting {
  CrashReporting._();

  static bool get supported => !kIsWeb;

  /// Routes uncaught errors to Crashlytics. Call once, after
  /// Firebase.initializeApp and EnvConfig.init.
  static Future<void> install() async {
    if (!supported) return;
    final crashlytics = FirebaseCrashlytics.instance;

    // Every report says which environment it came from, so a dev crash is
    // never mistaken for one users hit.
    await crashlytics.setCustomKey(
      'environment',
      EnvConfig.instance.environment.name,
    );

    // Framework errors (a layout overflow, a bad widget state) are reported
    // non-fatal: the app usually carries on, and calling each one a crash
    // would bury real ones. They still print to the console as before.
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      crashlytics.recordFlutterError(details);
    };

    // Anything that escapes to the top of an async zone is a real crash.
    PlatformDispatcher.instance.onError = (error, stack) {
      crashlytics.recordError(error, stack, fatal: true);
      return true;
    };

    // The uid lets the console count how many people a crash affects. It is
    // an opaque Firebase id, not a name or email.
    FirebaseAuth.instance.authStateChanges().listen((user) {
      crashlytics.setUserIdentifier(user?.uid ?? '');
    });
  }

  /// Records an error that was caught and handled but should not have
  /// happened.
  ///
  /// Also prints it, so it shows in the console during development and on
  /// web, which Crashlytics does not cover. Reporting never throws: it runs
  /// inside error handlers, and in tests Firebase is not set up at all.
  static void recordError(Object error, StackTrace? stack, {String? reason}) {
    debugPrint('[error] ${reason ?? 'unexpected'}: $error');
    if (!supported) return;
    try {
      unawaited(
        FirebaseCrashlytics.instance
            .recordError(error, stack, reason: reason)
            .catchError((_) {}),
      );
    } catch (_) {
      // Firebase not initialised, as in tests.
    }
  }

  /// Whether [testCrash] is offered: to anyone in dev, and to a moderator in
  /// staging, to check that environment's reports arrive before a release.
  /// Never in prod, where every crash in the console should be a real one.
  static bool offersTestCrash(Environment environment, {required bool admin}) =>
      switch (environment) {
        Environment.dev => true,
        Environment.staging => admin,
        Environment.prod => false,
      };

  /// Deliberately crashes the app, to check reports arrive. The report is
  /// sent the next time the app starts, and its Logs tab says it was a test.
  static Future<void> testCrash() async {
    if (!supported ||
        !offersTestCrash(EnvConfig.instance.environment, admin: isAdmin())) {
      return;
    }
    final crashlytics = FirebaseCrashlytics.instance;
    await crashlytics.log('Test crash sent from the account menu');
    crashlytics.crash();
  }
}
