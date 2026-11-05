import 'package:flutter/material.dart';

import '../../core/services/safety_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/user_action.dart';
import '../../core/widgets/live_data.dart';

/// Everyone the reader has blocked, each with Unblock.
class BlockedPeopleScreen extends StatelessWidget {
  const BlockedPeopleScreen({super.key});

  static Future<void> show(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const BlockedPeopleScreen()));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Blocked people'),
        backgroundColor: AppColors.background,
      ),
      body: LiveData<SafetyFilter>(
        stream: () => SafetyService().filter(),
        errorMessage: 'Your blocked list could not be loaded.',
        builder: (context, filter) {
          if (filter.blocked.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "You haven't blocked anyone. To block someone, tap ⋯ on "
                  'one of their posts.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            );
          }
          final people = filter.blocked.entries.toList()
            ..sort((a, b) => a.value.compareTo(b.value));
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              for (final person in people)
                ListTile(
                  leading: const Icon(Icons.block, color: AppColors.heartRed),
                  title: Text(person.value),
                  trailing: TextButton(
                    onPressed: () => runUserAction(
                      context,
                      () => SafetyService().unblock(person.key),
                      failureMessage:
                          '${person.value} was not unblocked. Please try again.',
                    ),
                    child: const Text('Unblock'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
