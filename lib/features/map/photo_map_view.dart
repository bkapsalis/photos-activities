import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/models/models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/photo_sorting.dart';

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
  /// Thumbnail bytes keyed by image URL, so panning and rebuilding never
  /// re-downloads a picture that has already been drawn.
  static final Map<String, BitmapDescriptor> _iconCache = {};

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

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

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
        _thumbnailFor(photo.imageUrl).then((icon) {
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

  /// Resolves an image through Flutter's own image pipeline and draws it as
  /// a small rounded square with a white border, which reads clearly against
  /// map tiles at pin size.
  ///
  /// This deliberately uses [NetworkImage] rather than a separate HTTP client:
  /// the photo grid already loads these same URLs successfully, so this reuses
  /// a path that is known to work, and hits Flutter's image cache so a picture
  /// already on screen costs no second download.
  Future<BitmapDescriptor> _thumbnailFor(String url) async {
    final cached = _iconCache[url];
    if (cached != null) return cached;

    try {
      // Decode at roughly pin size. The full file still downloads, but a
      // 15MB photo is never expanded to full resolution in memory.
      final source = await _resolve(url).timeout(const Duration(seconds: 60));

      const size = 120.0;
      const border = 6.0;
      const inner = size - border * 2;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final rect = const Rect.fromLTWH(0, 0, size, size);

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(18)),
        Paint()..color = Colors.white,
      );
      canvas.save();
      canvas.clipRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(border, border, inner, inner),
          const Radius.circular(12),
        ),
      );
      // Centre-crop rather than squash: photos are rarely square.
      final side = source.width < source.height
          ? source.width.toDouble()
          : source.height.toDouble();
      canvas.drawImageRect(
        source,
        Rect.fromLTWH(
          (source.width - side) / 2,
          (source.height - side) / 2,
          side,
          side,
        ),
        const Rect.fromLTWH(border, border, inner, inner),
        Paint()..filterQuality = FilterQuality.medium,
      );
      canvas.restore();

      final picture = recorder.endRecording();
      final rendered = await picture.toImage(size.round(), size.round());
      final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return BitmapDescriptor.defaultMarker;

      // An explicit logical size keeps the pin the same on every device;
      // without it the plugin scales by the device pixel ratio.
      final icon = BitmapDescriptor.bytes(
        bytes.buffer.asUint8List(),
        width: 56,
        height: 56,
      );
      _iconCache[url] = icon;
      return icon;
    } catch (e) {
      // A thumbnail that will not load should still leave a usable pin.
      debugPrint('[map] thumbnail failed for $url: $e');
      return BitmapDescriptor.defaultMarker;
    }
  }

  /// Bridges an [ImageProvider]'s listener callbacks into a Future.
  Future<ui.Image> _resolve(String url) {
    final completer = Completer<ui.Image>();
    final stream = ResizeImage(
      NetworkImage(url),
      width: 240,
      policy: ResizeImagePolicy.fit,
    ).resolve(ImageConfiguration.empty);
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.complete(info.image);
      },
      onError: (error, stack) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.completeError(error);
      },
    );
    stream.addListener(listener);
    return completer.future;
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
        (maxLng - minLng) * degreeMetres * math.cos(centre.latitude * math.pi / 180);
    final span = math.max(dLat.abs(), dLng.abs());

    return (
      box: LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      ),
      centre: centre,
      spanMetres: span,
    );
  }

  /// Frames the pins against the map's real size.
  ///
  /// [CameraUpdate.newLatLngBounds] cannot frame a zero-sized box, and a box
  /// only metres across would zoom past the deepest tile, so anything tighter
  /// than [_tightSpan] gets a fixed close zoom instead.
  static const _tightSpan = 60.0;

  Future<void> _fitToPins(GoogleMapController controller) async {
    final pts = _points;
    if (pts.isEmpty) return;
    final b = _boundsOf(pts);
    try {
      if (b.spanMetres < _tightSpan) {
        await controller.moveCamera(CameraUpdate.newLatLngZoom(b.centre, 17));
      } else {
        await controller.moveCamera(CameraUpdate.newLatLngBounds(b.box, 56));
      }
    } catch (_) {
      // A camera move can fail if the map is not laid out yet. The initial
      // position is still a reasonable view, so this is not worth surfacing.
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
