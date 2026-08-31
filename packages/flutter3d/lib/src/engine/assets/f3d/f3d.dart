/// The `.f3d` container: an offline-converted model that loads without parsing.
///
/// Depends on neither a graphics backend nor `dart:ui`, like the other decoders, so it
/// works from an isolate and from an ahead-of-time compiled tool.
library;

export 'f3d_format.dart';
export 'f3d_loader.dart';
export 'f3d_writer.dart';
