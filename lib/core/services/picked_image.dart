import 'dart:ui' show Codec, ImmutableBuffer;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// A photo offered for upload, and whether it is ticked to go.
///
/// Shown from [preview], small; read in full by [read] only if it is
/// uploaded. A folder can hold hundreds of photos, and reading every one in
/// full just to show it would take minutes and more memory than a phone has.
class PickedImage {
  final String name;

  /// What the grid shows, or null to show a placeholder.
  final ImageProvider? preview;

  final Future<Uint8List> Function() _read;

  bool selected;

  PickedImage({
    required this.name,
    required this.preview,
    required Future<Uint8List> Function() read,
    this.selected = true,
  }) : _read = read;

  /// A photo already in memory.
  factory PickedImage.bytes({
    required String name,
    required Uint8List bytes,
    bool selected = true,
  }) {
    return PickedImage(
      name: name,
      preview: ResizeImage(MemoryImage(bytes), width: previewWidth),
      read: () async => bytes,
      selected: selected,
    );
  }

  /// Width the previews are decoded at: three columns of them, sharp on a
  /// high-density screen.
  static const previewWidth = 240;

  /// The photo in full, as it was picked: metadata and all.
  Future<Uint8List> read() => _read();
}

/// An image whose bytes come from [load] when it is first shown: a preview
/// fetched from the platform for each photo only as it scrolls into view.
///
/// Two of these are the same image when their [key]s match, so a preview is
/// fetched once however often its tile rebuilds.
@immutable
class LazyBytesImage extends ImageProvider<LazyBytesImage> {
  final String key;
  final Future<Uint8List?> Function() load;

  const LazyBytesImage(this.key, this.load);

  @override
  Future<LazyBytesImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    LazyBytesImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _decode(decode),
      scale: 1,
      debugLabel: key.key,
    );
  }

  Future<Codec> _decode(ImageDecoderCallback decode) async {
    final bytes = await load();
    if (bytes == null || bytes.isEmpty) {
      throw StateError('No preview for $key');
    }
    return decode(await ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) => other is LazyBytesImage && other.key == key;

  @override
  int get hashCode => key.hashCode;
}
