import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../core/services/crash_reporting.dart';
import '../../core/services/moderation_service.dart';
import '../../core/theme/app_colors.dart';

enum _Stage { enter, found, deleted }

/// A moderator's "Delete an account": for someone who emailed to ask, as
/// web/delete-account.html offers. Finds the account by its email address,
/// shows whose it is and what is in it, then deletes it and everything in
/// it, as its owner's own "Delete account" would.
class DeleteAccountOfDialog extends StatefulWidget {
  /// The account using an email address, or null if none does. May throw.
  final Future<AccountToDelete?> Function(String email) find;

  /// Deletes the account. May throw.
  final Future<void> Function(String uid) delete;

  const DeleteAccountOfDialog({
    super.key,
    required this.find,
    required this.delete,
  });

  /// Not dismissed by a tap outside while deleting: it would carry on
  /// unseen.
  static Future<void> show(BuildContext context) {
    final service = ModerationService();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DeleteAccountOfDialog(
        find: service.findAccount,
        delete: service.deleteAccountOf,
      ),
    );
  }

  @override
  State<DeleteAccountOfDialog> createState() => _DeleteAccountOfDialogState();
}

class _DeleteAccountOfDialogState extends State<DeleteAccountOfDialog> {
  final _email = TextEditingController();
  _Stage _stage = _Stage.enter;
  AccountToDelete? _account;
  bool _working = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  /// Runs [step], showing a spinner meanwhile and, inline, the problem it
  /// returns or any failure.
  Future<void> _run(String what, Future<String?> Function() step) async {
    setState(() {
      _working = true;
      _error = null;
    });
    String? error;
    try {
      error = await step();
    } on FirebaseFunctionsException catch (e, stack) {
      // The server words what it expects to go wrong for the moderator.
      const worded = {'invalid-argument', 'not-found', 'failed-precondition'};
      if (worded.contains(e.code) && e.message != null) {
        error = e.message;
      } else {
        CrashReporting.recordError(e, stack, reason: what);
        error = 'That could not be done just now. Please try again.';
      }
    } catch (e, stack) {
      CrashReporting.recordError(e, stack, reason: what);
      error = 'That could not be done just now. Please try again.';
    }
    if (!mounted) return;
    setState(() {
      _working = false;
      _error = error;
    });
  }

  Future<void> _find() => _run('finding an account to delete', () async {
    final account = await widget.find(_email.text.trim());
    if (account == null) return 'No account uses that email address.';
    _account = account;
    _stage = _Stage.found;
    return null;
  });

  Future<void> _delete() => _run('deleting an account', () async {
    await widget.delete(_account!.uid);
    _stage = _Stage.deleted;
    return null;
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _stage == _Stage.deleted ? 'Account deleted' : 'Delete an account',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...switch (_stage) {
              _Stage.enter => _enter(),
              _Stage.found => _found(_account!),
              _Stage.deleted => _deleted(_account!),
            },
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(
                  color: AppColors.heartRed,
                  fontSize: 13.5,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: switch (_stage) {
        _Stage.enter => [
          TextButton(
            onPressed: _working ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _working || _email.text.trim().isEmpty ? null : _find,
            child: _working ? const _Spinner() : const Text('Find account'),
          ),
        ],
        _Stage.found => [
          TextButton(
            onPressed: _working
                ? null
                : () => setState(() {
                    _stage = _Stage.enter;
                    _error = null;
                  }),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: _working ? null : _delete,
            style: FilledButton.styleFrom(backgroundColor: AppColors.heartRed),
            child: _working ? const _Spinner() : const Text('Delete account'),
          ),
        ],
        _Stage.deleted => [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      },
    );
  }

  static const _body = TextStyle(fontSize: 14, height: 1.45);

  List<Widget> _enter() => [
    const Text(
      'For someone who emailed to ask for their account to be deleted. '
      'Enter the email address on their account: the one they wrote from.',
      style: _body,
    ),
    const SizedBox(height: 12),
    TextField(
      controller: _email,
      enabled: !_working,
      autofocus: true,
      keyboardType: TextInputType.emailAddress,
      autocorrect: false,
      decoration: const InputDecoration(
        labelText: 'Email address',
        border: OutlineInputBorder(),
      ),
      onChanged: (_) => setState(() => _error = null),
      onSubmitted: (_) {
        if (_email.text.trim().isNotEmpty && !_working) _find();
      },
    ),
  ];

  List<Widget> _found(AccountToDelete account) => [
    Text(
      account.name ?? 'No name',
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    ),
    if (account.email != null) Text(account.email!, style: _body),
    const SizedBox(height: 8),
    Text('Signs in with ${signInLabel(account.signInWith)}', style: _body),
    if (account.createdAt != null)
      Text('Joined ${shortDate(account.createdAt!)}', style: _body),
    if (account.lastSignInAt != null)
      Text('Last signed in ${shortDate(account.lastSignInAt!)}', style: _body),
    const SizedBox(height: 8),
    Text(contentsLine(account), style: _body),
    const SizedBox(height: 12),
    const Text(
      'Deleting removes the account and everything in it. It cannot be '
      'undone.',
      style: _body,
    ),
  ];

  List<Widget> _deleted(AccountToDelete account) => [
    Text(
      '${account.name == null ? 'The' : "${account.name}'s"} account and '
      'everything in it have been deleted. Reply to their email to let them '
      'know.',
      style: _body,
    ),
  ];
}

/// "Google", "Apple and email and password", or "nothing" for a guest.
String signInLabel(List<String> providers) {
  const names = {
    'google.com': 'Google',
    'apple.com': 'Apple',
    'password': 'email and password',
  };
  final known = [for (final p in providers) names[p] ?? p];
  return known.isEmpty ? 'nothing (a guest)' : known.join(' and ');
}

/// "1 photo, 2 comments and chat messages, 3 likes".
String contentsLine(AccountToDelete account) {
  String n(int count, String one, String many) =>
      '$count ${count == 1 ? one : many}';
  return '${n(account.photos, 'photo', 'photos')}, '
      '${n(account.messages, 'comment or chat message', 'comments and chat messages')}, '
      '${n(account.likes, 'like', 'likes')}';
}

/// "Nov 6, 2026".
String shortDate(DateTime date) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 18,
    width: 18,
    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
  );
}
