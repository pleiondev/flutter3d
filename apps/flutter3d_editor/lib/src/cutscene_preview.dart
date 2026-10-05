import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart'
    show CameraNode, PerspectiveProjection;
import 'package:flutter3d_sim/flutter3d_sim.dart' show Sequence;
import 'package:vector_math/vector_math.dart';

/// A cutscene's camera path played in the editor's viewport: the camera put
/// where the game will put it, at the time the wall clock says, until the
/// scene is over.
///
/// Only the camera. Subtitles, fades and actors are the game's, and a level
/// open in the editor has no actors running; the path is what an author
/// cannot see by reading the document.
final class CutscenePreview {
  CutscenePreview(this.sequence)
    : assert(sequence.hasCamera, 'a scene with no camera has nothing to show');

  final Sequence sequence;

  final Vector3 _at = Vector3.zero();
  final Vector3 _look = Vector3.zero();

  /// How long the scene runs, in seconds.
  double get seconds => sequence.steps / sequence.stepsPerSecond;

  /// Puts [camera] where the scene has it [seconds] in, and answers whether
  /// the scene is still running — false once it is over, with the camera
  /// left on the last key.
  bool placeOn(CameraNode camera, double seconds) {
    final step = seconds * sequence.stepsPerSecond;
    final fov = sequence.cameraAt(step, _at, _look);
    camera
      ..setPosition(_at.x, _at.y, _at.z)
      ..lookAt(_look, up: Vector3(0.0, 1.0, 0.0))
      ..projection = PerspectiveProjection(fovYRadians: fov * math.pi / 180.0);
    return seconds < this.seconds;
  }
}
