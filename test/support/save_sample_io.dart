import 'dart:io';
import 'dart:typed_data';

/// Writes [bytes] somewhere a person can open it and returns the path.
///
/// `flutter test` uninstalls the app when it finishes, taking its own temp
/// directory with it, so on the iOS simulator - which can write to the Mac's
/// disk - the sample goes to the Mac's temp directory instead.
String? saveSample(String name, Uint8List bytes) {
  final dir = Directory.systemTemp.path.contains('/CoreSimulator/')
      ? '/private/tmp'
      : Directory.systemTemp.path;
  final file = File('$dir/$name')..writeAsBytesSync(bytes);
  return file.path;
}
