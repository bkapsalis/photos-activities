import 'package:flutter/material.dart';

import '../services/crash_reporting.dart';

/// Runs something the reader asked for (posting, editing, deleting) and
/// tells them if it did not happen.
///
/// Returns whether it succeeded. A failure is shown as [failureMessage] and
/// reported to Crashlytics as non-fatal: the app carries on, so it is not a
/// crash, but it is something that should not have happened. Left uncaught,
/// the same error would reach the zone handler and be counted as a fatal
/// crash, while the reader saw nothing at all.
Future<bool> runUserAction(
  BuildContext context,
  Future<void> Function() action, {
  required String failureMessage,
}) async {
  // Looked up before the await: the widget may be gone by the time it fails.
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await action();
    return true;
  } catch (error, stack) {
    CrashReporting.recordError(error, stack, reason: failureMessage);
    messenger?.showSnackBar(SnackBar(content: Text(failureMessage)));
    return false;
  }
}
