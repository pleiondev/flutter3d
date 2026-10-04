/// The GPU passes: natively through wgpu-native, none in the browser — P9.
library;

export 'gpu_native.dart' if (dart.library.js_interop) 'gpu_web.dart';
