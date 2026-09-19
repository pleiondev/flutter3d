/// A walk clip whose own translation track stands still: the forward motion
/// was extracted into the clip's `extras` under `flutter3dRootMotion`, and
/// `AnimationPlayer.rootMotionDelta` hands it back a step at a time so a
/// separate controller node can carry the character instead of the rig
/// sliding inside itself.
///
/// Quoted by `root_motion.md` and shown whole in the Source tab.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class RootMotionDemo extends ShowcaseDemo {
  late final AnimationPlayer _player;
  late final SceneNode _controller;
  double _lastTime = 0.0;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 4.0
      ..pitch = 0.2;
  }

  @override
  Scene build(DemoContext context) {
    final MeshNode walker = MeshNode(
      DeviceMesh.upload(context.device, CuboidShape().build()),
      Material(name: 'walker', baseColor: Vector4(0.3, 0.7, 0.4, 1.0)),
      name: 'walker',
    );

    // #region clip
    // The track that ships with the clip stands still — the walk was
    // flattened to its first key, the way an exporter's own extraction pass
    // leaves it. The values a real walk would have had live in `extras`
    // instead, one triple per keyframe.
    final Float32List times = Float32List.fromList(<double>[0.0, 0.5, 1.0]);
    final AnimationTrack flatTrack = AnimationTrack(
      nodeIndex: 0,
      path: AnimationPath.translation,
      interpolation: AnimationInterpolation.linear,
      times: times,
      values: Float32List(9),
      componentCount: 3,
    );
    final AnimationClip walk = AnimationClip(
      name: 'walk',
      tracks: <AnimationTrack>[flatTrack],
      extras: <String, Object?>{
        kRootMotionExtra: <List<double>>[
          <double>[0.0, 0.0, 0.0],
          <double>[0.0, 0.0, 1.0],
          <double>[0.0, 0.0, 2.0],
        ],
      },
    );
    // #endregion clip

    // #region controller
    _controller = SceneNode(name: 'controller');
    _controller.add(walker);
    _player = AnimationPlayer(
      clips: <AnimationClip>[walk],
      targets: <AnimationTarget?>[walker],
    )..play(0);
    // #endregion controller

    return Scene()
      ..add(_controller)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -0.7, -0.5)),
      );
  }

  @override
  void update(DemoContext context, double dt) {
    // #region live
    final double fromTime = _lastTime;
    _player.update(dt);
    _lastTime = _player.time;
    final Vector3? delta = _player.rootMotionDelta(
      0,
      fromTime: fromTime,
      toTime: _lastTime,
    );
    if (delta != null) {
      _controller.translate(delta.x, delta.y, delta.z);
    }
    // #endregion live
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    final double z = _controller.worldMatrix.getTranslation().z;
    if (z <= 1e-5) {
      throw StateError('the controller did not carry the walk forward');
    }
    if (z > 1.0) {
      throw StateError('the controller moved further than one frame allows');
    }
  }
}
