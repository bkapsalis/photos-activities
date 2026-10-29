/// Picks every image inside a folder, including subfolders, through one
/// native dialog.
///
/// Web and Android. `package:file_picker`'s `getDirectoryPath()` only
/// hands back a path, which a browser has no use for and which an Android app
/// may not read photos through. So the web uses the browser's own `<input
/// webkitdirectory>`, and Android its folder browser
/// (ACTION_OPEN_DOCUMENT_TREE) through MainActivity. iOS is not offered a
/// folder: in its Files picker, Select then the photos does the same job.
///
/// See [platform_image_encoder.dart] for why this conditional-export facade
/// pattern is used instead of branching on `kIsWeb` inside one file.
library;

export 'folder_picker_io.dart'
    if (dart.library.js_interop) 'folder_picker_web.dart';
