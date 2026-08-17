import 'gamepad_platform_interface.dart';

/// The gamepad a build outside the browser gets.
///
/// Nothing yet, and honestly nothing: [UnsupportedGamepad] answers "no pad,
/// ever" without opening a channel, so a game on a platform this package does
/// not serve behaves exactly as it did before the package existed.
///
/// macOS lands here, as a method channel over `GameController.framework`,
/// whitelisted to the platforms that have a native side. It is not written yet
/// for a reason recorded in the specification: **an earlier gamepad backend in
/// this repository was deleted rather than finished**, because one written
/// without a controller in hand is wrong in a way no test shows.
GamepadPlatform defaultGamepadPlatform() => UnsupportedGamepad();
