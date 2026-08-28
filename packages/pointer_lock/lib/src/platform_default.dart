/// The platform implementation this build gets, chosen at compile time.
///
/// A conditional export rather than a plugin registration, for the reason
/// `pad_input` gives at the same place: the difference is a fact about the
/// platform and not a choice anybody is making, and the web half is pure Dart —
/// `document.requestPointerLock` is the whole of it, so there is nothing for a
/// generated registrant to register. It also means a browser build has pointer
/// capture inside `flutter test --platform chrome`, where a registrant would
/// never run.
///
/// The two halves cannot live in one file: `dart:js_interop` does not compile
/// for macOS and `package:flutter/services.dart`'s channels are not what a
/// browser answers on.
library;

export 'platform_default_native.dart'
    if (dart.library.js_interop) 'platform_default_web.dart';
