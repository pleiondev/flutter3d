import 'package:flutter3d_graphics/flutter3d_graphics.dart';

import '../engine_shaders.dart';
import 'webgl_device.dart';

/// Opens this backend with the engine's own shaders, or throws with something
/// worth putting on screen.
///
/// **Three applications had written this out**, identically, down to the
/// wording of the error — which is the wrong place for it: what a browser has
/// to provide is this package's knowledge, not a game's, and a game repeating
/// it is a game that will still be naming `EXT_color_buffer_float` on the day
/// this backend stops needing it.
///
/// What stays with the caller is the size, because the size is a budget: every
/// pixel here is blitted to a canvas the browser then scales, so one demo
/// renders at 720p and another — heavier, and honest about it — at 960×540.
/// That is a decision about a particular game, and this package has no way to
/// make it.
///
/// Throws a [StateError] rather than returning null. A browser without WebGL2
/// is not a case a game can carry on from, and the three copies all had to
/// invent the same sentence to say so.
Future<GraphicsDevice> openWebGl({
  required int width,
  required int height,
}) async {
  final device = WebGlDevice.create(
    width: width,
    height: height,
    // GLSL ES 3.00, translated from `flutter3d_shaders` by
    // `tool/generate_shaders.dart`. There is no compiled bundle on this
    // backend: a browser compiles GLSL itself, so a "bundle" is a map from the
    // engine's entry point names to source text.
    sources: engineShaders,
  );
  if (device == null) {
    throw StateError(
      'WebGL2 is not available in this browser. The engine needs WebGL2 '
      '(not WebGL1) and EXT_color_buffer_float for its HDR target.',
    );
  }
  return device;
}
