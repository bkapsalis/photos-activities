import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'media_location_access.dart';

const _channel = MethodChannel('bills_bay_area/folder_picker');

/// Opens Android's folder browser and reads back every image inside the
/// chosen folder and its subfolders, at most [limit]; empty if no folder was
/// chosen. MainActivity does the reading.
///
/// iOS has no route here: its Files picker's Select takes a folder's photos
/// instead, so `uploadSourcesFor` never offers a folder there.
Future<List<({String name, Uint8List bytes})>> pickFolderImages({
  int limit = 50,
}) async {
  if (defaultTargetPlatform != TargetPlatform.android) {
    throw UnsupportedError('Picking a whole folder is web and Android only.');
  }
  // Without this Android blanks the GPS out of every photo it hands over.
  await MediaLocationAccess.ensure();
  final images = await _channel.invokeListMethod<Map<Object?, Object?>>(
    'pickFolderImages',
    {'limit': limit},
  );
  return [
    for (final image in images ?? const <Map<Object?, Object?>>[])
      (name: image['name']! as String, bytes: image['bytes']! as Uint8List),
  ];
}
