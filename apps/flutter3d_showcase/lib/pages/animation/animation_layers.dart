/// A walk on the base clip, a wave laid over just the arm: `AnimationLayer`
/// and `AnimationMask` say which joints a second clip may touch while the
/// base keeps playing everywhere else.
///
/// Quoted by `animation_layers.md` and shown whole in the Source tab.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class AnimationLayersDemo extends ShowcaseDemo {
  late final AnimationPlayer _player;
  late final AnimationLayer _wave;
  late final AnimationTrack _waveTrack;
  late final SceneNode _body;
  late final SceneNode _arm;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 4.5
      ..pitch = 0.2;
  }

  @override
  Scene build(DemoContext context) {
    final DeviceMesh torso = DeviceMesh.upload(
      context.device,
      CuboidShape(size: Vector3(0.8, 1.4, 0.5)).build(),
    );
    final DeviceMesh limb = DeviceMesh.upload(
      context.device,
      CuboidShape(size: Vector3(0.2, 0.9, 0.2)).build(),
    );

    final MeshNode bodyMesh = MeshNode(
      torso,
      Material(name: 'body', baseColor: Vector4(0.5, 0.55, 0.65, 1.0)),
      name: 'body',
    );
    final MeshNode armMesh = MeshNode(
      limb,
      Material(name: 'arm', baseColor: Vector4(0.85, 0.5, 0.2, 1.0)),
      name: 'arm',
    )..setPosition(0.6, 0.3, 0.0);
    _body = bodyMesh;
    _arm = armMesh;

    // #region clips
    final AnimationClip walk = AnimationClip(
      name: 'walk',
      tracks: <AnimationTrack>[
        _rotationTrack(nodeIndex: 0, axis: Vector3(0, 0, 1), peak: 0.12),
        _rotationTrack(nodeIndex: 1, axis: Vector3(1, 0, 0), peak: 0.5),
      ],
    );
    _waveTrack = _rotationTrack(
      nodeIndex: 1,
      axis: Vector3(0, 0, 1),
      peak: 1.1,
    );
    final AnimationClip wave = AnimationClip(
      name: 'wave',
      tracks: <AnimationTrack>[_waveTrack],
    );
    // #endregion clips

    // #region layer
    _player = AnimationPlayer(
      clips: <AnimationClip>[walk, wave],
      targets: <AnimationTarget?>[bodyMesh, armMesh],
    )..play(0);
    _wave = _player.playLayer(
      1,
      mask: AnimationMask(<int>[1]),
      wrap: AnimationWrap.loop,
      fadeIn: 0.0,
    );
    // #endregion layer

    return Scene()
      ..add(bodyMesh)
      ..add(armMesh)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -0.7, -0.5)),
      );
  }

  static AnimationTrack _rotationTrack({
    required int nodeIndex,
    required Vector3 axis,
    required double peak,
  }) {
    final Float32List times = Float32List.fromList(<double>[0.0, 0.5, 1.0]);
    final List<double> angles = <double>[0.0, peak, 0.0];
    final Float32List values = Float32List(angles.length * 4);
    for (var i = 0; i < angles.length; i++) {
      final Quaternion q = Quaternion.axisAngle(axis, angles[i]);
      values[i * 4] = q.x;
      values[i * 4 + 1] = q.y;
      values[i * 4 + 2] = q.z;
      values[i * 4 + 3] = q.w;
    }
    return AnimationTrack(
      nodeIndex: nodeIndex,
      path: AnimationPath.rotation,
      interpolation: AnimationInterpolation.linear,
      times: times,
      values: values,
      componentCount: 4,
    );
  }

  @override
  void update(DemoContext context, double dt) {
    // #region live
    _player.update(dt);
    // #endregion live
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    if (!_wave.mask.covers(1) || _wave.mask.covers(0)) {
      throw StateError('the mask should cover the arm and nothing else');
    }
    final Quaternion bodyRotation = Quaternion.fromRotation(
      _body.worldMatrix.getRotation(),
    );
    if ((bodyRotation.w - 1.0).abs() < 1e-6) {
      throw StateError('the base clip did not move the body');
    }

    final Float32List sample = Float32List(4);
    _waveTrack.sample(_wave.time, sample);
    final Quaternion armRotation = Quaternion.fromRotation(
      _arm.worldMatrix.getRotation(),
    );
    final double dot =
        (armRotation.x * sample[0] +
                armRotation.y * sample[1] +
                armRotation.z * sample[2] +
                armRotation.w * sample[3])
            .abs();
    if (dot < 0.999) {
      throw StateError("the arm's pose came from the base clip, not the layer");
    }
  }
}
