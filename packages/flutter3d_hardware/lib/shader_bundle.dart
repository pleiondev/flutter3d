/// The shader bundle container on its own, for a tool that runs on plain Dart.
///
/// `flutter3d_hardware.dart` reaches `package:flutter` through
/// `GraphicsDevice`, and a program that packs a bundle — `flutter3d_webgl`'s
/// `tool/pack_shaders.dart` — is a `dart run` script that has no `dart:ui`
/// to give it. The container names no graphics API and no Flutter, so it is
/// exported alone here, the way `testing.dart` is a second entry point for a
/// second kind of consumer. An application loading a bundle wants the whole
/// library and the device with it; this is for the thing that writes one.
library;

export 'src/shader_bundle.dart';
