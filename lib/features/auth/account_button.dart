import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;

import '../../core/models/models.dart';
import '../../core/config/env_config.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/crash_reporting.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../profile/profile_screen.dart';
import 'upgrade_account_screen.dart';

/// Avatar for the signed-in user, with account actions behind it.
///
/// Guests get the route to a permanent account; everyone gets a way out.
class AccountButton extends StatelessWidget {
  final double size;

  const AccountButton({super.key, this.size = 36});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();

    return StreamBuilder<auth.User?>(
      stream: authService.userChanges,
      builder: (context, snapshot) {
        final user = snapshot.data ?? auth.FirebaseAuth.instance.currentUser;
        if (user == null) return const SizedBox.shrink();

        final profile = UserProfile.fromFirebaseUser(user);

        return PopupMenuButton<String>(
          tooltip: profile.name,
          offset: const Offset(0, 44),
          onSelected: (value) => _onSelected(context, authService, value),
          itemBuilder: (context) => [
            PopupMenuItem<String>(
              enabled: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    profile.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    profile.isGuest
                        ? 'Guest session on this device'
                        : user.email ?? 'Registered',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem<String>(
              value: 'profile',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.account_circle_outlined, size: 20),
                title: Text('Profile'),
              ),
            ),
            if (profile.isGuest)
              const PopupMenuItem<String>(
                value: 'register',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.person_add_alt,
                      size: 20, color: AppColors.primary),
                  title: Text('Create account'),
                  subtitle: Text('Keeps your chat history',
                      style: TextStyle(fontSize: 11)),
                ),
              ),
            // Dev builds only: proves crash reports reach Crashlytics.
            if (EnvConfig.instance.isDev && CrashReporting.supported)
              const PopupMenuItem<String>(
                value: 'testcrash',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.bug_report_outlined, size: 20),
                  title: Text('Send test crash'),
                  subtitle: Text('Dev only. Reopen the app to send it.',
                      style: TextStyle(fontSize: 11)),
                ),
              ),
            const PopupMenuItem<String>(
              value: 'signout',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.logout, size: 20),
                title: Text('Sign out'),
              ),
            ),
          ],
          child: UserAvatar(
            initials: profile.initials,
            color: profile.avatarColor,
            size: size,
          ),
        );
      },
    );
  }

  Future<void> _onSelected(
    BuildContext context,
    AuthService authService,
    String value,
  ) async {
    if (value == 'profile') {
      await ProfileScreen.show(context);
      return;
    }

    if (value == 'register') {
      final messenger = ScaffoldMessenger.of(context);
      final registered = await UpgradeAccountScreen.show(context);
      if (registered == true) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Account created — your chat history is saved.'),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    if (value == 'testcrash') {
      CrashReporting.testCrash();
      return;
    }

    if (value == 'signout') {
      final confirmed = await _confirmSignOut(context, authService.isGuest);
      if (confirmed == true) await authService.signOut();
    }
  }

  Future<bool?> _confirmSignOut(BuildContext context, bool isGuest) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        // A signed-out guest session cannot be recovered: the anonymous
        // credential lives only on this device.
        content: Text(
          isGuest
              ? 'This guest session cannot be recovered once you sign out, and '
                  'your chat history will stay behind. Register first to keep it.'
              : 'You can sign back in at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: isGuest ? AppColors.heartRed : AppColors.primary,
            ),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}
