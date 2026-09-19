/// An arm bent to reach a point: `TwoBoneIk` solves on a `Pose` alone, with
/// no scene behind it, and only afterwards is the result written onto real
/// nodes so this page has something to draw.
///
/// Quoted by `two_bone_ik.md` and shown whole in the Source tab.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class TwoBoneIkDemo extends ShowcaseDemo {
  double reach = 0.5;

  late final Pose _pose;
  late final SceneNode _shoulder;
  late final SceneNode _elbow;
  late final SceneNode _wrist;
  late final MeshNode _targetMarker;
  double _lastError = 0.0;

  static const double _boneLength = 1.0;
  static Vector3 get _pole => Vector3(1.0, 0.0, 0.0);

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 5.0
      ..pitch = 0.2
      ..yaw = 0.3;
  }

  @override
  Scene build(DemoContext context) {
    // #region pose
    _pose = Pose(
      parents: <int>[-1, 0, 1],
      restTranslations: Float32List.fromList(<double>[
        0.0, 0.0, 0.0, // shoulder
        0.0, -_boneLength, 0.0, // elbow, relative to the shoulder
        0.0, -_boneLength, 0.0, // wrist, relative to the elbow
      ]),
      restRotations: Float32List.fromList(<double>[
        0.0,
        0.0,
        0.0,
        1.0,
        0.0,
        0.0,
        0.0,
        1.0,
        0.0,
        0.0,
        0.0,
        1.0,
      ]),
      restScales: Float32List.fromList(<double>[
        1.0,
        1.0,
        1.0,
        1.0,
        1.0,
        1.0,
        1.0,
        1.0,
        1.0,
      ]),
    );
    // #endregion pose

    final DeviceMesh joint = DeviceMesh.upload(
      context.device,
      SphereShape(radius: 0.12, segments: 16, rings: 8).build(),
    );
    _shoulder = MeshNode(
      joint,
      Material(name: 'shoulder', baseColor: Vector4(0.6, 0.6, 0.65, 1.0)),
      name: 'shoulder',
    );
    _elbow = MeshNode(
      joint,
      Material(name: 'elbow', baseColor: Vector4(0.6, 0.6, 0.65, 1.0)),
      name: 'elbow',
    );
    _wrist = MeshNode(
      joint,
      Material(name: 'wrist', baseColor: Vector4(0.9, 0.5, 0.2, 1.0)),
      name: 'wrist',
    );
    _shoulder.add(_elbow);
    _elbow.add(_wrist);
    _targetMarker = MeshNode(
      DeviceMesh.upload(
        context.device,
        SphereShape(radius: 0.08, segments: 12, rings: 6).build(),
      ),
      Material(name: 'target', baseColor: Vector4(0.9, 0.2, 0.2, 1.0)),
      name: 'target',
    );

    return Scene()
      ..add(_shoulder)
      ..add(_targetMarker)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -0.7, -0.5)),
      );
  }

  @override
  void update(DemoContext context, double dt) {
    // #region solve
    final double maxReach = _boneLength * 2;
    final Vector3 direction = Vector3(0.6, -0.7, 0.3)..normalize();
    final Vector3 target = direction * (reach * maxReach * 0.8);

    _pose.resetToRest();
    _lastError = TwoBoneIk.solve(
      _pose,
      root: 0,
      mid: 1,
      tip: 2,
      target: target,
      pole: _pole,
    );
    _pose.writeTo(<SceneNode?>[_shoulder, _elbow, _wrist]);
    _targetMarker.setPositionFrom(target);
    // #endregion solve
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Reach',
      min: 0,
      max: 1,
      value: () => reach,
      onChanged: (double v) => reach = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (_lastError > 1e-3) {
      throw StateError(
        'the wrist did not reach the target; missed by $_lastError',
      );
    }
  }
}
