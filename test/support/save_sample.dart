// Lets the device check leave its stamped output where a person can look at
// it, without pulling dart:io into the browser build of the same check.
export 'save_sample_io.dart'
    if (dart.library.js_interop) 'save_sample_web.dart';
