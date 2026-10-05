/// Decoding a model on an isolate, natively, with the ports that read its
/// sibling files back on the caller's — and in the browser, which has no
/// isolates, in place. Chosen at compile time so the browser's build imports
/// no `dart:isolate`: see `platform/background.dart`.
library;

export 'model_isolate_io.dart'
    if (dart.library.js_interop) 'model_isolate_web.dart';
