/// The core's memory: natively through dart:ffi, in the browser the
/// WebAssembly module's — P9, phase 12.
library;

export 'memory_native.dart' if (dart.library.js_interop) 'memory_web.dart';
