/// Work run off the calling isolate where there are isolates, and in place
/// in the browser, which has none.
///
/// Chosen at compile time rather than by a constant beside an `Isolate.run`,
/// so that the browser's build imports no `dart:isolate` at all: pub.dev reads
/// an unconditional import of it, stub or not, as "not for the web", and
/// listed the whole engine without the web while it ran there.
library;

export 'background_io.dart' if (dart.library.js_interop) 'background_web.dart';
