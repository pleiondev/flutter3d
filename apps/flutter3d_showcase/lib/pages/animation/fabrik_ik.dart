/// A four-joint chain reaching for a point: `FabrikIk` solves a chain of any
/// length, the same way `TwoBoneIk` solves an arm, on a `Pose` with no scene
/// behind it.
///
/// Quoted by `fabrik_ik.md` and shown whole in the Source tab.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class FabrikIkDemo extends ShowcaseDemo {
  double reach = 0.6;

  late final Pose _pose;
  late final List<SceneNode> _joints;
  late final MeshNode _targetMarker;
  double _lastError = 0.0;

  static const int _jointCount = 4;
  static const double _boneLength = 0.7;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 5.5
      ..pitch = 0.2
      ..yaw = 0.3;
  }

  @override
  Scene build(DemoContext context) {
    // #region chain
    final List<int> parents = <int>[
      -1,
      for (var i = 1; i < _jointCount; i++) i - 1,
    ];
    final Float32List translations = Float32List(_jointCount * 3);
    final Float32List rotations = Float32List(_jointCount * 4);
    final Float32List scales = Float32List(_jointCount * 3);
    for (var i = 0; i < _jointCount; i++) {
      translations[i * 3 + 1] = i == 0 ? 0.0 : -_boneLength;
      rotations[i * 4 + 3] = 1.0;
      scales[i * 3] = 1.0;
      scales[i * 3 + 1] = 1.0;
      scales[i * 3 + 2] = 1.0;
    }
    _pose = Pose(
      parents: parents,
      restTranslations: translations,
      restRotations: rotations,
      restScales: scales,
    );
    // #endregion chain

    final DeviceMesh bead = DeviceMesh.upload(
      context.device,
      SphereShape(radius: 0.1, segments: 14, rings: 7).build(),
    );
    _joints = <SceneNode>[];
    SceneNode? previous;
    for (var i = 0; i < _jointCount; i++) {
      final MeshNode node = MeshNode(
        bead,
        Material(
          name: 'bead $i',
          baseColor: i == _jointCount - 1
              ? Vector4(0.9, 0.5, 0.2, 1.0)
              : Vector4(0.5, 0.65, 0.9, 1.0),
        ),
        name: 'bead $i',
      );
      if (previous == null) {
        _joints.add(node);
      } else {
        previous.add(node);
        _joints.add(node);
      }
      previous = node;
    }
    _targetMarker = MeshNode(
      DeviceMesh.upload(
        context.device,
        SphereShape(radius: 0.08, segments: 12, rings: 6).build(),
      ),
      Material(name: 'target', baseColor: Vector4(0.9, 0.2, 0.2, 1.0)),
      name: 'target',
    );

    return Scene()
      ..add(_joints.first)
      ..add(_targetMarker)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -0.7, -0.5)),
      );
  }

  @override
  void update(DemoContext context, double dt) {
    // #region solve
    final double maxReach = _boneLength * (_jointCount - 1);
    final Vector3 direction = Vector3(0.5, -0.8, 0.4)..normalize();
    final Vector3 target = direction * (reach * maxReach * 0.85);

    _pose.resetToRest();
    FabrikIk.solve(
      _pose,
      joints: <int>[for (var i = 0; i < _jointCount; i++) i],
      target: target,
    );
    _pose.writeTo(_joints);
    _targetMarker.setPositionFrom(target);

    final Vector3 tip = _pose.worldMatrices()[_jointCount - 1].getTranslation();
    _lastError = (tip - target).length;
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
    if (_lastError > 1e-2) {
      throw StateError(
        'the last bead did not reach the target within tolerance',
      );
    }
  }
}
