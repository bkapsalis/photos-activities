import 'dart:async';

import 'package:flutter/material.dart';

import '../services/crash_reporting.dart';
import '../theme/app_colors.dart';

/// Shows live data from a stream: a spinner until it first arrives, then
/// [builder], or an explanation with a retry if it cannot be loaded.
///
/// The stream is created once, not on every build. A StreamBuilder handed a
/// fresh Firestore stream each build starts over every time its parent
/// rebuilds (opening the keyboard is enough), flashing a spinner and
/// listening again. It is only replaced when [identity] changes, such as
/// another photo or category, or when the reader asks to retry.
///
/// A failure is shown as a failure. Shown as an empty list it would read as
/// "nothing here", which is wrong and impossible to diagnose.
class LiveData<T> extends StatefulWidget {
  /// Creates the stream to show.
  final Stream<T> Function() stream;

  /// What the stream is for; a change here means listening to a new one.
  final Object? identity;

  final Widget Function(BuildContext context, T data) builder;

  /// What failed, in the reader's terms, e.g. "Comments could not be loaded."
  final String errorMessage;

  /// Shown in place of the full error view where space is tight.
  final Widget Function(BuildContext context, VoidCallback retry)? errorBuilder;

  const LiveData({
    super.key,
    required this.stream,
    required this.builder,
    required this.errorMessage,
    this.identity,
    this.errorBuilder,
  });

  @override
  State<LiveData<T>> createState() => _LiveDataState<T>();
}

class _LiveDataState<T> extends State<LiveData<T>> {
  late Stream<T> _stream = _listen();

  Stream<T> _listen() => widget.stream().transform(
    StreamTransformer.fromHandlers(
      handleError: (error, stack, sink) {
        CrashReporting.recordError(error, stack, reason: widget.errorMessage);
        sink.addError(error, stack);
      },
    ),
  );

  void _retry() => setState(() => _stream = _listen());

  @override
  void didUpdateWidget(covariant LiveData<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity) _stream = _listen();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<T>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return widget.errorBuilder?.call(context, _retry) ??
              LoadErrorView(message: widget.errorMessage, onRetry: _retry);
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return widget.builder(context, snapshot.requireData);
      },
    );
  }
}

/// Says that something could not be loaded, and offers to try again.
class LoadErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const LoadErrorView({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            const Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
