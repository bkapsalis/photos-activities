import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Where a photo's coordinates came from.
enum LocationSource {
  /// Read from the file's own EXIF GPS tags.
  exif,

  /// Typed or picked by a person.
  manual,

  /// Derived from the place name rather than the photo.
  geocoded,

  /// Where the phone was when the photo was taken in the app, because the
  /// camera recorded no location of its own.
  device,

  /// No coordinates.
  none;

  static LocationSource parse(String? value) => LocationSource.values.firstWhere(
    (s) => s.name == value,
    orElse: () => LocationSource.none,
  );
}

/// What a photo's original file said about itself.
///
/// Every field is optional. Cameras disagree about which tags they write, a
/// re-encoded file may carry none of them, and a browser may hand over an
/// image with no metadata at all — so a missing field is the normal case and
/// must never stop an upload.
@immutable
class PhotoMetadata {
  final double? latitude;
  final double? longitude;
  final double? altitude;
  final DateTime? takenAt;
  final String? cameraMake;
  final String? cameraModel;
  final int? orientation;
  final int? originalWidth;
  final int? originalHeight;
  final LocationSource locationSource;

  const PhotoMetadata({
    this.latitude,
    this.longitude,
    this.altitude,
    this.takenAt,
    this.cameraMake,
    this.cameraModel,
    this.orientation,
    this.originalWidth,
    this.originalHeight,
    this.locationSource = LocationSource.none,
  });

  static const empty = PhotoMetadata();

  /// True only when there is a usable pair to put on a map.
  bool get hasLocation => latitude != null && longitude != null;

  /// True when the file described itself at all, location aside.
  bool get isEmpty =>
      !hasLocation &&
      takenAt == null &&
      cameraMake == null &&
      cameraModel == null &&
      orientation == null &&
      originalWidth == null &&
      originalHeight == null;

  /// Fills in dimensions the EXIF did not carry, from the decoded image.
  ///
  /// EXIF dimension tags are frequently absent even when the rest is present,
  /// and the upload already decodes the image to measure its aspect ratio, so
  /// the real size is free at that point.
  PhotoMetadata withFallbackSize(int width, int height) {
    if (originalWidth != null && originalHeight != null) return this;
    return copyWith(
      originalWidth: originalWidth ?? width,
      originalHeight: originalHeight ?? height,
    );
  }

  PhotoMetadata copyWith({
    double? latitude,
    double? longitude,
    double? altitude,
    DateTime? takenAt,
    String? cameraMake,
    String? cameraModel,
    int? orientation,
    int? originalWidth,
    int? originalHeight,
    LocationSource? locationSource,
  }) {
    return PhotoMetadata(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitude: altitude ?? this.altitude,
      takenAt: takenAt ?? this.takenAt,
      cameraMake: cameraMake ?? this.cameraMake,
      cameraModel: cameraModel ?? this.cameraModel,
      orientation: orientation ?? this.orientation,
      originalWidth: originalWidth ?? this.originalWidth,
      originalHeight: originalHeight ?? this.originalHeight,
      locationSource: locationSource ?? this.locationSource,
    );
  }

  /// Fills in [latitude]/[longitude] as where the device was, but only when
  /// the photo carried no location of its own: GPS the camera wrote into the
  /// file always wins over the phone's position at upload time.
  PhotoMetadata withDeviceLocation(double latitude, double longitude) {
    if (hasLocation) return this;
    return copyWith(
      latitude: latitude,
      longitude: longitude,
      locationSource: LocationSource.device,
    );
  }

  /// Coordinates rounded to roughly 110m, for sharing a neighbourhood rather
  /// than a doorstep.
  ///
  /// The rounding is applied before the value is stored, never at display
  /// time: the photo document is world-readable, so anything written exactly
  /// is public exactly.
  PhotoMetadata roundedToApproximate() {
    if (!hasLocation) return this;
    double r(double v) => (v * 1000).roundToDouble() / 1000;
    return copyWith(latitude: r(latitude!), longitude: r(longitude!));
  }

  /// Drops the location entirely, keeping the rest.
  PhotoMetadata withoutLocation() => PhotoMetadata(
    altitude: altitude,
    takenAt: takenAt,
    cameraMake: cameraMake,
    cameraModel: cameraModel,
    orientation: orientation,
    originalWidth: originalWidth,
    originalHeight: originalHeight,
    locationSource: LocationSource.none,
  );

  Map<String, dynamic> toFirestore() => {
    'gps': hasLocation ? GeoPoint(latitude!, longitude!) : null,
    'hasLocation': hasLocation,
    'altitude': altitude,
    'takenAt': takenAt == null ? null : Timestamp.fromDate(takenAt!),
    'cameraMake': cameraMake,
    'cameraModel': cameraModel,
    'orientation': orientation,
    'originalWidth': originalWidth,
    'originalHeight': originalHeight,
    'locationSource': locationSource.name,
  };

  factory PhotoMetadata.fromFirestore(Map<String, dynamic>? data) {
    if (data == null) return empty;
    final gps = data['gps'];
    return PhotoMetadata(
      latitude: gps is GeoPoint ? gps.latitude : null,
      longitude: gps is GeoPoint ? gps.longitude : null,
      altitude: (data['altitude'] as num?)?.toDouble(),
      takenAt: data['takenAt'] is Timestamp
          ? (data['takenAt'] as Timestamp).toDate()
          : null,
      cameraMake: data['cameraMake'] as String?,
      cameraModel: data['cameraModel'] as String?,
      orientation: (data['orientation'] as num?)?.toInt(),
      originalWidth: (data['originalWidth'] as num?)?.toInt(),
      originalHeight: (data['originalHeight'] as num?)?.toInt(),
      locationSource: LocationSource.parse(data['locationSource'] as String?),
    );
  }
}
