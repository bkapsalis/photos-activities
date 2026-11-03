import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// A phone-sized photo stored landscape with an EXIF "rotate 90" tag — what a
/// portrait shot looks like on disk — and the GPS of
/// test/fixtures/gps_north_west.jpg (37°28'N, 122°18'W).
///
/// The EXIF is written by hand rather than through the `image` package:
/// exif_reader and Apple ImageIO accept that package's EXIF block, but
/// Android ExifInterface reports no rotation in it, so the Android codec
/// left the photo sideways. With this textbook layout it rotates correctly,
/// as it does for real camera files.
Uint8List portraitPhotoWithGps({int width = 4000, int height = 3000}) {
  final photo = img.Image(width: width, height: height);
  for (final p in photo) {
    // Texture, so the encoder does real work rather than compressing a blank.
    p
      ..r = (p.x * 7 + p.y * 3) % 256
      ..g = (p.x * p.y) % 256
      ..b = (p.y * 5) % 256;
  }
  final jpeg = img.encodeJpg(photo, quality: 95);
  final app1 = _exifApp1(orientation: 6);
  return Uint8List.fromList([
    ...jpeg.sublist(0, 2), // SOI
    ...app1,
    ...jpeg.sublist(2),
  ]);
}

/// Big-endian TIFF: IFD0 {Orientation, GPS pointer} -> GPS IFD
/// {LatRef, Lat, LonRef, Lon}, rationals after it.
Uint8List _exifApp1({required int orientation}) {
  final t = BytesBuilder();
  void u16(int v) => t.add([(v >> 8) & 0xFF, v & 0xFF]);
  void u32(int v) =>
      t.add([(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF]);
  void entry(int tag, int type, int count, void Function() value) {
    u16(tag);
    u16(type);
    u32(count);
    value();
  }

  const ifd0 = 8, gpsIfd = 38, latData = 92, lonData = 116;

  t.add('MM'.codeUnits);
  u16(0x2A);
  u32(ifd0);

  // IFD0 at 8: 2 entries.
  u16(2);
  entry(0x0112, 3, 1, () {
    u16(orientation);
    u16(0);
  });
  entry(0x8825, 4, 1, () => u32(gpsIfd));
  u32(0);

  // GPS IFD at 38: 4 entries.
  u16(4);
  entry(0x0001, 2, 2, () => t.add([0x4E, 0, 0, 0])); // 'N'
  entry(0x0002, 5, 3, () => u32(latData));
  entry(0x0003, 2, 2, () => t.add([0x57, 0, 0, 0])); // 'W'
  entry(0x0004, 5, 3, () => u32(lonData));
  u32(0);

  // Rationals at 92 and 116.
  for (final r in [37, 1, 28, 1, 5863, 500, 122, 1, 18, 1, 20433, 500]) {
    u32(r);
  }

  final tiff = t.toBytes();
  assert(tiff.length == lonData + 24);
  final length = 2 + 6 + tiff.length;
  return Uint8List.fromList([
    0xFF,
    0xE1,
    (length >> 8) & 0xFF,
    length & 0xFF,
    ...'Exif'.codeUnits,
    0,
    0,
    ...tiff,
  ]);
}
