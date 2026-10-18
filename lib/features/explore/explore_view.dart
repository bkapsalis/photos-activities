import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../../core/models/models.dart';
import '../../core/services/firestore_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/explore_picks.dart';
import '../home/widgets/photo_card.dart';

/// The Explore tab: a shuffled mix of the best-liked photo from every
/// location, across all categories.
///
/// The shuffle is deliberately *not* re-rolled on every rebuild. A new seed
/// is drawn only when you open the tab or pull to refresh, because the photo
/// list arrives on a Firestore stream — reshuffling per build would make the
/// grid reorder itself under the reader's thumb every time a heart count
/// changed somewhere.
class ExploreView extends StatefulWidget {
  final Function(String photoId)? onPhotoTap;

  const ExploreView({super.key, this.onPhotoTap});

  @override
  State<ExploreView> createState() => _ExploreViewState();
}

class _ExploreViewState extends State<ExploreView> {
  /// Subscribed once. Created in build, a new stream each rebuild made the
  /// StreamBuilder resubscribe and flash its spinner.
  late final Stream<List<PhotoPost>> _photos = FirestoreService()
      .streamAllPhotos();

  /// The shuffle's seed, not a [Random]: each build shuffles with a fresh
  /// `Random(_seed)`, so every rebuild deals the same order. Sharing one
  /// Random across builds drew new numbers each time and reordered the grid
  /// on any rebuild at all.
  late int _seed;

  static const _perLocation = 2;

  @override
  void initState() {
    super.initState();
    _seed = Random().nextInt(1 << 32);
  }

  void _reshuffle() => setState(() => _seed = Random().nextInt(1 << 32));

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Best of every location',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const Text(
                      'Explore',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.shuffle),
                tooltip: 'Shuffle',
                onPressed: _reshuffle,
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<PhotoPost>>(
            stream: _photos,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return _ExploreMessage(
                  icon: Icons.cloud_off,
                  title: 'Could not load Explore',
                  detail: '${snapshot.error}',
                );
              }

              final picks = (snapshot.data ?? const <PhotoPost>[])
                  .topLikedPerLocation(
                    perLocation: _perLocation,
                    random: Random(_seed),
                  );

              if (picks.isEmpty) {
                return const _ExploreMessage(
                  icon: Icons.explore_outlined,
                  title: 'Nothing to explore yet',
                  detail:
                      'Once photos are added, the best-liked shot from '
                      'each location shows up here.',
                );
              }

              return RefreshIndicator(
                onRefresh: () async => _reshuffle(),
                // The same view serves phones and the browser, so the column
                // count follows the width rather than being fixed at 2.
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final crossAxisCount = constraints.maxWidth > 1200
                        ? 5
                        : constraints.maxWidth > 900
                        ? 4
                        : constraints.maxWidth > 600
                        ? 3
                        : 2;
                    return MasonryGridView.count(
                      physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: picks.length,
                      itemBuilder: (context, index) {
                        final photo = picks[index];
                        return PhotoCard(
                          photo: photo,
                          onTap: () => widget.onPhotoTap?.call(photo.id),
                        );
                      },
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ExploreMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;

  const _ExploreMessage({
    required this.icon,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
