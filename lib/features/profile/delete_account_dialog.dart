import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/material.dart';

import '../../core/services/account_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/crash_reporting.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/permissions.dart';

/// "Delete your account?": what goes, then signing in once more to confirm
/// it is them, then the deleting. Stays open, saying why, if any step does
/// not go through.
class DeleteAccountDialog extends StatefulWidget {
  /// How they confirm it is them; null for a guest.
  final ConfirmMethod? method;

  /// The moderator's account is kept: the server refuses to delete it.
  final bool isModerator;

  /// Confirms it is them and deletes the account. Returns why it did not
  /// happen, or null once it has.
  final Future<String?> Function(String password) delete;

  const DeleteAccountDialog({
    super.key,
    required this.method,
    required this.isModerator,
    required this.delete,
  });

  /// Asks [user] to confirm, and deletes their account if they do. True
  /// once it is gone; the caller then signs out.
  static Future<bool> show(BuildContext context, auth.User user) async {
    final method = AuthService.confirmMethodFor(
      isAnonymous: user.isAnonymous,
      providerIds: user.providerData.map((info) => info.providerId),
    );
    final deleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DeleteAccountDialog(
        method: method,
        isModerator: isAdmin(user),
        delete: (password) => _delete(method, password),
      ),
    );
    return deleted == true;
  }

  static const _failed =
      'Your account could not be deleted just now. Please try again.';

  static Future<String?> _delete(ConfirmMethod? method, String password) async {
    if (method != null) {
      final confirmed = await AuthService().confirmIdentity(
        method,
        password: password,
      );
      if (!confirmed.isSuccess) return confirmed.error;
    }
    try {
      await AccountService().deleteMyAccount();
      return null;
    } on FirebaseFunctionsException catch (e, stack) {
      // The server words its refusals for the reader.
      if (e.code == 'failed-precondition' && e.message != null) {
        return e.message;
      }
      CrashReporting.recordError(e, stack, reason: 'account not deleted');
      return _failed;
    } catch (e, stack) {
      CrashReporting.recordError(e, stack, reason: 'account not deleted');
      return _failed;
    }
  }

  @override
  State<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<DeleteAccountDialog> {
  final _password = TextEditingController();
  bool _working = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  bool get _needsPassword => widget.method == ConfirmMethod.password;

  Future<void> _confirm() async {
    setState(() {
      _working = true;
      _error = null;
    });
    final error = await widget.delete(_password.text);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _working = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isModerator) {
      return AlertDialog(
        title: const Text('Delete account'),
        content: const Text(
          "This is the moderator's account. Deleting it would delete every "
          'photo it posted, so it cannot be done in the app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('OK'),
          ),
        ],
      );
    }

    const body = TextStyle(fontSize: 14, height: 1.45);
    final confirmNote = switch (widget.method) {
      ConfirmMethod.google =>
        'To confirm it is you, you will sign in with Google once more.',
      ConfirmMethod.apple =>
        'To confirm it is you, you will sign in with Apple once more. This '
            "also removes the app from your Apple ID's sign-in list.",
      ConfirmMethod.password => 'To confirm it is you, enter your password.',
      null => null,
    };

    return AlertDialog(
      title: const Text('Delete your account?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This permanently deletes your account and everything in it: '
              'the photos, comments and chat messages you posted, your likes, '
              'and your blocked list. It cannot be undone.',
              style: body,
            ),
            if (confirmNote != null) ...[
              const SizedBox(height: 12),
              Text(confirmNote, style: body),
            ],
            if (_needsPassword) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                enabled: !_working,
                autofillHints: const [AutofillHints.password],
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (_password.text.isNotEmpty && !_working) _confirm();
                },
              ),
            ],
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
      actions: [
        TextButton(
          onPressed: _working ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _working || (_needsPassword && _password.text.isEmpty)
              ? null
              : _confirm,
          style: FilledButton.styleFrom(backgroundColor: AppColors.heartRed),
          child: _working
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Delete account'),
        ),
      ],
    );
  }
}
