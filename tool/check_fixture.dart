// A command-line EXIF dumper, used to verify the test fixtures parse the way
// the app's parser will read them. Printing is this tool's entire purpose.
// ignore_for_file: avoid_print

import 'dart:io';
import 'package:exif_reader/exif_reader.dart';

Future<void> main(List<String> args) async {
  final bytes = await File(args.first).readAsBytes();
  final exif = await readExifFromBytes(bytes);
  print('tags: ${exif.tags.length}  warnings: ${exif.warnings}');
  final names = exif.tags.keys.toList()..sort();
  for (final n in names) {
    print('  $n = ${exif.tags[n]!.printable}');
  }
}
