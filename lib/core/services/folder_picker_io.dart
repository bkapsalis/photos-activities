import 'dart:typed_data';

/// Not reachable: `StorageService.pickFolderAndScanImages` checks `kIsWeb`
/// before ever calling into this facade, since Android and iOS have nothing
/// for it to do. Kept only so the conditional export in folder_picker.dart
/// has a non-web branch that compiles.
Future<List<({String name, Uint8List bytes})>> pickFolderImages({
  int limit = 50,
}) async {
  throw UnsupportedError(
    'pickFolderImages is web-only; use the multi-file picker instead.',
  );
}
