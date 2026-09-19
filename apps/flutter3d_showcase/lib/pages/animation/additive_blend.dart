/// A steady turn of the head, with a quick twitch layered on top of it
/// additively instead of replacing it — `AnimationBlend.additive` and
/// `AnimationClip.referenceTime`.
///
/// Quoted by `additive_blend.md` and shown whole in the Source tab.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class AdditiveBlendDemo extends ShowcaseDemo {
  late final AnimationPlayer _player;
  late final AnimationLayer _twitch;
  late final AnimationTrack _twitchTrack;
  late final SceneNode _head;
  late final Quaternion _turn;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 3.0
      ..pitch = 0.2;
  }

  @override
  Scene build(DemoContext context) {
    final MeshNode headMesh = MeshNode(
      DeviceMesh.upload(context.device, CuboidShape().build()),
      Material(name: 'head', baseColor: Vector4(0.8, 0.6, 0.35, 1.0)),
      name: 'head',
    );
    _head = headMesh;
    _turn = Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), 0.4);

    // #region clips
    final AnimationClip turn = AnimationClip(
      name: 'turn',
      tracks: <AnimationTrack>[
        _constantRotationTrack(nodeIndex: 0, rotation: _turn),
      ],
    );
    _twitchTrack = _pulseTrack(nodeIndex: 0);
    final AnimationClip twitch = AnimationClip(
      name: 'twitch',
      tracks: <AnimationTrack>[_twitchTrack],
      // The rest pose the twitch is a difference from: at time zero it
      // asks for nothing, so playing it alone would hold the head still.
      referenceTime: 0.0,
    );
    // #endregion clips

    // #region additive
    _player = AnimationPlayer(
      clips: <AnimationClip>[turn, twitch],
      targets: <AnimationTarget?>[headMesh],
    )..play(0);
    _twitch = _player.playLayer(
      1,
      wrap: AnimationWrap.once,
      fadeIn: 0.0,
      blend: AnimationBlend.additive,
    );
    // #endregion additive

    return Scene()
      ..add(headMesh)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.3, -0.7, -0.5)),
      );
  }

  static AnimationTrack _constantRotationTrack({
    required int nodeIndex,
    required Quaternion rotation,
  }) {
    final Float32List values = Float32List(8);
    for (var i = 0; i < 2; i++) {
      values[i * 4] = rotation.x;
      values[i * 4 + 1] = rotation.y;
      values[i * 4 + 2] = rotation.z;
      values[i * 4 + 3] = rotation.w;
    }
    return AnimationTrack(
      nodeIndex: nodeIndex,
      path: AnimationPath.rotation,
      interpolation: AnimationInterpolation.linear,
      times: Float32List.fromList(<double>[0.0, 1.0]),
      values: values,
      componentCount: 4,
    );
  }

  /// A short twitch about X: nothing, a snap forward, nothing again. Short
  /// enough that one frame at 60 fps already lands past its peak.
  static AnimationTrack _pulseTrack({required int nodeIndex}) {
    final List<double> angles = <double>[0.0, 0.8, 0.0];
    final Float32List times = Float32List.fromList(<double>[0.0, 0.01, 0.02]);
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
    final Float32List referenceBuffer = Float32List(4);
    _twitchTrack.sample(0.0, referenceBuffer);
    final Float32List sampleBuffer = Float32List(4);
    _twitchTrack.sample(_twitch.time, sampleBuffer);
    final Quaternion reference = Quaternion(
      referenceBuffer[0],
      referenceBuffer[1],
      referenceBuffer[2],
      referenceBuffer[3],
    );
    final Quaternion sample = Quaternion(
      sampleBuffer[0],
      sampleBuffer[1],
      sampleBuffer[2],
      sampleBuffer[3],
    );
    final Quaternion delta = (reference.conjugated() * sample)..normalize();
    if ((delta.w - 1.0).abs() < 1e-3) {
      throw StateError('the twitch has not moved yet; nothing to add');
    }

    final Quaternion expected = (_turn * delta)..normalize();
    final Quaternion actual = Quaternion.fromRotation(
      _head.worldMatrix.getRotation(),
    );
    final double dot =
        (actual.x * expected.x +
                actual.y * expected.y +
                actual.z * expected.z +
                actual.w * expected.w)
            .abs();
    if (dot < 0.999) {
      throw StateError(
        'the head is not the base turn with the twitch added on top of it',
      );
    }
  }
}
