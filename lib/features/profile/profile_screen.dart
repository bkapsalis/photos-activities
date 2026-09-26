import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;

import '../../core/models/models.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/contribution_stats_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../auth/upgrade_account_screen.dart';

const Color _guestAmber = Color(0xFFF9A825);

/// Account status: who you are signed in as, and — for a guest — how to become
/// a permanent account.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  static Future<void> show(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: AppColors.background,
      ),
      // userChanges (not authStateChanges) so registering from this page flips
      // it to the registered state in place — linking keeps the same uid.
      body: StreamBuilder<auth.User?>(
        stream: authService.userChanges,
        builder: (context, snapshot) {
          final user = snapshot.data ?? auth.FirebaseAuth.instance.currentUser;
          if (user == null) {
            return const Center(child: Text('You are not signed in.'));
          }

          final profile = UserProfile.fromFirebaseUser(user);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(profile: profile, user: user),
                    const SizedBox(height: 24),
                    if (profile.isGuest)
                      _GuestSection(onRegister: () => _register(context))
                    else
                      _RegisteredSection(user: user),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: () => _signOut(context, authService,
                          isGuest: profile.isGuest),
                      icon: const Icon(Icons.logout, size: 18),
                      label: const Text('Sign out'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        foregroundColor: AppColors.textPrimary,
                        side: BorderSide(color: AppColors.divider),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _register(BuildContext context) async {
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
  }

  Future<void> _signOut(
    BuildContext context,
    AuthService authService, {
    required bool isGuest,
  }) async {
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
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

    if (confirmed == true) {
      await authService.signOut();
      // Pop back to the auth gate, which swaps in the sign-in screen.
      navigator.popUntil((route) => route.isFirst);
    }
  }
}

class _Header extends StatelessWidget {
  final UserProfile profile;
  final auth.User user;

  const _Header({required this.profile, required this.user});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        UserAvatar(
          initials: profile.initials,
          color: profile.avatarColor,
          size: 76,
        ),
        const SizedBox(height: 14),
        Text(
          profile.name,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        _StatusChip(isGuest: profile.isGuest),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final bool isGuest;

  const _StatusChip({required this.isGuest});

  @override
  Widget build(BuildContext context) {
    final color = isGuest ? _guestAmber : AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isGuest ? Icons.person_outline : Icons.verified_user,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            isGuest ? 'Guest session' : 'Registered account',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _GuestSection extends StatelessWidget {
  final VoidCallback onRegister;

  const _GuestSection({required this.onRegister});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Card(
          borderColor: _guestAmber.withValues(alpha: 0.4),
          background: _guestAmber.withValues(alpha: 0.07),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You have not registered yet',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'This guest account lives only on this device. Sign out, '
                'reinstall or switch phones and it is gone for good — along '
                'with the chat history attached to it.',
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'REGISTERING GETS YOU',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        const _Benefit(
          icon: Icons.forum_outlined,
          title: 'Your chat history, kept',
          detail: 'Everything you have already posted stays yours — you are '
              'upgraded in place, not moved to a new account.',
        ),
        const _Benefit(
          icon: Icons.devices_outlined,
          title: 'Sign in from any device',
          detail: 'Reach the same account from another phone, or from the web.',
        ),
        const _Benefit(
          icon: Icons.badge_outlined,
          title: 'A name instead of a number',
          detail: 'Your posts show your name rather than a guest tag.',
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: onRegister,
          icon: const Icon(Icons.person_add_alt, size: 20),
          label: const Text('Create an account'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 15),
            backgroundColor: AppColors.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Takes a moment. Nothing you have posted is lost.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _RegisteredSection extends StatelessWidget {
  final auth.User user;

  const _RegisteredSection({required this.user});

  /// Firebase reports each linked credential; map the ids people recognise.
  List<String> get _methods {
    final methods = <String>[];
    for (final provider in user.providerData) {
      switch (provider.providerId) {
        case 'password':
          methods.add('Email and password');
        case 'google.com':
          methods.add('Google');
        case 'apple.com':
          methods.add('Apple');
        default:
          methods.add(provider.providerId);
      }
    }
    return methods;
  }

  @override
  Widget build(BuildContext context) {
    final methods = _methods;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Card(
          borderColor: AppColors.primary.withValues(alpha: 0.35),
          background: AppColors.primary.withValues(alpha: 0.07),
          child: const Row(
            children: [
              Icon(Icons.check_circle, color: AppColors.primary, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Your chat history and photos are saved to this account.',
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.4,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _Contributions(userId: user.uid),
        const SizedBox(height: 20),
        const Text(
          'ACCOUNT',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        if (user.email != null)
          _DetailRow(icon: Icons.email_outlined, label: 'Email', value: user.email!),
        _DetailRow(
          icon: Icons.key_outlined,
          label: methods.length == 1 ? 'Sign-in method' : 'Sign-in methods',
          value: methods.isEmpty ? 'Not available' : methods.join(', '),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  final Color borderColor;
  final Color background;

  const _Card({
    required this.child,
    required this.borderColor,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: child,
    );
  }
}

class _Benefit extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;

  const _Benefit({
    required this.icon,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Here is what you have added" — photos shared, likes those photos earned,
/// and comments written.
class _Contributions extends StatefulWidget {
  final String userId;

  const _Contributions({required this.userId});

  @override
  State<_Contributions> createState() => _ContributionsState();
}

class _ContributionsState extends State<_Contributions> {
  final _service = ContributionStatsService();
  late Future<ContributionStats> _stats;

  @override
  void initState() {
    super.initState();
    _stats = _service.forUser(widget.userId);
  }

  @override
  void didUpdateWidget(covariant _Contributions oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only refetch when the account actually changes — the parent rebuilds on
    // every userChanges tick, and each fetch is a Firestore read.
    if (oldWidget.userId != widget.userId) {
      _stats = _service.forUser(widget.userId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'YOUR CONTRIBUTIONS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        FutureBuilder<ContributionStats>(
          future: _stats,
          builder: (context, snapshot) {
            final loading =
                snapshot.connectionState == ConnectionState.waiting;
            final stats = snapshot.data ?? const ContributionStats();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _StatTile(
                        icon: Icons.photo_camera_outlined,
                        value: stats.photos,
                        label: 'Photos',
                        loading: loading,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatTile(
                        icon: Icons.favorite_border,
                        value: stats.likesReceived,
                        label: 'Likes earned',
                        loading: loading,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatTile(
                        icon: Icons.mode_comment_outlined,
                        value: stats.comments,
                        label: 'Comments',
                        loading: loading,
                      ),
                    ),
                  ],
                ),
                if (!loading) ...[
                  const SizedBox(height: 10),
                  Text(
                    stats.hasAny
                        ? 'Thank you for helping people discover the Bay Area.'
                        : 'Share your first photo — the community starts with you.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final int? value;
  final String label;
  final bool loading;

  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(height: 8),
          SizedBox(
            height: 30,
            child: loading
                ? const Center(
                    child: SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : FittedBox(
                    child: Text(
                      // An unreadable figure shows as "—" rather than 0, which
                      // would wrongly claim the person contributed nothing.
                      value?.toString() ?? '—',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
