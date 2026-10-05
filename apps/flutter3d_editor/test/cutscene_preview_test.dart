/// A cutscene's camera played in the editor's viewport.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart'
    show CameraNode, PerspectiveProjection;
import 'package:flutter3d_editor/src/cutscene_preview.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show Sequence;
import 'package:flutter_test/flutter_test.dart';

Sequence _scene() => Sequence.read(<String, Object?>{
  'seconds': 2,
  'camera': <String, Object?>{
    'keys': <Object?>[
      <String, Object?>{
        't': 0,
        'at': <double>[0, 2, 0],
        'look': <double>[0, 2, -5],
      },
      <String, Object?>{
        't': 2,
        'at': <double>[10, 2, 0],
        'look': <double>[10, 2, -5],
        'fov': 30,
      },
    ],
  },
}, stepsPerSecond: 60).sequence!;

void main() {
  test('the camera is on each key at its time, with its field of view', () {
    final preview = CutscenePreview(_scene());
    final camera = CameraNode(name: 'editor');
    expect(preview.seconds, 2.0);

    expect(preview.placeOn(camera, 0.0), isTrue);
    expect(camera.worldMatrix.getTranslation().x, closeTo(0.0, 1e-9));
    expect(
      (camera.projection as PerspectiveProjection).fovYRadians,
      closeTo(45 * math.pi / 180, 1e-9),
    );
    // Halfway in time is halfway along: one speed between two keys.
    // Mutation: reading the time as steps, which leaves it at the start.
    preview.placeOn(camera, 1.0);
    expect(camera.worldMatrix.getTranslation().x, closeTo(5.0, 1e-6));

    // Over, and left on the last key.
    expect(preview.placeOn(camera, 2.0), isFalse);
    expect(camera.worldMatrix.getTranslation().x, closeTo(10.0, 1e-9));
    expect(
      (camera.projection as PerspectiveProjection).fovYRadians,
      closeTo(30 * math.pi / 180, 1e-9),
    );
  });
}
