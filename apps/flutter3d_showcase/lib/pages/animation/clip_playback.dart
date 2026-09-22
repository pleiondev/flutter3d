/// Two clips on one cube: `AnimationPlayer` plays one, fades to the other and
/// answers to a speed and a wrap mode while it does.
///
/// Quoted by `clip_playback.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class ClipPlaybackDemo extends ShowcaseDemo {
  int wrapIndex = 0;

  late final AnimationPlayer _player;

  static const List<AnimationWrap> _wraps = <AnimationWrap>[
    AnimationWrap.loop,
    AnimationWrap.once,
    AnimationWrap.pingPong,
  ];

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 3.5
      ..pitch = 0.25;
  }

  @override
  Scene build(DemoContext context) {
    final MeshNode cube = MeshNode(
      DeviceMesh.upload(context.device, CuboidShape().build()),
      Material(name: 'cube', baseColor: Vector4(0.3, 0.55, 0.9, 1.0)),
      name: 'cube',
    );

    // #region clips
    final AnimationClip spin = AnimationClip(
      name: 'spin',
      tracks: <AnimationTrack>[_yawTrack(turns: 1, duration: 2.0)],
    );
    final AnimationClip nod = AnimationClip(
      name: 'nod',
      tracks: <AnimationTrack>[_nodTrack(duration: 1.2)],
    );
    // #endregion clips

    // #region player
    _player = AnimationPlayer(
      clips: <AnimationClip>[spin, nod],
      targets: <AnimationTarget?>[cube],
    );
    _player.play(0);
    _player.crossFadeTo(1, duration: 0.4);
    // #endregion player

    return Scene()
      ..add(cube)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -0.7, -0.5)),
      );
  }

  /// A full turn about Y, five keys so the loop closes exactly on itself.
  static AnimationTrack _yawTrack({
    required int turns,
    required double duration,
  }) {
    const int keys = 5;
    final Float32List times = Float32List(keys);
    final Float32List values = Float32List(keys * 4);
    for (var i = 0; i < keys; i++) {
      final double t = i / (keys - 1);
      times[i] = t * duration;
      final Quaternion q = Quaternion.axisAngle(
        Vector3(0.0, 1.0, 0.0),
        t * turns * 2 * math.pi,
      );
      values[i * 4] = q.x;
      values[i * 4 + 1] = q.y;
      values[i * 4 + 2] = q.z;
      values[i * 4 + 3] = q.w;
    }
    return AnimationTrack(
      nodeIndex: 0,
      path: AnimationPath.rotation,
      interpolation: AnimationInterpolation.linear,
      times: times,
      values: values,
      componentCount: 4,
    );
  }

  /// A short dip on X: level, down, level.
  static AnimationTrack _nodTrack({required double duration}) {
    final List<double> angles = <double>[0.0, -0.5, 0.0];
    final Float32List times = Float32List.fromList(<double>[
      0.0,
      duration / 2,
      duration,
    ]);
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
      nodeIndex: 0,
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
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Speed',
      min: 0.1,
      max: 3,
      value: () => _player.speed,
      onChanged: (double v) => _player.speed = v,
    ),
    ChoiceControl(
      'Wrap',
      options: const <String>['Loop', 'Once', 'Ping-pong'],
      index: () => wrapIndex,
      onChanged: (int i) {
        wrapIndex = i;
        _player.wrap = _wraps[i];
      },
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (!_player.isPlaying) {
      throw StateError('the player is not playing a clip');
    }
    if (!_player.isCrossFading) {
      throw StateError('the crossfade to the second clip did not start');
    }
    final double weight = _player.fadeWeight;
    if (weight <= 0.0 || weight >= 1.0) {
      throw StateError('the crossfade is not partway through, got $weight');
    }
  }
}
