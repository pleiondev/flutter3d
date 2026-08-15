/// Which backend this build draws through.
///
/// The engine talks to `flutter3d_graphics` and never to a graphics API, so an
/// application is the one place that picks. A conditional import rather than a
/// runtime branch, because the two backends pull in incompatible worlds:
/// `flutter_gpu` does not compile for the web and `dart:js_interop` does not
/// compile for macOS, so a file that imported both could target neither.
///
/// This file used to export the native backend unconditionally, with a comment
/// saying the conditional would come back when there was a web build. There is
/// one now.
library;

export 'backend_native.dart' if (dart.library.js_interop) 'backend_web.dart';
