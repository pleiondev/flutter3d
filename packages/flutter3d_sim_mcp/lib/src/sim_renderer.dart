import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show WorldPosition;
import 'package:flutter3d_mcp/kit.dart' show ProjectRoot;
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'diagnostic_renderer.dart';

/// A picture of the room, drawn with no GPU — [SimSession.frame]'s other half.
///
/// **The diagnostic server's [DiagnosticRenderer], in its ordinary view.**
/// The two were one class written twice, down to the marker a level's asset
/// root is found by; a picture from the sim server is the renderer server's
/// `lit` frame, and a fix to how a level is loaded for one is a fix for both.
/// [registry] is the game's own, so the level spawns what that game spawns.
final class SimRenderer {
  SimRenderer._(this._frames);

  final DiagnosticRenderer _frames;

  static const int width = DiagnosticRenderer.width;
  static const int height = DiagnosticRenderer.height;

  static Future<SimRenderer> open(
    String levelPath, {
    required EntityRegistry registry,
    ProjectRoot? root,
  }) async => SimRenderer._(
    await DiagnosticRenderer.open(levelPath, registry: registry, root: root),
  );

  /// A PNG, looking from [at] — in the scene's own space — in the
  /// direction [aim] points.
  Future<Uint8List> frame({required Vector3 at, required Vector3 aim}) async =>
      (await _frames.frame(at: at, aim: aim)).png;

  /// A PNG, looking from [eye], a place in the world, in the direction [aim]
  /// points: [DiagnosticRenderer.frameFrom], which keeps the scene's origin
  /// near the eye.
  Future<Uint8List> frameFrom({
    required WorldPosition eye,
    required Vector3 aim,
  }) async => (await _frames.frameFrom(eye: eye, aim: aim)).png;
}
