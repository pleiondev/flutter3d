import 'gamepad_method_channel.dart';
import 'gamepad_platform_interface.dart';

/// The gamepad a build outside the browser gets.
///
/// [MethodChannelGamepad], which answers honestly on the platforms it has no
/// native side for: its `isSupported` is a **whitelist** and it opens nothing
/// until somebody reads it. So a macOS build behaves exactly as it did before
/// this package existed, without a `MissingPluginException` to catch.
///
/// Android, macOS and iOS are written; Windows and Linux are not. The rule the
/// specification records — **an earlier gamepad backend here was deleted rather
/// than finished**, because one written without a controller in hand is wrong in
/// a way no test shows — was not waived for any of them. It was survived the same
/// way each time: every platform's difficulty is in *choosing* what a value
/// means, the choosing is in Dart and under test, and the native side forwards
/// and decides nothing.
GamepadPlatform defaultGamepadPlatform() => MethodChannelGamepad();
