import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../config/env_config.dart';

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
  static void recordError(Object error, StackTrace? stack, {String? reason}) {
    if (!supported) return;
    unawaited(
      FirebaseCrashlytics.instance.recordError(error, stack, reason: reason),
    );
  }

  /// Deliberately crashes the app, to check reports arrive. Dev only; the
  /// report is sent the next time the app starts.
  static void testCrash() {
    if (!supported || !EnvConfig.instance.isDev) return;
    FirebaseCrashlytics.instance.crash();
  }
}
