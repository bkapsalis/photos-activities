import 'dart:typed_data';

import 'package:file/memory.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Serves every image URL from memory, so CachedNetworkImage runs in a widget
/// test with no network, no path_provider and no sqflite.
///
/// Install it as `CachedNetworkImageProvider.defaultCacheManager` before
/// pumping. URLs in [failingUrls] fail the way an unreachable photo would.
class FakeCacheManager extends Fake implements BaseCacheManager {
  FakeCacheManager({this.failingUrls = const {}});

  final Set<String> failingUrls;
  final requested = <String>[];
  final _fs = MemoryFileSystem();

  static final Uint8List _png = Uint8List.fromList(
    img.encodePng(img.Image(width: 4, height: 3)),
  );

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) {
    requested.add(url);
    if (failingUrls.contains(url)) {
      return Stream.error(Exception('404 for $url'));
    }
    final file = _fs.file('/${requested.length}.png')..writeAsBytesSync(_png);
    return Stream.value(FileInfo(file, FileSource.Online, DateTime(2100), url));
  }

  @override
  Future<void> removeFile(String key) async {}
}
