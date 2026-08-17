import 'gamepad_method_channel.dart';
import 'gamepad_platform_interface.dart';

/// The gamepad a build outside the browser gets.
///
/// [MethodChannelGamepad], which answers honestly on the platforms it has no
/// native side for: its `isSupported` is a **whitelist** and it opens nothing
/// until somebody reads it. So a macOS build behaves exactly as it did before
/// this package existed, without a `MissingPluginException` to catch.
///
/// Android is written. macOS and iOS are not, and the reason is recorded in the
/// specification: **an earlier gamepad backend here was deleted rather than
/// finished**, because one written without a controller in hand is wrong in a way
/// no test shows. What made Android possible anyway is that its whole difficulty
/// is in *choosing* — which axis is a trigger, whether the d-pad is a hat — and
/// the choosing is in Dart, under test, with the Kotlin side forwarding raw
/// events and deciding nothing.
GamepadPlatform defaultGamepadPlatform() => MethodChannelGamepad();
