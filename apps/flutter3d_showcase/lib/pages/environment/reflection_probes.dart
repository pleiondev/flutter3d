/// A mirror finish that shows the room it stands in, not the sky: a cube
/// captured from one point and convolved into a roughness chain on the
/// device.
///
/// Quoted by `reflection_probes.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class ReflectionProbesDemo extends ShowcaseDemo {
  double intensity = 1.0;
  double roughness = 0.06;

  late final ReflectionProbeNode _probe;
  late final Material _ball;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 6.0
      ..pitch = 0.18
      ..yaw = 0.7;
    context.orbit.target.setValues(0.0, 0.7, 0.0);
    context.orbit.apply();
  }

  @override
  Scene build(DemoContext context) {
    final Material floor = Material(
      name: 'floor',
      baseColor: Vector4(0.5, 0.5, 0.53, 1.0),
      roughness: 0.9,
      doubleSided: true,
    );
    final Material wall = Material(
      name: 'wall',
      baseColor: Vector4(0.82, 0.18, 0.14, 1.0),
      roughness: 0.9,
      doubleSided: true,
    );
    // #region ball
    final Material ball = _ball = Material(
      name: 'mirror ball',
      baseColor: Vector4(0.9, 0.9, 0.92, 1.0),
      metallic: 1.0,
      roughness: roughness,
    );
    // #endregion ball

    // #region probe
    _probe = ReflectionProbeNode(name: 'probe', intensity: intensity)
      ..setPosition(0.0, 0.9, 0.0);
    // #endregion probe

    final MeshNode wallNode =
        MeshNode(
            DeviceMesh.upload(
              context.device,
              const PlaneShape(width: 3, depth: 4).build(),
            ),
            wall,
            name: 'wall',
          )
          ..setPosition(-2.0, 1.5, 0.0)
          ..setRotation(
            Quaternion.axisAngle(Vector3(0.0, 0.0, 1.0), -math.pi / 2),
          );

    return Scene()
      ..ambientIntensity = 0.15
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            const PlaneShape(width: 8, depth: 8).build(),
          ),
          floor,
          name: 'floor',
        ),
      )
      ..add(wallNode)
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            SphereShape(radius: 0.9, segments: 32, rings: 16).build(),
          ),
          ball,
          name: 'ball',
        )..setPosition(0.0, 0.9, 0.0),
      )
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.5, -0.7, -0.35)),
      )
      ..add(_probe);
  }

  // #region live
  @override
  void update(DemoContext context, double dt) {
    _probe.intensity = intensity;
    _ball.roughness = roughness;
  }
  // #endregion live

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Probe intensity',
      min: 0,
      max: 2,
      value: () => intensity,
      onChanged: (double v) => intensity = v,
    ),
    SliderControl(
      'Ball roughness',
      min: 0.02,
      max: 1,
      value: () => roughness,
      onChanged: (double v) => roughness = v,
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (!_probe.isCaptured) {
      throw StateError('the probe never finished capturing its cube');
    }
    final FramePass capture = frame.passes.firstWhere(
      (FramePass p) => p.name == 'reflection probe 0',
      orElse: () => throw StateError('no reflection probe pass ran this frame'),
    );
    if (capture.drawCalls == 0) {
      throw StateError('the probe pass ran and drew nothing into its cube');
    }
  }
}
