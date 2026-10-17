/// The file system, where there is one: `dart:io` natively, and in the
/// browser a refusal that says why — chosen at compile time, so the browser's
/// build imports no `dart:io`, which pub.dev reads as "not for the web".
library;

export 'files_io.dart' if (dart.library.js_interop) 'files_web.dart';
