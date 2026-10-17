/// Root motion, end to end — N1: a walk cycle's own stride, taken out of
/// the pose by the animation graph, carried into the world by the model's
/// matrix, and walked by a character controller on the fixed step.
///
///     flutter test test/root_motion_test.dart
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

/// A walk whose root goes 1.5 along the pose's +z a second.
AnimationGraph _walking() => AnimationGraph(
  machine: AnimationStateMachine(
    parameters: AnimationParameterSchema(const <AnimationParameter>[]),
    entry: 'walk',
    states: const <AnimationState>[AnimationState(name: 'walk', clip: 'walk')],
    transitions: const <AnimationTransition>[],
  ),
  clips: <AnimationClip>[
    AnimationClip(
      name: 'walk',
      tracks: <AnimationTrack>[
        AnimationTrack(
          nodeIndex: 0,
          path: AnimationPath.translation,
          interpolation: AnimationInterpolation.linear,
          times: Float32List.fromList(<double>[0.0, 1.0]),
          values: Float32List.fromList(<double>[0, 0, 0, 0, 0, 1.5]),
          componentCount: 3,
        ),
      ],
    ),
  ],
  pose: AnimationPose(
    parents: const <int>[-1],
    restTranslations: Float32List(3),
    restRotations: Float32List.fromList(<double>[0, 0, 0, 1]),
    restScales: Float32List.fromList(<double>[1, 1, 1]),
  ),
)..rootNode = 0;

/// The model turned a quarter round to face +x and drawn twice its size.
final Matrix4 _model = Matrix4.compose(
  Vector3.zero(),
  Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), math.pi / 2),
  Vector3.all(2.0),
);

void main() {
  test('the stride, turned and scaled into the world, walks the body', () {
    final world = CollisionWorld()
      ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0));
    final body = CharacterController(
      world: world,
      position: Vector3(0.0, 0.9, 0.0),
    );
    final graph = _walking();
    for (var i = 0; i < 60; i++) {
      graph.evaluate(_dt);
      body.step(
        _dt,
        wishDirection: Vector3.zero(),
        drivenBy: graph.rootDeltaIn(_model),
      );
    }
    // A second of 1.5 along the pose's z: 3 m along the world's x.
    expect(body.position.x, closeTo(3.0, 1e-3));
    expect(body.position.z.abs(), lessThan(1e-3));
  });

  test('and stops at a wall, the pose still striding', () {
    final world = CollisionWorld()
      ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0))
      ..addBox(Vector3(2.5, 1.0, 0.0), Vector3(1.0, 2.0, 4.0));
    final body = CharacterController(
      world: world,
      position: Vector3(0.0, 0.9, 0.0),
    );
    final graph = _walking();
    for (var i = 0; i < 120; i++) {
      graph.evaluate(_dt);
      body.step(
        _dt,
        wishDirection: Vector3.zero(),
        drivenBy: graph.rootDeltaIn(_model),
      );
    }
    expect(body.position.x, closeTo(2.0 - body.halfExtents.x, 0.01));
    expect(graph.rootDelta.z, greaterThan(0.0), reason: 'still walking');
  });
}
