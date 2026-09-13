/// A model fetched from an address rather than picked from a folder.
///
/// What the models service needs from this application: the page that embeds
/// the web build names a file, and the build opens it through the same
/// `openBytes` a picked file goes through.
library;

export 'fetch_model_io.dart' if (dart.library.js_interop) 'fetch_model_web.dart';
