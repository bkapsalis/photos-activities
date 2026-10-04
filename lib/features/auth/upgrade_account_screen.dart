import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;

import '../../core/models/models.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/chat_history_service.dart';
import '../../core/theme/app_colors.dart';

/// Turns the current guest session into a permanent account.
///
/// This links a credential to the existing anonymous user rather than creating
/// a new one, so the uid — and therefore everything the guest has posted —
/// carries over.
class UpgradeAccountScreen extends StatefulWidget {
  const UpgradeAccountScreen({super.key});

  static Future<bool?> show(BuildContext context) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const UpgradeAccountScreen()),
    );
  }

  @override
  State<UpgradeAccountScreen> createState() => _UpgradeAccountScreenState();
}

class _UpgradeAccountScreenState extends State<UpgradeAccountScreen>
    with WidgetsBindingObserver {
  final AuthService _authService = AuthService();
  final ChatHistoryService _historyService = ChatHistoryService();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  String? _error;
  int? _messageCount;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadMessageCount();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Same cancelled-provider trap as the sign-in screen: back out of the
    // Apple or Google sheet and the future may never settle. Still being a
    // guest on resume means the upgrade did not happen.
    if (state == AppLifecycleState.resumed && _isLoading && _authService.isGuest) {
      setState(() {
        _isLoading = false;
        _error = 'Registration was cancelled.';
      });
    }
  }

  Future<void> _loadMessageCount() async {
    final uid = _authService.currentUser?.uid;
    if (uid == null) return;
    final count = await _historyService.countAuthoredMessages(uid);
    if (mounted) setState(() => _messageCount = count);
  }

  Future<void> _register(Future<AuthResult> Function() link) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await link();

    if (!mounted) return;

    if (!result.isSuccess) {
      setState(() {
        _isLoading = false;
        _error = result.error;
      });
      return;
    }

    // The account is upgraded at this point. Rewriting the author name on old
    // messages is a best-effort follow-up: if it fails the registration stands.
    final user = result.user;
    if (user != null) {
      await _historyService.renameAuthor(UserProfile.fromFirebaseUser(user));
    }

    if (!mounted) return;
    setState(() => _isLoading = false);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final count = _messageCount;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Create your account'),
        backgroundColor: AppColors.background,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.lock_open_rounded,
                    size: 56, color: AppColors.primary),
                const SizedBox(height: 16),
                const Text(
                  'Keep what you have posted',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  count == null
                      ? 'Registering keeps your chat history and photos on this '
                          'account, and lets you sign in from another device.'
                      : count == 0
                          ? 'Register to keep your chat history and photos, and '
                              'to sign in from another device.'
                          : 'Your $count message${count == 1 ? '' : 's'} will '
                              'stay with this account, and you will be able to '
                              'sign in from another device.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 32),

                if (AuthService.isGoogleSignInOffered) ...[
                  OutlinedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () => _register(_authService.linkGuestWithGoogle),
                    icon: const Icon(Icons.g_mobiledata, size: 28),
                    label: const Text('Register with Google'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: BorderSide(color: AppColors.divider),
                    ),
                  ),
                  const SizedBox(height: 24),

                  Row(
                    children: [
                      Expanded(child: Divider(color: AppColors.divider)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text('or',
                            style: TextStyle(color: AppColors.textSecondary)),
                      ),
                      Expanded(child: Divider(color: AppColors.divider)),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],

                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: AppColors.surface,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: AppColors.surface,
                  ),
                ),
                const SizedBox(height: 16),

                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),

                FilledButton(
                  onPressed: _isLoading ? null : _registerWithEmail,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Create Account'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _isLoading
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('Not now'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _registerWithEmail() {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please enter an email and password.');
      return;
    }
    _register(() => _authService.linkGuestWithEmail(email, password));
  }
}

/// Watches for the session becoming a guest and offers registration.
///
/// Listens to [AuthService.userChanges] rather than auth state: linking keeps
/// the same uid, so auth state never fires and the prompt would never clear.
class GuestBanner extends StatelessWidget {
  const GuestBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<auth.User?>(
      stream: AuthService().userChanges,
      builder: (context, snapshot) {
        final user = snapshot.data ?? auth.FirebaseAuth.instance.currentUser;
        if (user == null || !user.isAnonymous) return const SizedBox.shrink();

        return Material(
          color: AppColors.primary.withValues(alpha: 0.10),
          child: InkWell(
            onTap: () => _openUpgrade(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.person_outline,
                      size: 18, color: AppColors.primaryDark),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Browsing as a guest — register to save your chat history',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Register',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  const Icon(Icons.chevron_right,
                      size: 18, color: AppColors.primaryDark),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static Future<void> _openUpgrade(BuildContext context) async {
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
}
