import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../core/services/moderation_service.dart';
import '../../core/services/safety_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/user_action.dart';
import '../../core/widgets/app_network_image.dart';
import '../../core/widgets/live_data.dart';

/// The moderator's review screen: the AI content filter's switch, open
/// reports, what the filter took down, and who is banned. Apple expects
/// reports dealt with within 24 hours.
class ModerationScreen extends StatelessWidget {
  const ModerationScreen({super.key});

  static Future<void> show(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const ModerationScreen()));

  @override
  Widget build(BuildContext context) {
    final service = ModerationService();
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Moderation'),
          backgroundColor: AppColors.background,
          bottom: const TabBar(
            labelColor: AppColors.primaryDark,
            indicatorColor: AppColors.primary,
            tabs: [
              Tab(text: 'Reports'),
              Tab(text: 'Removed by AI'),
              Tab(text: 'Banned'),
            ],
          ),
        ),
        body: Column(
          children: [
            _FilterSwitch(service: service),
            const Divider(height: 1),
            Expanded(
              child: TabBarView(
                children: [
                  _ReportsTab(service: service),
                  _RemovedTab(service: service),
                  _BannedTab(service: service),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterSwitch extends StatelessWidget {
  final ModerationService service;

  const _FilterSwitch({required this.service});

  @override
  Widget build(BuildContext context) {
    return LiveData<bool>(
      stream: service.contentFilterOn,
      errorMessage: 'The filter switch could not be loaded.',
      loading: const SizedBox(height: 72),
      builder: (context, on) => SwitchListTile(
        value: on,
        activeThumbColor: AppColors.primary,
        title: const Text('AI content filter'),
        subtitle: Text(
          on
              ? 'On: photos, comments and chat messages the AI flags are '
                    'taken down within seconds, and listed under Removed by AI.'
              : 'Off: the AI still checks photos, but nothing is taken down.',
          style: const TextStyle(fontSize: 12),
        ),
        onChanged: (value) => runUserAction(
          context,
          () => service.setContentFilter(value),
          failureMessage: 'The filter was not switched. Please try again.',
        ),
      ),
    );
  }
}

// ── Reports ──────────────────────────────────────────

class _ReportsTab extends StatelessWidget {
  final ModerationService service;

  const _ReportsTab({required this.service});

  @override
  Widget build(BuildContext context) {
    return LiveData<List<ReportedPost>>(
      stream: service.openReports,
      errorMessage: 'Reports could not be loaded.',
      builder: (context, posts) {
        if (posts.isEmpty) {
          return const _Empty('No open reports.');
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: posts.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) =>
              _ReportCard(post: posts[index], service: service),
        );
      },
    );
  }
}

class _ReportCard extends StatelessWidget {
  final ReportedPost post;
  final ModerationService service;

  const _ReportCard({required this.post, required this.service});

  @override
  Widget build(BuildContext context) {
    final count = post.reports.length;
    final details = post.reports
        .map((report) => report.details)
        .where((details) => details.isNotEmpty);
    return _PostCard(
      kind: post.kind,
      authorName: post.authorName,
      imageUrl: post.imageUrl,
      text: post.kind == 'photo' ? 'At ${post.preview}' : post.preview,
      lines: [
        'Reported for: ${post.reasonSummary}',
        for (final line in details) '"$line"',
        '$count ${count == 1 ? 'report' : 'reports'}'
            '${post.latest == null ? '' : ', latest ${_ago(post.latest!)}'}',
      ],
      actions: [
        FilledButton(
          onPressed: () async {
            if (await _confirm(
              context,
              'Delete this ${postNoun(post.kind)}?',
              'It is deleted for everyone. This cannot be undone.',
              'Delete',
            )) {
              if (!context.mounted) return;
              await runUserAction(
                context,
                () => service.deleteReported(post),
                failureMessage: 'It was not deleted. Please try again.',
              );
            }
          },
          style: FilledButton.styleFrom(backgroundColor: AppColors.heartRed),
          child: const Text('Delete'),
        ),
        OutlinedButton(
          onPressed: () => runUserAction(
            context,
            () => service.settle(post, 'dismissed'),
            failureMessage: 'The reports were not dismissed. Please try again.',
          ),
          child: const Text('Dismiss'),
        ),
        _BanButton(
          service: service,
          userId: post.authorId,
          name: post.authorName,
        ),
      ],
    );
  }
}

// ── Removed by the AI ────────────────────────────────

class _RemovedTab extends StatelessWidget {
  final ModerationService service;

  const _RemovedTab({required this.service});

  @override
  Widget build(BuildContext context) {
    return LiveData<List<RemovedPost>>(
      stream: service.removedPosts,
      errorMessage: 'Removed posts could not be loaded.',
      builder: (context, posts) {
        if (posts.isEmpty) {
          return const _Empty('The AI has not taken anything down.');
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: posts.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final post = posts[index];
            return _PostCard(
              kind: post.kind,
              authorName: post.authorName,
              imageUrl: post.imageUrl,
              text: post.kind == 'photo' ? 'At ${post.place}' : post.text,
              lines: [
                'Flagged for: ${post.flaggedFor.join(', ')}'
                    '${post.reason.isEmpty ? '' : ' (${post.reason})'}',
                if (post.removedAt != null) 'Removed ${_ago(post.removedAt!)}',
              ],
              actions: [
                FilledButton(
                  onPressed: () => _callFunction(
                    context,
                    () => service.restore(post.key),
                    'It was not put back.',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                  child: const Text('Put back'),
                ),
                OutlinedButton(
                  onPressed: () async {
                    if (await _confirm(
                      context,
                      'Delete this ${postNoun(post.kind)} for good?',
                      'This cannot be undone.',
                      'Delete',
                    )) {
                      if (!context.mounted) return;
                      await _callFunction(
                        context,
                        () => service.discard(post.key),
                        'It was not deleted.',
                      );
                    }
                  },
                  child: const Text('Delete for good'),
                ),
                _BanButton(
                  service: service,
                  userId: post.authorId,
                  name: post.authorName,
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Runs a request to the functions, showing their own explanation when
  /// they give one (such as "The photo that comment was on has been
  /// deleted.").
  static Future<void> _callFunction(
    BuildContext context,
    Future<void> Function() call,
    String failure,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await call();
    } on FirebaseFunctionsException catch (error) {
      final known =
          error.code == 'not-found' || error.code == 'failed-precondition';
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            known && error.message != null
                ? error.message!
                : '$failure Please try again.',
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text('$failure Please try again.')),
      );
    }
  }
}

// ── Banned ───────────────────────────────────────────

class _BannedTab extends StatelessWidget {
  final ModerationService service;

  const _BannedTab({required this.service});

  @override
  Widget build(BuildContext context) {
    return LiveData<List<BannedUser>>(
      stream: service.bannedUsers,
      errorMessage: 'Banned people could not be loaded.',
      builder: (context, people) {
        if (people.isEmpty) return const _Empty('Nobody is banned.');
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            for (final person in people)
              ListTile(
                leading: const Icon(Icons.gavel, color: AppColors.heartRed),
                title: Text(person.name),
                subtitle: person.bannedAt == null
                    ? null
                    : Text('Banned ${_ago(person.bannedAt!)}'),
                trailing: TextButton(
                  onPressed: () => runUserAction(
                    context,
                    () => service.unban(person.id),
                    failureMessage:
                        '${person.name} was not unbanned. Please try again.',
                  ),
                  child: const Text('Unban'),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ── Shared ───────────────────────────────────────────

/// One post under review: what it is, who posted it, and what to do.
class _PostCard extends StatelessWidget {
  final String kind;
  final String authorName;
  final String? imageUrl;
  final String text;
  final List<String> lines;
  final List<Widget> actions;

  const _PostCard({
    required this.kind,
    required this.authorName,
    required this.imageUrl,
    required this.text,
    required this.lines,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final noun = postNoun(kind);
    final image = imageUrl;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (image != null && image.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AppNetworkImage(image, width: 88, height: 88),
                  )
                else
                  Icon(
                    kind == 'chat'
                        ? Icons.forum_outlined
                        : Icons.comment_outlined,
                    size: 32,
                    color: AppColors.textSecondary,
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${noun[0].toUpperCase()}${noun.substring(1)} by '
                        '$authorName',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (text.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          text,
                          maxLines: 6,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 6),
                      for (final line in lines)
                        Text(
                          line,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ),
      ),
    );
  }
}

class _BanButton extends StatelessWidget {
  final ModerationService service;
  final String userId;
  final String name;

  const _BanButton({
    required this.service,
    required this.userId,
    required this.name,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: userId.isEmpty
          ? null
          : () async {
              if (!await _confirm(
                context,
                'Ban $name?',
                '$name will not be able to post photos, comments or chat '
                    'messages. What they already posted stays until you delete '
                    'it. You can unban them under Banned.',
                'Ban',
              )) {
                return;
              }
              if (!context.mounted) return;
              final messenger = ScaffoldMessenger.of(context);
              if (await runUserAction(
                context,
                () => service.ban(userId, name),
                failureMessage: '$name was not banned. Please try again.',
              )) {
                messenger.showSnackBar(
                  SnackBar(content: Text('$name is banned.')),
                );
              }
            },
      icon: const Icon(Icons.gavel, size: 16),
      label: Text('Ban $name', overflow: TextOverflow.ellipsis),
      style: TextButton.styleFrom(foregroundColor: AppColors.heartRed),
    );
  }
}

class _Empty extends StatelessWidget {
  final String message;

  const _Empty(this.message);

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      message,
      style: const TextStyle(color: AppColors.textSecondary),
    ),
  );
}

Future<bool> _confirm(
  BuildContext context,
  String title,
  String message,
  String action,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(backgroundColor: AppColors.heartRed),
          child: Text(action),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// "just now", "5m ago", "3h ago", "2d ago".
String _ago(DateTime time) {
  final elapsed = DateTime.now().difference(time);
  if (elapsed.inMinutes < 1) return 'just now';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes}m ago';
  if (elapsed.inDays < 1) return '${elapsed.inHours}h ago';
  return '${elapsed.inDays}d ago';
}
