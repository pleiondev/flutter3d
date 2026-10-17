/// The physics core as the Dart side reaches it, natively and in the
/// browser: its calls, its constants, its structs' layouts and its memory —
/// P9, phase 12.
library;

export 'buffers.dart';
export 'calls_native.g.dart' if (dart.library.js_interop) 'calls_web.g.dart';
export 'constants.dart';
export 'layout.g.dart';
export 'memory.dart';
