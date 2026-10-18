import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/models/models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/photo_sorting.dart';
import 'photo_pin.dart';

/// Shows the photos currently on screen as thumbnail pins on a Google map.
///
/// Only the list handed in is plotted — this deliberately takes the already
/// filtered photos rather than querying again, so the map always matches the
/// category, location tab and search the reader is looking at.
///
/// Photos whose location has no coordinates are not placed. Guessing a point
/// for a vague place name ("Bay Area") would put a pin somewhere the photo
/// was not taken, so those are counted and reported instead.
class PhotoMapView extends StatefulWidget {
  final List<PhotoPost> photos;
  final Function(String photoId)? onPhotoTap;

  const PhotoMapView({super.key, required this.photos, this.onPhotoTap});

  @override
  State<PhotoMapView> createState() => _PhotoMapViewState();
}

class _PhotoMapViewState extends State<PhotoMapView> {
  Set<Marker> _markers = {};
  bool _building = true;
  GoogleMapController? _controller;

  List<PhotoPost> get _mappable =>
      widget.photos.where((p) => p.location.hasCoordinates).toList();

  int get _unmappable => widget.photos.length - _mappable.length;

  @override
  void initState() {
    super.initState();
    _buildMarkers();
  }

  @override
  void didUpdateWidget(PhotoMapView old) {
    super.didUpdateWidget(old);
    if (old.photos != widget.photos) {
      _buildMarkers();
      // Switching location tab changes which points are on screen, so the
      // frame has to follow or the new pins can sit off the edge.
      final controller = _controller;
      if (controller != null) _fitToPins(controller);
    }
  }

  // No dispose of _controller here: the GoogleMap widget disposes its own
  // controller, and a second dispose fails an assertion on the web
  // ("Maps cannot be retrieved before calling buildView!") every time the
  // map is closed.

  Future<void> _buildMarkers() async {
    setState(() => _building = true);

    // Coordinates come from the location, not the camera, so every photo at
    // one place shares an identical point. Seventeen markers stacked on the
    // same pixel look like one and only the top is tappable, so build one
    // marker per distinct point and let its thumbnail be the best-liked photo
    // there.
    final groups = <String, List<PhotoPost>>{};
    for (final photo in _mappable) {
      final key = '${photo.location.latitude},${photo.location.longitude}';
      groups.putIfAbsent(key, () => <PhotoPost>[]).add(photo);
    }

    final reps = groups.values
        .map((g) => g.sortedByPopularity().first)
        .toList();

    Marker markerFor(PhotoPost photo, BitmapDescriptor icon) {
      final count =
          groups['${photo.location.latitude},${photo.location.longitude}']!
              .length;
      return Marker(
        markerId: MarkerId(photo.id),
        position: LatLng(photo.location.latitude!, photo.location.longitude!),
        icon: icon,
        // Tapping opens the photo's regular page rather than an info window,
        // which is what was asked for.
        onTap: () => widget.onPhotoTap?.call(photo.id),
        infoWindow: InfoWindow(
          title: photo.location.name,
          snippet: count == 1 ? '1 photo' : '$count photos here',
        ),
      );
    }

    // Place every pin straight away with a plain icon. These photos run to
    // 15MB apiece, so waiting for all the thumbnails would leave the map
    // blank for as long as the slowest download takes. Pins first, pictures
    // as they arrive.
    if (!mounted) return;
    setState(() {
      _markers = reps
          .map((p) => markerFor(p, BitmapDescriptor.defaultMarker))
          .toSet();
      _building = reps.isNotEmpty;
    });

    debugPrint(
      '[map] photos=${widget.photos.length} mappable=${_mappable.length} '
      'distinct places=${groups.length} pins=${reps.length}',
    );

    var pending = reps.length;
    for (final photo in reps) {
      // Not awaited in order: each thumbnail swaps itself in when ready.
      unawaited(
        PhotoPin.iconFor(photo.imageUrl).then((icon) {
          if (!mounted) return;
          setState(() {
            _markers = {
              for (final m in _markers)
                if (m.markerId.value == photo.id) markerFor(photo, icon) else m,
            };
            if (--pending == 0) _building = false;
          });
        }),
      );
    }
  }

  /// Every plotted point, which is what the camera has to frame.
  List<LatLng> get _points => _mappable
      .map((p) => LatLng(p.location.latitude!, p.location.longitude!))
      .toList();

  /// A first frame, replaced by [_fitToPins] as soon as the map exists.
  ///
  /// Counting distinct points is not a usable proxy for how far apart they
  /// are: eight photos taken along one museum path are eight distinct points
  /// spanning about thirty metres, and framing them like eight scattered
  /// places puts all eight on the same pixel. Only the real span can decide
  /// the zoom, so this centres the points and leaves the fitting to the
  /// controller.
  CameraPosition get _initialCamera {
    final pts = _points;
    if (pts.isEmpty) {
      return const CameraPosition(target: LatLng(37.77, -122.42), zoom: 9);
    }
    return CameraPosition(target: _boundsOf(pts).centre, zoom: 14);
  }

  /// The smallest real-world box ever handed to the camera fit.
  ///
  /// A cluster of photos taken minutes apart at one spot is routinely only
  /// tens of metres across. Framing a box that small verbatim still looked
  /// zoomed out in practice — `newLatLngBounds` only zooms in as far as the
  /// *box* demands, and a few tens of metres across a normal-sized map
  /// window is a smaller zoom step than it sounds like. Padding the box out
  /// to this floor whenever the real span is tighter than it asks Maps for
  /// the closest zoom it has at that spot, which is what actually spreads
  /// the thumbnails across the view instead of leaving them bunched in the
  /// middle of a much wider frame.
  static const _minSpanMetres = 50.0;

  ({LatLngBounds box, LatLng centre, double spanMetres}) _boundsOf(
    List<LatLng> pts,
  ) {
    final lats = pts.map((p) => p.latitude);
    final lngs = pts.map((p) => p.longitude);
    final minLat = lats.reduce(math.min);
    final maxLat = lats.reduce(math.max);
    final minLng = lngs.reduce(math.min);
    final maxLng = lngs.reduce(math.max);
    final centre = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);

    // Rough metres, which is all that is needed to tell "one spot" from
    // "several places". Longitude degrees shrink towards the poles.
    const degreeMetres = 111320.0;
    final dLat = (maxLat - minLat) * degreeMetres;
    final dLng =
        (maxLng - minLng) *
        degreeMetres *
        math.cos(centre.latitude * math.pi / 180);
    final span = math.max(dLat.abs(), dLng.abs());

    var sw = LatLng(minLat, minLng);
    var ne = LatLng(maxLat, maxLng);
    if (span < _minSpanMetres) {
      final halfDegLat = (_minSpanMetres / 2) / degreeMetres;
      final halfDegLng = halfDegLat / math.cos(centre.latitude * math.pi / 180);
      sw = LatLng(centre.latitude - halfDegLat, centre.longitude - halfDegLng);
      ne = LatLng(centre.latitude + halfDegLat, centre.longitude + halfDegLng);
    }

    return (
      box: LatLngBounds(southwest: sw, northeast: ne),
      centre: centre,
      spanMetres: span,
    );
  }

  /// Frames the pins against the map's real size.
  Future<void> _fitToPins(GoogleMapController controller) async {
    final pts = _points;
    if (pts.isEmpty) return;
    final b = _boundsOf(pts);

    // onMapCreated can fire a frame or two before the platform view has
    // actually finished laying out, during which moveCamera throws rather
    // than waiting. A few short, backed-off retries cover that race without
    // a fixed delay that would make the common, already-laid-out case feel
    // sluggish.
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        await controller.moveCamera(CameraUpdate.newLatLngBounds(b.box, 56));
        return;
      } catch (e) {
        if (attempt == 3) {
          debugPrint('[map] could not fit camera to pins after retries: $e');
          return; // The initial position is still a reasonable fallback.
        }
        await Future.delayed(Duration(milliseconds: 150 * (attempt + 1)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_mappable.isEmpty) {
      return _MapMessage(
        icon: Icons.location_off_outlined,
        title: 'No mapped photos here',
        detail: widget.photos.isEmpty
            ? 'There are no photos in the current view.'
            : 'None of the ${widget.photos.length} photos in view has a '
                  'precise location yet.',
      );
    }

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: _initialCamera,
          markers: _markers,
          myLocationButtonEnabled: false,
          mapToolbarEnabled: false,
          onMapCreated: (controller) {
            _controller = controller;
            _fitToPins(controller);
          },
        ),
        if (_building)
          const Positioned(
            top: 12,
            right: 12,
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ),
        if (_unmappable > 0)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Material(
              elevation: 2,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Text(
                  '$_unmappable of ${widget.photos.length} photos have no '
                  'precise location and are not shown.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MapMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;

  const _MapMessage({
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
