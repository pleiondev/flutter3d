/// What the world does to a sound between there and here, as a callback the
/// scene asks and never a wall test of its own.
///
/// Quoted by `audio_occlusion.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_showcase/src/demo/scene_kit.dart';
import 'package:vector_math/vector_math.dart';

final class AudioOcclusionDemo extends ShowcaseDemo {
  late final String _report;

  double listenerX = 0.0;
  bool walking = true;

  late final AudioScene _audio;
  late final SoundEmitter _bell;
  late final AudioListener _listener;
  late final MeshNode _source;
  late final MeshNode _head;
  late final BarGauge _gain;
  late final BarGauge _muffle;
  double _clock = 0.0;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 12.0
      ..pitch = 0.8
      ..yaw = 0.0;
    context.orbit.target.setValues(1.0, 0.0, 1.0);
  }

  @override
  Scene build(DemoContext context) {
    _report = _run();
    _source = ballNode(
      context,
      'bell',
      0.5,
      Vector4(0.9, 0.75, 0.3, 1.0),
      at: Vector3(4.0, 0.5, 0.0),
    );
    _head = blockNode(
      context,
      'listener',
      Vector3(0.7, 0.7, 0.7),
      Vector4(0.45, 0.65, 0.95, 1.0),
    );
    _gain = BarGauge(
      context,
      'gain',
      Vector4(0.9, 0.75, 0.3, 1.0),
      Vector3(-4.0, 0.0, 4.5),
      height: 5.0,
    );
    _muffle = BarGauge(
      context,
      'muffle',
      Vector4(0.7, 0.4, 0.85, 1.0),
      Vector3(-4.0, 0.0, 5.5),
      height: 5.0,
    );

    // #region live
    // The same scene and the same question, asked every frame while the
    // listener walks: the wall is only ever the callback.
    _audio = AudioScene(backend: SilentBackend(), occlusion: _occlusion);
    _bell = _audio.play(
      const SoundDef(name: 'bell', asset: 'bell.wav', loop: true),
      Vector3(4.0, 0.0, 0.0),
    );
    _listener = AudioListener(position: Vector3.zero());
    // #endregion live
    return sceneOf(<SceneNode>[
      floorNode(context, width: 18.0, depth: 14.0),
      blockNode(
        context,
        'wall',
        Vector3(0.3, 2.0, 6.0),
        Vector4(0.6, 0.5, 0.4, 1.0),
        at: Vector3(2.0, 1.0, 0.0),
      ),
      _source,
      _head,
      ..._gain.nodes,
      ..._muffle.nodes,
    ]);
  }

  @override
  void update(DemoContext context, double dt) {
    _clock += dt;
    if (walking) listenerX = 2.0 + 5.5 * math.sin(_clock * 0.45);
    _listener.position.setValues(listenerX, 0.0, 0.0);
    _audio.update(_listener);
    _head.setPosition(listenerX, 0.35, 0.0);
    _gain.set(_bell.audibleGain);
    _muffle.set(_bell.muffle);
    // A muffled bell goes dull.
    _source.material.baseColor.setValues(
      0.9 - 0.45 * _bell.muffle,
      0.75 - 0.3 * _bell.muffle,
      0.3 + 0.2 * _bell.muffle,
      1.0,
    );
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Listener at',
      min: -6.0,
      max: 8.0,
      value: () => listenerX,
      onChanged: (double v) {
        walking = false;
        listenerX = v;
      },
      format: (double v) => '${v.toStringAsFixed(1)} m',
    ),
    ToggleControl(
      'Walk about',
      value: () => walking,
      onChanged: (bool v) => walking = v,
    ),
  ];

  // #region wall
  /// A wall at x = 2: a straight line that crosses it is half heard, and one
  /// that does not is heard clearly. The scene never learns what a wall is;
  /// it only asks this question.
  static double _occlusion(Vector3 from, Vector3 to) {
    final crossesWall = (from.x - 2.0).sign != (to.x - 2.0).sign;
    return crossesWall ? 0.5 : 1.0;
  }
  // #endregion wall

  static String _run() {
    // #region scene
    final scene = AudioScene(backend: SilentBackend(), occlusion: _occlusion);
    const bell = SoundDef(name: 'bell', asset: 'bell.wav', loop: true);
    final behindTheWall = scene.play(bell, Vector3(4.0, 0.0, 0.0));
    // #endregion scene

    // #region listen
    final listener = AudioListener(position: Vector3(0.0, 0.0, 0.0));
    scene.update(listener);
    final gainBehindWall = behindTheWall.audibleGain;
    final muffleBehindWall = behindTheWall.muffle;

    listener.position.setValues(5.0, 0.0, 0.0);
    scene.update(listener);
    final gainSameSide = behindTheWall.audibleGain;
    // #endregion listen

    return 'listener at 0, sound past the wall at 4: gain '
        '${gainBehindWall.toStringAsFixed(3)}, muffle '
        '${muffleBehindWall.toStringAsFixed(2)}\n'
        'listener moved to 5, same side as the sound now: gain '
        '${gainSameSide.toStringAsFixed(3)}';
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the wall marker was not drawn');
    }
    if (!_report.contains('muffle 0.50')) {
      throw StateError(
        'a sound heard through the wall should be muffled '
        'by half',
      );
    }
  }
}
