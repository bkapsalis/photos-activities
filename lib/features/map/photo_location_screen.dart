import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/data/mock_data.dart';
import '../../core/models/models.dart';
import '../../core/services/analytics_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/directions.dart';
import '../home/feed_navigator.dart';
import 'photo_pin.dart';

/// Where one photo was taken: its thumbnail pinned on a map, inside the app.
///
/// Reached from a photo's page with [MapLocationButton]. From here the reader
/// can step back to the photo (the arrow at the top), go back to the feed of
/// the place the photo is from ("Back"), or hand the spot to the device's own
/// map app with [DirectionsButton] — the only step that leaves the app.
class PhotoLocationScreen extends StatelessWidget {
  final PhotoPost photo;

  const PhotoLocationScreen({super.key, required this.photo});

  /// Replaces the map in widget tests, which cannot host the native map view.
  @visibleForTesting
  static Widget Function(PhotoPost photo)? debugMapBuilder;

  static Future<void> open(BuildContext context, PhotoPost photo) {
    AnalyticsService.photoMapOpened(photo.location.name);
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PhotoLocationScreen(photo: photo),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final location = photo.location;
    final region = location.region?.trim() ?? '';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to photo',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              location.name,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
            if (region.isNotEmpty)
              Text(
                region,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: debugMapBuilder?.call(photo) ?? _PhotoPinMap(photo: photo),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              // Kept to a readable width on a wide browser window.
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'The pin shows where this photo was taken.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      DirectionsButton(photo: photo, prominent: true),
                      const SizedBox(height: 8),
                      // Back to the feed of the place this photo is from —
                      // its category and location tab — rather than one
                      // step back to the photo; the arrow at the top does that.
                      OutlinedButton.icon(
                        onPressed: () => FeedNavigator.showLocationOf(
                          context,
                          photo,
                          categories,
                        ),
                        icon: const Icon(Icons.arrow_back, size: 18),
                        label: const Text('Back'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The map itself: centred on the photo, with the photo as its pin.
class _PhotoPinMap extends StatefulWidget {
  final PhotoPost photo;

  const _PhotoPinMap({required this.photo});

  @override
  State<_PhotoPinMap> createState() => _PhotoPinMapState();
}

class _PhotoPinMapState extends State<_PhotoPinMap> {
  // A plain pin until the thumbnail has been drawn, so the spot shows at once.
  BitmapDescriptor _icon = BitmapDescriptor.defaultMarker;

  @override
  void initState() {
    super.initState();
    PhotoPin.iconFor(widget.photo.imageUrl).then((icon) {
      if (mounted) setState(() => _icon = icon);
    });
  }

  @override
  Widget build(BuildContext context) {
    final location = widget.photo.location;
    final spot = LatLng(location.latitude!, location.longitude!);
    return GoogleMap(
      // Street level: close enough to recognise the place, wide enough to
      // see how to get there.
      initialCameraPosition: CameraPosition(target: spot, zoom: 16),
      markers: {
        Marker(
          markerId: MarkerId(widget.photo.id),
          position: spot,
          icon: _icon,
          infoWindow: InfoWindow(title: location.name),
        ),
      },
      myLocationButtonEnabled: false,
      mapToolbarEnabled: false,
    );
  }
}

/// "Map Where Image Was Taken" on a photo's page.
///
/// A photo with no recorded location still shows the button, disabled with a
/// line saying why: when it simply vanished, people who had seen it on other
/// photos read its absence as the page being broken.
class MapLocationButton extends StatelessWidget {
  final PhotoPost photo;

  /// Filled rather than outlined. Used on web, where the photo modal has more
  /// competing controls than the mobile page and an outlined button recedes.
  final bool prominent;

  static const label = 'Map Where Image Was Taken';
  static const unavailableNote =
      "No location was recorded for this photo, so it can't be shown on a map.";

  const MapLocationButton({
    super.key,
    required this.photo,
    this.prominent = false,
  });

  @override
  Widget build(BuildContext context) {
    final available = photo.location.hasCoordinates;
    return _LocationActionButton(
      label: label,
      icon: Icons.map_outlined,
      prominent: prominent,
      onPressed: available
          ? () => PhotoLocationScreen.open(context, photo)
          : null,
      unavailableNote: available ? null : unavailableNote,
    );
  }
}

/// "Get Directions to Where the Picture Was Taken": hands the spot to the
/// device's own map app (see [Directions]) — the one step that leaves the app.
class DirectionsButton extends StatefulWidget {
  final PhotoPost photo;
  final bool prominent;

  static const label = 'Get Directions to Where the Picture Was Taken';
  static const unavailableNote =
      "No location was recorded for this photo, so directions aren't available.";

  const DirectionsButton({
    super.key,
    required this.photo,
    this.prominent = false,
  });

  @override
  State<DirectionsButton> createState() => _DirectionsButtonState();
}

class _DirectionsButtonState extends State<DirectionsButton> {
  bool _opening = false;

  Future<void> _go() async {
    AnalyticsService.directionsRequested(widget.photo.location.name);
    setState(() => _opening = true);
    final error = await Directions.toLocation(widget.photo.location);
    if (!mounted) return;
    setState(() => _opening = false);
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = widget.photo.location.hasCoordinates;
    return _LocationActionButton(
      label: DirectionsButton.label,
      icon: Icons.directions,
      prominent: widget.prominent,
      busy: _opening,
      onPressed: available && !_opening ? _go : null,
      unavailableNote: available ? null : DirectionsButton.unavailableNote,
    );
  }
}

/// The shape both location buttons share: full width, wrapping onto two
/// lines on a narrow phone rather than clipping, and — when the photo has no
/// location — disabled with [unavailableNote] beneath it.
class _LocationActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool prominent;
  final bool busy;
  final VoidCallback? onPressed;
  final String? unavailableNote;

  const _LocationActionButton({
    required this.label,
    required this.icon,
    required this.prominent,
    required this.onPressed,
    this.busy = false,
    this.unavailableNote,
  });

  @override
  Widget build(BuildContext context) {
    final iconWidget = busy
        ? SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: prominent ? Colors.white : null,
            ),
          )
        : Icon(icon, size: prominent ? 20 : 18);

    final Widget button = prominent
        ? FilledButton.icon(
            onPressed: onPressed,
            icon: iconWidget,
            label: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: iconWidget,
            label: Text(label, textAlign: TextAlign.center),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          );

    final note = unavailableNote;
    if (note == null) return button;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        button,
        const SizedBox(height: 6),
        Text(
          note,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
