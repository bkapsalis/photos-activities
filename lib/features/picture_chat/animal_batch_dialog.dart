import 'package:flutter/material.dart';

import '../../core/services/ai_service.dart';
import '../../core/services/crash_reporting.dart';
import '../../core/theme/app_colors.dart';
import 'ai_widgets.dart';

enum _Stage { confirm, running, finished, failed }

/// A moderator's "Check all photos for animals": posts the AI's animal
/// comments on every photo that does not have them yet, a batch at a time,
/// with progress and a way to stop. Photos already done are skipped, so it
/// can be run again whenever new photos have come in.
class AnimalBatchDialog extends StatefulWidget {
  const AnimalBatchDialog({super.key});

  /// Not dismissed by a tap outside while running: the run would carry on
  /// unseen.
  static Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AnimalBatchDialog(),
  );

  @override
  State<AnimalBatchDialog> createState() => _AnimalBatchDialogState();
}

class _AnimalBatchDialogState extends State<AnimalBatchDialog> {
  _Stage _stage = _Stage.confirm;
  bool _stopRequested = false;
  int _checked = 0;
  int _added = 0;
  // Null until the first batch says how many are waiting.
  int? _remaining;
  int _failedTotal = 0;
  String _error = '';

  Future<void> _run() async {
    setState(() => _stage = _Stage.running);
    try {
      while (true) {
        final batch = await AiService().describeNextBatch();
        if (!mounted) return;
        setState(() {
          _checked += batch.checked;
          _added += batch.commentsAdded;
          _remaining = batch.remaining;
          _failedTotal = batch.failedTotal;
        });
        if (batch.isFinished || _stopRequested) break;
      }
      setState(() => _stage = _Stage.finished);
    } catch (error, stack) {
      CrashReporting.recordError(
        error,
        stack,
        reason: 'checking all photos for animals',
      );
      if (!mounted) return;
      setState(() {
        _stage = _Stage.failed;
        _error = aiErrorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(switch (_stage) {
        _Stage.confirm => 'Check all photos for animals?',
        _Stage.running => 'Checking photos…',
        _Stage.finished => _stopRequested ? 'Stopped' : 'Done',
        _Stage.failed => 'The check stopped',
      }),
      content: SizedBox(width: 360, child: _content()),
      actions: switch (_stage) {
        _Stage.confirm => [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _run,
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Start'),
          ),
        ],
        _Stage.running => [
          TextButton(
            onPressed: _stopRequested
                ? null
                : () => setState(() => _stopRequested = true),
            child: Text(_stopRequested ? 'Stopping…' : 'Stop'),
          ),
        ],
        _Stage.finished || _Stage.failed => [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Close'),
          ),
        ],
      },
    );
  }

  Widget _content() {
    const secondary = TextStyle(color: AppColors.textSecondary);
    final remaining = _remaining;
    final progress = remaining == null || _checked + remaining == 0
        ? null
        : _checked / (_checked + remaining);
    final tally =
        'Checked ${_plural(_checked, 'photo')} and added '
        '${_plural(_added, 'AI comment')}.';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: switch (_stage) {
        _Stage.confirm => const [
          Text(
            'The AI looks at every photo whose animals have not been posted '
            'yet, and adds a comment for each animal it finds. Photos already '
            'done are skipped.',
          ),
          SizedBox(height: 12),
          Text(
            'It costs well under a cent per photo, and you can stop at any '
            'time.',
            style: secondary,
          ),
        ],
        _Stage.running => [
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 12),
          Text(tally),
          if (remaining != null && remaining > 0)
            Text('${_plural(remaining, 'photo')} to go.', style: secondary),
        ],
        _Stage.finished => [
          Text(tally),
          if (remaining != null && remaining > 0) ...[
            const SizedBox(height: 8),
            Text(
              '${_plural(remaining, 'photo')} still to go. Run it again to '
              'carry on.',
              style: secondary,
            ),
          ],
          if (_failedTotal > 0) ...[
            const SizedBox(height: 8),
            Text(
              '${_plural(_failedTotal, 'photo')} could not be checked. Open '
              'one and tap "More info about the animals" to try it again.',
              style: secondary,
            ),
          ],
        ],
        _Stage.failed => [
          Text(_error),
          const SizedBox(height: 8),
          Text(
            '$tally Those are kept; run it again to carry on.',
            style: secondary,
          ),
        ],
      },
    );
  }
}

String _plural(int count, String noun) =>
    '$count $noun${count == 1 ? '' : 's'}';
