/// An XR runtime for tests, with no headset behind it.
///
///     import 'package:flutter3d_app/xr_testing.dart';
///
/// A second entry point, as `flutter3d_hardware/testing.dart` is one: a
/// fake is for a test, and an application that imports the main barrel
/// should not find it there. [FakeXrSession] drives every part of the XR
/// contract (capabilities and their refusals, frames with poses, controls,
/// planes, light and depth, a swapchain, anchors and haptics), and a test
/// reads back what the engine ended each frame with.
library;

export 'src/xr/fake_xr_session.dart';
