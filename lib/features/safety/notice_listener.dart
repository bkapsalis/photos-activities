import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/services/crash_reporting.dart';
import '../../core/services/safety_service.dart';
import '../../core/theme/app_colors.dart';

/// Shows the reader each notice about a post of theirs, once: taken down by
/// the content filter ("Inappropriate content detected and blocked"), or
/// put back by a moderator. Wraps the signed-in app.
class NoticeListener extends StatefulWidget {
  final Widget child;

  const NoticeListener({super.key, required this.child});

  @override
  State<NoticeListener> createState() => _NoticeListenerState();
}

class _NoticeListenerState extends State<NoticeListener> {
  StreamSubscription<List<PostNotice>>? _subscription;
  final _queue = <PostNotice>[];
  final _queued = <String>{};
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    _subscription = SafetyService().unseenNotices().listen(
      (notices) {
        for (final notice in notices) {
          if (_queued.add(notice.id)) _queue.add(notice);
        }
        _showNext();
      },
      onError: (Object error, StackTrace stack) => CrashReporting.recordError(
        error,
        stack,
        reason: 'listening for notices',
      ),
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _showNext() async {
    if (_showing || _queue.isEmpty || !mounted) return;
    _showing = true;
    final notice = _queue.removeAt(0);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          notice.restored ? Icons.check_circle_outline : Icons.block,
          color: notice.restored ? AppColors.primary : AppColors.heartRed,
        ),
        title: Text(notice.title),
        content: Text(notice.message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    try {
      await SafetyService().markSeen(notice.id);
    } catch (error, stack) {
      // Shown again next time, which is better than never.
      CrashReporting.recordError(error, stack, reason: 'marking a notice seen');
    }
    _showing = false;
    _showNext();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
