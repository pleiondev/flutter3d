/// A two-joint pendulum sampled straight off a clip through `Pose`, with no
/// `AnimationPlayer` and no scene node anywhere near the arithmetic. The
/// clip turns the root; the tip only moves because it hangs off it. Markers
/// are placed afterwards, only to give this page something to draw.
///
/// Quoted by `pose_sampling.md` and shown whole in the Source tab.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class PoseSamplingDemo extends ShowcaseDemo {
  double _time = 0.3;

  late final Pose _pose;
  late final AnimationClip _swing;
  late final MeshNode _rootMarker;
  late final MeshNode _tipMarker;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 3.5
      ..pitch = 0.15;
  }

  @override
  Scene build(DemoContext context) {
    // #region pose
    _pose = Pose(
      parents: <int>[-1, 0],
      restTranslations: Float32List.fromList(<double>[
        0.0,
        0.0,
        0.0,
        0.0,
        -1.2,
        0.0,
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
      ]),
      restScales: Float32List.fromList(<double>[1.0, 1.0, 1.0, 1.0, 1.0, 1.0]),
    );
    // #endregion pose

    // #region clip
    final Float32List times = Float32List.fromList(<double>[0.0, 0.75, 1.5]);
    final List<double> angles = <double>[-0.6, 0.6, -0.6];
    final Float32List values = Float32List(angles.length * 4);
    for (var i = 0; i < angles.length; i++) {
      final Quaternion q = Quaternion.axisAngle(
        Vector3(1.0, 0.0, 0.0),
        angles[i],
      );
      values[i * 4] = q.x;
      values[i * 4 + 1] = q.y;
      values[i * 4 + 2] = q.z;
      values[i * 4 + 3] = q.w;
    }
    _swing = AnimationClip(
      name: 'swing',
      tracks: <AnimationTrack>[
        AnimationTrack(
          nodeIndex: 0,
          path: AnimationPath.rotation,
          interpolation: AnimationInterpolation.linear,
          times: times,
          values: values,
          componentCount: 4,
        ),
      ],
    );
    // #endregion clip

    final DeviceMesh bead = DeviceMesh.upload(
      context.device,
      SphereShape(radius: 0.15, segments: 16, rings: 8).build(),
    );
    _rootMarker = MeshNode(
      bead,
      Material(name: 'root', baseColor: Vector4(0.6, 0.6, 0.65, 1.0)),
      name: 'root marker',
    );
    _tipMarker = MeshNode(
      bead,
      Material(name: 'tip', baseColor: Vector4(0.9, 0.5, 0.2, 1.0)),
      name: 'tip marker',
    );

    return Scene()
      ..add(_rootMarker)
      ..add(_tipMarker)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.3, -0.7, -0.5)),
      );
  }

  @override
  void update(DemoContext context, double dt) {
    // #region sample
    _time = (_time + dt) % _swing.duration;
    _pose.sampleClip(_swing, _time);
    final List<Matrix4> world = _pose.worldMatrices();
    _rootMarker.setPositionFrom(world[0].getTranslation());
    _tipMarker.setPositionFrom(world[1].getTranslation());
    // #endregion sample
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    final Matrix4 restTip = _pose.restOf(1);
    final Vector3 sampledTip = _pose.worldMatrices()[1].getTranslation();
    final double moved = (sampledTip - restTip.getTranslation()).length;
    if (moved < 1e-3) {
      throw StateError(
        'sampling the clip did not move the tip off its rest pose',
      );
    }
  }
}
