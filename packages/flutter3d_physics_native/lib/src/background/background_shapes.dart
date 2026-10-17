/// A liquid's shapes worked out on another isolate: natively a long-lived
/// isolate, in the browser, which has none, at once.
library;

export 'background_shapes_isolate.dart'
    if (dart.library.js_interop) 'background_shapes_web.dart';
