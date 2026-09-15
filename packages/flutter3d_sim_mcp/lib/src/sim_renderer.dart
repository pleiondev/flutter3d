import 'dart:typed_data';

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'diagnostic_renderer.dart';

/// A picture of the room, drawn with no GPU — [SimSession.frame]'s other half.
///
/// **[DiagnosticRenderer], in its ordinary view.** The two were one class
/// written twice, down to the marker a level's asset root is found by, back
/// when they lived in separate packages — a picture from `frame` is
/// `diagFrame`'s own `lit` view, and a fix to how a level is loaded for one
/// is a fix for both. [registry] is the game's own, so the level spawns
/// what that game spawns; `DiagnosticSession`'s own `diagOpen` spawns
/// nothing, which is the one way these two still differ.
final class SimRenderer {
  SimRenderer._(this._frames);

  final DiagnosticRenderer _frames;

  static const int width = DiagnosticRenderer.width;
  static const int height = DiagnosticRenderer.height;

  static Future<SimRenderer> open(
    String levelPath, {
    required EntityRegistry registry,
  }) async => SimRenderer._(
    await DiagnosticRenderer.open(levelPath, registry: registry),
  );

  /// A PNG, looking from [at] in the direction [aim] points.
  Future<Uint8List> frame({required Vector3 at, required Vector3 aim}) async =>
      (await _frames.frame(at: at, aim: aim)).png;
}
