/// WebGL2 as an implementation of `flutter3d_hardware`.
///
/// The second backend. Its value is not only that it runs on the web: it is the
/// first thing that can tell us whether the HAL is a seam or a description of
/// Impeller, because a fake backend can only confirm that an interface is
/// callable, never that it is implementable.
///
/// **Status: it draws the engine's scenes.** The engine names its stages —
/// `LightingModel.shaderName` and the renderer's `require` calls — and every
/// backend must ship a set answering to those names. This one's are generated:
/// `tool/generate_shaders.dart` translates `flutter3d_shaders` into GLSL ES
/// 3.00 and writes `engine_shaders.dart`, which `tool/ci.sh` regenerates and
/// diffs, because a table nobody diffed once held a sky from before the sky
/// was rewritten.
///
/// What it draws is measured rather than asserted. Every golden scene is
/// recorded here as well, and `test/cross_backend_test.dart` holds each one to
/// its own measured distance from the picture Impeller recorded — a budget per
/// scene rather than one tolerance over all of them, because a tolerance wide
/// enough for the worst scene stops watching the rest.
///
/// This paragraph said the opposite for as long as the shaders took to write,
/// which is the trap a status line sets: it is the first thing a reader of the
/// package sees, on pub.dev and in the IDE, and nothing fails when it goes out
/// of date.
library;

export 'src/open.dart';

/// The `webgl` section of a loadable bundle, as the packer writes it and the
/// device reads it. No browser in it, so a harness on the VM can write one.
export 'src/webgl_bundle_section.dart';
export 'src/webgl_device.dart';
export 'src/webgl_shaders.dart';
