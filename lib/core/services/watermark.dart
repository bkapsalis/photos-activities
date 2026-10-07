import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// The text stamped on an upload: the photographer's name with a copyright
/// sign. Null when there is no name to credit.
String? watermarkText(String photographer) {
  final name = photographer.trim();
  return name.isEmpty ? null : '© $name';
}

/// Size and inset of the stamp for an image whose shorter side is [shortSide]:
/// about 3.5% of it, so it reads the same on a portrait and a panorama, but
/// never so small it blurs into noise or so large it dominates.
({double fontSize, double margin}) watermarkMetrics(double shortSide) {
  final fontSize = (shortSide * 0.035).clamp(14.0, 64.0);
  return (fontSize: fontSize, margin: fontSize * 0.8);
}

/// Draws [text] into the bottom-right corner of an already-sized photo with
/// Flutter's own renderer, which works the same on Android, iOS and web and
/// shapes any script the platform fonts cover. Returns PNG bytes, since
/// dart:ui cannot encode JPEG; the caller re-encodes. Null on failure.
Future<Uint8List?> stampWithFlutter(Uint8List photo, String text) async {
  ui.Image? source;
  ui.Image? stamped;
  try {
    final codec = await ui.instantiateImageCodec(photo);
    source = (await codec.getNextFrame()).image;
    codec.dispose();

    final w = source.width, h = source.height;
    final (:fontSize, :margin) = watermarkMetrics(
      (w < h ? w : h).toDouble(),
    );

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..drawImage(source, ui.Offset.zero, ui.Paint());

    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              textAlign: ui.TextAlign.right,
              maxLines: 1,
              ellipsis: '…',
              fontSize: fontSize,
              fontWeight: ui.FontWeight.w600,
            ),
          )
          ..pushStyle(
            ui.TextStyle(
              // Semi-opaque white with a soft shadow reads on sky and on
              // shade alike without blotting out the corner of the picture.
              color: const ui.Color(0xD9FFFFFF),
              shadows: [
                ui.Shadow(
                  color: const ui.Color(0x99000000),
                  blurRadius: fontSize * 0.18,
                  offset: ui.Offset(0, fontSize * 0.06),
                ),
              ],
            ),
          )
          ..addText(text);
    // At most 60% of the width, so a long name is shortened rather than
    // running across the photo.
    final maxWidth = w * 0.6;
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: maxWidth));
    canvas.drawParagraph(
      paragraph,
      ui.Offset(w - margin - maxWidth, h - margin - paragraph.height),
    );

    stamped = await recorder.endRecording().toImage(w, h);
    final png = await stamped.toByteData(format: ui.ImageByteFormat.png);
    return png?.buffer.asUint8List();
  } catch (e) {
    debugPrint('[watermark] Flutter stamp failed: $e');
    return null;
  } finally {
    source?.dispose();
    stamped?.dispose();
  }
}

/// The pure-Dart fallback's stamp, for when the platform path failed. Uses
/// the `image` package's bitmap font: cruder, and limited to Latin-1, but it
/// runs anywhere, including in an isolate.
void stampWithImagePackage(img.Image photo, String text) {
  final shortSide = photo.width < photo.height ? photo.width : photo.height;
  final (:fontSize, :margin) = watermarkMetrics(shortSide.toDouble());
  final font = fontSize >= 36 ? img.arial48 : img.arial24;
  final inset = margin.round();
  final y = photo.height - inset - font.lineHeight;
  // With rightJustify, x is where the text ENDS.
  final right = photo.width - inset;
  // A dark copy one pixel down and right stands in for the shadow.
  img.drawString(
    photo,
    text,
    font: font,
    x: right + 1,
    y: y + 1,
    rightJustify: true,
    color: img.ColorRgba8(0, 0, 0, 150),
  );
  img.drawString(
    photo,
    text,
    font: font,
    x: right,
    y: y,
    rightJustify: true,
    color: img.ColorRgba8(255, 255, 255, 217),
  );
}
