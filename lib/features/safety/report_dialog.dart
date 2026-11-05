import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../../core/services/safety_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/user_action.dart';

/// The "⋯" menu on someone else's photo, comment or chat message: report it,
/// or block whoever posted it.
class SafetyMenuButton extends StatelessWidget {
  final ReportTarget target;

  /// The button's look, to match where it sits.
  final Widget icon;

  /// No padding around [icon], for a row of text such as a comment's.
  final bool compact;

  const SafetyMenuButton({
    super.key,
    required this.target,
    required this.icon,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: icon,
      tooltip: 'Report or block',
      padding: compact ? EdgeInsets.zero : const EdgeInsets.all(8),
      constraints: compact ? const BoxConstraints() : null,
      onSelected: (value) {
        if (value == 'report') {
          ReportDialog.show(context, target);
        } else if (value == 'block') {
          confirmBlock(context, target.author);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'report',
          child: Row(
            children: [
              const Icon(Icons.flag_outlined, size: 18, color: Colors.red),
              const SizedBox(width: 8),
              Text(
                'Report ${target.noun}',
                style: const TextStyle(color: Colors.red),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'block',
          child: Row(
            children: [
              const Icon(Icons.block, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Block ${target.author.name}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Asks why a post is being reported, sends the report, and hides the post
/// from the reporter. Optionally blocks its author too.
class ReportDialog extends StatefulWidget {
  final ReportTarget target;

  const ReportDialog({super.key, required this.target});

  static Future<void> show(BuildContext context, ReportTarget target) =>
      showDialog<void>(
        context: context,
        builder: (_) => ReportDialog(target: target),
      );

  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  ReportReason? _reason;
  bool _alsoBlock = false;
  bool _sending = false;
  final _details = TextEditingController();

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final reason = _reason;
    if (reason == null) return;
    final target = widget.target;
    // Looked up before the awaits: the dialog closes before they finish.
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    final sent = await runUserAction(context, () async {
      await SafetyService().report(target, reason, details: _details.text);
      if (_alsoBlock) await SafetyService().block(target.author);
    }, failureMessage: 'Your report was not sent. Please try again.');
    if (!mounted) return;
    if (!sent) {
      setState(() => _sending = false);
      return;
    }
    Navigator.pop(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Thanks for reporting this ${target.noun}. A moderator will review '
          "it within 24 hours. You won't see it any more"
          '${_alsoBlock ? ', or anything else from ${target.author.name}' : ''}.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.target;
    return AlertDialog(
      title: Text('Report ${target.noun}'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Why are you reporting this ${target.noun} by '
                '${target.author.name}?',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              RadioGroup<ReportReason>(
                groupValue: _reason,
                onChanged: (reason) => setState(() => _reason = reason),
                child: Column(
                  children: [
                    for (final reason in ReportReason.values)
                      RadioListTile<ReportReason>(
                        value: reason,
                        title: Text(reason.label),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                  ],
                ),
              ),
              TextField(
                controller: _details,
                maxLength: 500,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText:
                      'Anything else the moderator should know (optional)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              CheckboxListTile(
                value: _alsoBlock,
                onChanged: (value) => setState(() => _alsoBlock = value!),
                title: Text('Also block ${target.author.name}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _reason == null || _sending ? null : _send,
          style: FilledButton.styleFrom(backgroundColor: AppColors.heartRed),
          child: Text(_sending ? 'Sending…' : 'Report'),
        ),
      ],
    );
  }
}

/// Asks before blocking [user], then blocks them.
Future<void> confirmBlock(BuildContext context, UserProfile user) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Block ${user.name}?'),
      content: Text(
        "You won't see ${user.name}'s photos, comments or chat messages. "
        "They won't be told. You can unblock them from your Profile.",
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(backgroundColor: AppColors.heartRed),
          child: const Text('Block'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final blocked = await runUserAction(
    context,
    () => SafetyService().block(user),
    failureMessage: '${user.name} was not blocked. Please try again.',
  );
  if (blocked) {
    messenger.showSnackBar(SnackBar(content: Text('${user.name} is blocked.')));
  }
}
