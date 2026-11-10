import 'package:carousel_slider/carousel_slider.dart'
    show
        CarouselOptions,
        CarouselPageChangedReason,
        CarouselSlider,
        CarouselSliderController;
import 'package:flutter/material.dart';

import '../../../core/models/models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/carousel_selection.dart';
import '../../../core/widgets/app_network_image.dart';
import '../../../core/widgets/shared_widgets.dart';
import 'carousel_momentum_physics.dart';
import 'full_screen_photo_view.dart';

/// The carousel layout: a strip of thumbnails, with whichever one is centred
/// shown large beneath it at its own proportions.
///
/// Takes the same already-filtered, already-sorted list the grid does, so the
/// two layouts can never disagree about which photos a tab contains.
///
/// The selection lives in a [ValueNotifier] rather than in `setState`.
/// carousel_slider rebuilds its PageController on every rebuild of the
/// slider, so the slider is kept out of the rebuild that a new selection
/// causes: only the thumbnail borders and the large photo listen.
class PhotoCarouselView extends StatefulWidget {
  final List<PhotoPost> photos;
  final Function(String photoId)? onPhotoTap;
  final double horizontalPadding;

  /// The photo to centre on — the one the reader was on when they asked to
  /// come back to this tab — instead of the tab's first photo. Ignored if it
  /// is not in [photos].
  final String? focusPhotoId;

  /// Changes with each new focus request, so a carousel that is already
  /// showing still moves to [focusPhotoId], even when it is the same photo
  /// as last time.
  final int focusRequest;

  const PhotoCarouselView({
    super.key,
    required this.photos,
    this.onPhotoTap,
    this.horizontalPadding = 16,
    this.focusPhotoId,
    this.focusRequest = 0,
  });

  @override
  State<PhotoCarouselView> createState() => _PhotoCarouselViewState();
}

class _PhotoCarouselViewState extends State<PhotoCarouselView> {
  final _slider = CarouselSliderController();
  final _selected = ValueNotifier<int>(0);
  String? _selectedId;

  /// The thumbnail a tap is currently sliding to the centre, if any.
  int? _tapTarget;

  static const _gap = 10.0;

  @override
  void initState() {
    super.initState();
    // Start on the requested photo when there is one; the slider opens on
    // _selected's index, so nothing has to move afterwards.
    _selectedId =
        widget.focusPhotoId ??
        (widget.photos.isEmpty ? null : widget.photos.first.id);
    _select(resolveCarouselSelection(widget.photos, _selectedId));
  }

  @override
  void didUpdateWidget(PhotoCarouselView old) {
    super.didUpdateWidget(old);
    final refocus =
        widget.focusRequest != old.focusRequest && widget.focusPhotoId != null;
    if (identical(old.photos, widget.photos) && !refocus) return;
    if (refocus) _selectedId = widget.focusPhotoId;

    final previous = _selected.value;
    final index = resolveCarouselSelection(widget.photos, _selectedId);
    _select(index);
    // Only move the strip when the selected photo actually changed position;
    // a re-emitted list with the same order must not interrupt a swipe.
    if (index != previous) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _slider.ready) _slider.jumpToPage(index);
      });
    }
  }

  @override
  void dispose() {
    _selected.dispose();
    super.dispose();
  }

  void _select(int index) {
    _selected.value = index;
    _selectedId = widget.photos.isEmpty ? null : widget.photos[index].id;
  }

  void _onPageChanged(int index, CarouselPageChangedReason _) {
    // A tap has already chosen its photo before the strip starts moving, so
    // the pages it passes on the way are skipped — following them would
    // flash each one through the large view.
    //
    // This deliberately ignores carousel_slider's own reason argument. It
    // only reports "manual" after a finger or mouse button presses on the
    // strip; trackpad and mouse-wheel scrolling on web never press, so they
    // arrive labelled "controller" and were being dropped, leaving the large
    // photo stuck while the strip scrolled.
    final target = _tapTarget;
    if (target != null) {
      if (index == target) _tapTarget = null;
      return;
    }
    _select(index);
  }

  Future<void> _onThumbnailTap(int index) async {
    if (index == _selected.value) return;
    _select(index);
    _tapTarget = index;
    await _slider.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
    // Also covers an animation cut short by a drag or scroll, which never
    // reaches the target page.
    if (_tapTarget == index) _tapTarget = null;
  }

  /// Thumbnail edge length. Fixed sizes rather than a fraction of the width,
  /// so a wide desktop window gets more thumbnails, not enormous ones.
  static double _thumbSizeFor(double width) => width >= 900
      ? 104
      : width >= 560
      ? 92
      : 76;

  @override
  Widget build(BuildContext context) {
    final photos = widget.photos;
    if (photos.isEmpty) return const SizedBox.shrink();
    final pad = widget.horizontalPadding;

    return LayoutBuilder(
      builder: (context, constraints) {
        final stripWidth = constraints.maxWidth - pad * 2;
        final thumb = _thumbSizeFor(stripWidth);
        final fraction = ((thumb + _gap) / stripWidth).clamp(0.05, 1.0);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: pad),
              child: SizedBox(
                height: thumb,
                child: CarouselSlider.builder(
                  // carousel_slider reads its viewport fraction once, so a
                  // window resize needs a fresh slider. It starts on the
                  // photo already selected, so nothing visibly jumps.
                  key: ValueKey(fraction.toStringAsFixed(4)),
                  carouselController: _slider,
                  itemCount: photos.length,
                  options: CarouselOptions(
                    height: thumb,
                    viewportFraction: fraction,
                    initialPage: _selected.value,
                    enableInfiniteScroll: false,
                    // A flick coasts and slows before settling on a
                    // thumbnail, instead of moving exactly one.
                    pageSnapping: false,
                    scrollPhysics: const CarouselMomentumPhysics(),
                    // The package's enlargeCenterPage shrinks each item more
                    // the further it sits from the centre — made for two or
                    // three big slides, it turns a strip of a dozen
                    // thumbnails into dots. The highlight is done in
                    // _Thumbnail instead, so the rest stay one even size.
                    enlargeCenterPage: false,
                    onPageChanged: _onPageChanged,
                  ),
                  itemBuilder: (context, index, _) => _Thumbnail(
                    photo: photos[index],
                    index: index,
                    selected: _selected,
                    size: thumb,
                    gap: _gap,
                    onTap: () => _onThumbnailTap(index),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: _selected,
                builder: (context, index, _) {
                  final photo = photos[index.clamp(0, photos.length - 1)];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Caption(
                        photo: photo,
                        position: index + 1,
                        total: photos.length,
                        horizontalPadding: pad,
                        onDetails: widget.onPhotoTap == null
                            ? null
                            : () => widget.onPhotoTap!(photo.id),
                      ),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(pad, 0, pad, 16),
                          child: _LargePhoto(photo: photo),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final PhotoPost photo;
  final int index;
  final ValueNotifier<int> selected;
  final double size;
  final double gap;
  final VoidCallback onTap;

  const _Thumbnail({
    required this.photo,
    required this.index,
    required this.selected,
    required this.size,
    required this.gap,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final decodeWidth = (size * MediaQuery.devicePixelRatioOf(context)).round();
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: AppNetworkImage(
        photo.imageUrl,
        fit: BoxFit.cover,
        decodeWidth: decodeWidth,
      ),
    );

    return ValueListenableBuilder<int>(
      valueListenable: selected,
      child: image,
      builder: (context, selectedIndex, image) {
        final isSelected = selectedIndex == index;
        return Semantics(
          button: true,
          selected: isSelected,
          label: 'Photo ${index + 1}, ${photo.location.name}',
          child: GestureDetector(
            key: ValueKey('carousel-thumb-${photo.id}'),
            onTap: onTap,
            // Selected: full size with a coloured frame. The rest sit a
            // little smaller and dimmer, so the choice reads at a glance.
            child: AnimatedScale(
              scale: isSelected ? 1 : 0.86,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: AnimatedOpacity(
                opacity: isSelected ? 1 : 0.8,
                duration: const Duration(milliseconds: 200),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: EdgeInsets.symmetric(horizontal: gap / 2),
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: isSelected ? AppColors.primary : Colors.transparent,
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.35),
                              blurRadius: 8,
                            ),
                          ]
                        : null,
                  ),
                  child: AspectRatio(aspectRatio: 1, child: image),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Caption extends StatelessWidget {
  final PhotoPost photo;
  final int position;
  final int total;
  final double horizontalPadding;
  final VoidCallback? onDetails;

  const _Caption({
    required this.photo,
    required this.position,
    required this.total,
    required this.horizontalPadding,
    this.onDetails,
  });

  static const linkLabel = 'Image Comments and Directions';

  @override
  Widget build(BuildContext context) {
    // The grid opens a photo's page on tap; here a tap on the photo goes full
    // screen instead, so its page — comments, likes and directions — needs a
    // way in of its own.
    final link = onDetails == null
        ? null
        : OutlinedButton.icon(
            onPressed: onDetails,
            icon: const Icon(Icons.forum_outlined, size: 18),
            label: const Text(linkLabel),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          );

    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 12, horizontalPadding, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final info = _info();
          // Beside the info on a wide screen; on a phone the label would
          // squeeze the place name to nothing, so it gets a line of its own.
          if (link == null) return info;
          if (constraints.maxWidth >= 560) {
            return Row(
              children: [
                Expanded(child: info),
                const SizedBox(width: 4),
                link,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [info, link],
          );
        },
      ),
    );
  }

  Widget _info() {
    return Row(
      children: [
        UserAvatar(
          initials: photo.user.initials,
          color: photo.user.avatarColor,
          size: 30,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                photo.location.name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '${photo.user.name} · $position of $total',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        HeartCount(count: photo.heartCount),
      ],
    );
  }
}

class _LargePhoto extends StatelessWidget {
  final PhotoPost photo;

  const _LargePhoto({required this.photo});

  @override
  Widget build(BuildContext context) {
    // Deliberately not keyed by photo: the same image widget is reused as
    // the selection changes, so while the strip glides past photos the
    // previous one stays up until the next has loaded, instead of a grey
    // placeholder flashing between every one.
    return TapToEnlarge(
      photo: photo,
      sharedTag: FullScreenPhotoView.heroTag(photo.id),
      // contain, never cover: the whole photo at its own proportions,
      // letterboxed by whatever space is left over.
      child: AppNetworkImage(
        photo.imageUrl,
        fit: BoxFit.contain,
        keepPreviousWhileLoading: true,
      ),
    );
  }
}
