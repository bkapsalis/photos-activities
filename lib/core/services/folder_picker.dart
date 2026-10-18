/// Picks every image inside a folder, including subfolders, through one
/// native dialog.
///
/// Web only. `package:file_picker`'s `getDirectoryPath()` has no Android,
/// iOS or web implementation at all — it is wired up for macOS, Windows and
/// Linux only, none of which this app ships to, so calling it there always
/// throws `UnimplementedError`. That is the bug this file exists to route
/// around: the browser's own `<input webkitdirectory>` gives real recursive
/// folder access, so web gets a genuine implementation here. Android and iOS
/// have no comparable API, so `StorageService.pickFolderAndScanImages` falls
/// back to the ordinary multi-file picker there instead of calling this —
/// which is also how someone actually selects "everything in a folder" on
/// those platforms: navigate into it, then select all.
///
/// See [platform_image_encoder.dart] for why this conditional-export facade
/// pattern is used instead of branching on `kIsWeb` inside one file.
library;

export 'folder_picker_io.dart' if (dart.library.js_interop) 'folder_picker_web.dart';
