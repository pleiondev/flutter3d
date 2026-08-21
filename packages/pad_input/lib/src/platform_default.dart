/// The platform implementation this build gets, chosen at compile time.
///
/// A conditional export rather than a plugin registration, and the case for it
/// is the same one `flutter3d`'s `packed_keys.dart` makes: the difference is a
/// fact about the platform rather than a choice anybody is making, and no fake
/// wants to stand here. It also means a browser build has a gamepad in
/// `flutter test --platform chrome`, where a generated plugin registrant would
/// never run.
///
/// The web implementation is pure Dart, so nothing needs registering for it. A
/// native one is a method channel and will need the usual plugin declaration in
/// `pubspec.yaml` as well; the choice of default is still made here.
library;

export 'platform_default_native.dart'
    if (dart.library.js_interop) 'platform_default_web.dart';
