/// Where the photos for an upload come from: the two choices on the
/// "Upload Image or Images" screen, on each platform.
///
/// | | Photos on this device | Photos from the Cloud |
/// |---|---|---|
/// | Android | a folder, from the top of the phone's storage | Google Drive, in the document picker |
/// | iPhone | the Photos library | a folder in Files: iCloud Drive, or Google Drive's if installed |
/// | web | a folder on the computer | Google Drive, in Google's own picker |
///
/// A chosen folder comes back whole, newest first, with nothing ticked, for
/// the upload screen to offer Select all or a tap on each photo wanted.
/// Where only single photos can be handed over — Google Drive, which gives
/// apps no folder's contents, and the Photos library — they come back
/// ticked, chosen in the picker already.
///
/// Every photo comes back as a preview plus a way to read it in full, which
/// happens only for those uploaded; see PickedImage.
///
/// See [platform_image_encoder.dart] for why this conditional-export facade
/// pattern is used instead of branching on `kIsWeb` inside one file.
library;

export 'photo_pickers_io.dart'
    if (dart.library.js_interop) 'photo_pickers_web.dart';
