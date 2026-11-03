// Generates an unmistakable image for the EXIF probe, so the tester can never
// confuse it with a real photo in the library.
// ignore_for_file: avoid_print
import 'dart:io';
import 'package:image/image.dart' as img;

void main(List<String> args) {
  final im = img.Image(width: 1200, height: 800);
  // Solid magenta - nothing in this library looks remotely like it.
  img.fill(im, color: img.ColorRgb8(255, 0, 170));
  // Big white bars, readable at thumbnail size.
  for (var i = 0; i < 5; i++) {
    img.fillRect(
      im,
      x1: 120 + i * 200,
      y1: 150,
      x2: 220 + i * 200,
      y2: 650,
      color: img.ColorRgb8(255, 255, 255),
    );
  }
  File(args.first).writeAsBytesSync(img.encodeJpg(im, quality: 92));
  print('wrote ${args.first}');
}
