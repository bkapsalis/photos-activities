import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';

/// Custom traces for operations Firebase's automatic instrumentation can't
/// see well on its own — notably Firestore, which talks gRPC rather than the
/// HTTP stack Performance Monitoring hooks into automatically. App start,
/// screen rendering and most network calls are already traced with no code
/// here; this is only for app-specific latency worth watching separately.
///
/// Each Firebase project (dev, staging, prod) reports to its own Performance
/// dashboard, same as Analytics and Crashlytics, so dev runs never skew the
/// real numbers.
///
/// Tracing must never break the operation it measures: start/stop failures
/// are swallowed and logged, never thrown.
class PerformanceService {
  PerformanceService._();

  /// Wraps [action] in a named trace. Returns [action]'s result (or lets its
  /// error propagate) regardless of whether tracing itself succeeds.
  static Future<T> trace<T>(String name, Future<T> Function() action) async {
    Trace? trace;
    try {
      trace = FirebasePerformance.instance.newTrace(name);
      await trace.start();
    } catch (e) {
      debugPrint('[performance] $name failed to start: $e');
      trace = null;
    }

    try {
      return await action();
    } finally {
      try {
        await trace?.stop();
      } catch (e) {
        debugPrint('[performance] $name failed to stop: $e');
      }
    }
  }
}
