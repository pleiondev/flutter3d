/// A walk clip whose own translation track stands still: the forward motion
/// was extracted into the clip's `extras` under `flutter3dRootMotion`, and
/// `AnimationPlayer.rootMotionDelta` hands it back a step at a time so a
/// separate controller node can carry the character instead of the rig
/// sliding inside itself. The controller paces between two ends of a floor.
///
/// Quoted by `root_motion.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class RootMotionDemo extends ShowcaseDemo {
  late final AnimationPlayer _player;
  late final SceneNode _controller;
  double _lastTime = 0.0;
  double _direction = 1.0;

  /// How far from the middle of the floor the walker goes before it turns.
  static const double _reach = 3.5;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 11.0
      ..pitch = 0.6
      ..yaw = 0.7;
  }

  @override
  Scene build(DemoContext context) {
    final Scene scene = Scene();

    scene.add(
      MeshNode(
        DeviceMesh.upload(
          context.device,
          const PlaneShape(width: 7.0, depth: 11.0).build(),
        ),
        Material(name: 'floor', baseColor: Vector4(0.32, 0.36, 0.34, 1.0)),
        name: 'floor',
      ),
    );
    // Posts along both edges: the walker's own cube never changes shape, so
    // what shows that it is being carried is the ground going past it.
    final DeviceMesh post = DeviceMesh.upload(
      context.device,
      CuboidShape(size: Vector3(0.2, 0.6, 0.2)).build(),
    );
    final Material postMaterial = Material(
      name: 'post',
      baseColor: Vector4(0.85, 0.8, 0.6, 1.0),
    );
    for (var z = -5; z <= 5; z += 2) {
      for (final double x in <double>[-2.8, 2.8]) {
        scene.add(
          MeshNode(post, postMaterial, name: 'post $x,$z')
            ..setPosition(x, 0.3, z.toDouble()),
        );
      }
    }

    final MeshNode walker = MeshNode(
      DeviceMesh.upload(context.device, CuboidShape().build()),
      Material(name: 'walker', baseColor: Vector4(0.3, 0.7, 0.4, 1.0)),
      name: 'walker',
    );
    // A nose, so the turn at each end reads as a turn.
    walker.add(
      MeshNode(
        DeviceMesh.upload(
          context.device,
          CuboidShape(size: Vector3(0.3, 0.3, 0.4)).build(),
        ),
        Material(name: 'nose', baseColor: Vector4(0.95, 0.9, 0.8, 1.0)),
        name: 'nose',
      )..setPosition(0.0, 0.0, 0.6),
    );

    // #region clip
    // The track that ships with the clip goes up and down in place and
    // nowhere else: the walk's forward travel was taken out of it, the way
    // an exporter's own extraction pass leaves it. The values a real walk
    // would have had live in `extras` instead, one triple per keyframe.
    final Float32List times = Float32List.fromList(<double>[0.0, 0.5, 1.0]);
    final AnimationTrack bobTrack = AnimationTrack(
      nodeIndex: 0,
      path: AnimationPath.translation,
      interpolation: AnimationInterpolation.linear,
      times: times,
      values: Float32List.fromList(<double>[
        0.0, 0.0, 0.0, //
        0.0, 0.15, 0.0,
        0.0, 0.0, 0.0,
      ]),
      componentCount: 3,
    );
    final AnimationClip walk = AnimationClip(
      name: 'walk',
      tracks: <AnimationTrack>[bobTrack],
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
    _controller = SceneNode(name: 'controller')..setPosition(0.0, 0.5, -_reach);
    _controller.add(walker);
    _player = AnimationPlayer(
      clips: <AnimationClip>[walk],
      targets: <AnimationTarget?>[walker],
    )..play(0);
    // #endregion controller
    scene.add(_controller);

    return scene..add(
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
      // The clip only ever walks forward; which way forward is on the floor
      // is the controller's business, so it is the controller that turns
      // round when the floor runs out.
      _controller.translate(0.0, 0.0, delta.z * _direction);
      final double z = _controller.readPosition().z;
      if (z.abs() >= _reach) {
        _direction = z > 0 ? -1.0 : 1.0;
        _controller
          ..setPosition(0.0, 0.5, _reach * (z > 0 ? 1.0 : -1.0))
          ..setRotation(
            Quaternion.axisAngle(
              Vector3(0.0, 1.0, 0.0),
              _direction > 0 ? 0.0 : math.pi,
            ),
          );
      }
    }
    // #endregion live
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    final double z = _controller.readPosition().z;
    if (z <= -_reach + 1e-5) {
      throw StateError('the controller did not carry the walk forward');
    }
    if (z > -_reach + 1.0) {
      throw StateError('the controller moved further than one frame allows');
    }
    if (frame.drawCalls < 1) throw StateError('the walker was not drawn');
  }
}
