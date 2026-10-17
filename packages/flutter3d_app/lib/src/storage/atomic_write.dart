/// Writing a document without the moment where it is half a document — see
/// `atomic_write_io.dart` for why.
///
/// **Chosen by platform, so a browser build of this package compiles.** There
/// is no filesystem in a browser, and `Storage` there is `localStorage`; the
/// web half refuses by name rather than leaving `dart:io` in the import graph
/// of a package that says it runs on the web.
library;

export 'atomic_write_io.dart'
    if (dart.library.js_interop) 'atomic_write_web.dart';
