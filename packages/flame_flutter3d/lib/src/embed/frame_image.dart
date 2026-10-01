/// A finished frame as a `ui.Image`, where the backend can hand one over
/// without copying it; null where it cannot, and the pixels have to be read
/// back instead.
///
/// **A conditional import, because only the native half can name the type.**
/// Impeller's texture becomes an image through `flutter_gpu`, which a web
/// build cannot compile; the web half answers null for every device and the
/// caller reads the frame back.
library;

export 'frame_image_web.dart' if (dart.library.io) 'frame_image_native.dart';
