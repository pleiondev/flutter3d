/// How many sounds may play at once, and which ones win when more than that
/// are asking to be heard.
///
/// Quoted by `voice_limit.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_showcase/src/demo/scene_kit.dart';
import 'package:vector_math/vector_math.dart';

final class VoiceLimitDemo extends ShowcaseDemo {
  late final String _report;

  double voices = 3.0;
  double asking = 8.0;
  bool shouting = true;

  bool _dirty = true;
  late final List<MeshNode> _balls;
  late final MeshNode _shout;
  late final BarGauge _granted;

  static const int _most = 12;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 14.0
      ..pitch = 1.1
      ..yaw = 0.0;
    context.orbit.target.setValues(0.0, 0.0, 0.5);
  }

  @override
  Scene build(DemoContext context) {
    _report = _run();
    _balls = <MeshNode>[
      for (var i = 0; i < _most; i++)
        ballNode(context, 'step $i', 0.3, Vector4(0.3, 0.3, 0.33, 1.0)),
    ];
    _shout = ballNode(
      context,
      'shout',
      0.55,
      Vector4(0.3, 0.3, 0.33, 1.0),
      at: Vector3(0.0, 0.55, -3.0),
    );
    _granted = BarGauge(
      context,
      'granted',
      Vector4(0.7, 0.4, 0.8, 1.0),
      Vector3(-5.0, 0.0, 5.5),
      height: 10.0,
    );
    return sceneOf(<SceneNode>[
      floorNode(context, width: 16.0, depth: 14.0),
      blockNode(
        context,
        'listener',
        Vector3(0.6, 0.6, 0.6),
        Vector4(0.45, 0.65, 0.95, 1.0),
        at: Vector3(0.0, 0.3, 0.0),
      ),
      ..._balls,
      _shout,
      ..._granted.nodes,
    ]);
  }

  @override
  void update(DemoContext context, double dt) {
    if (!_dirty) return;
    _dirty = false;
    // #region live
    // Ask again with whatever the sliders say: a scene with room for `voices`
    // voices, a crowd of footsteps at growing distances, and a shout.
    final AudioScene scene = AudioScene(
      backend: SilentBackend(),
      maxVoices: voices.round(),
    );
    const SoundDef footstep = SoundDef(
      name: 'footstep',
      asset: 'step.wav',
      priority: 0,
    );
    const SoundDef shout = SoundDef(
      name: 'shout',
      asset: 'shout.wav',
      priority: 10,
    );
    final List<SoundEmitter> steps = <SoundEmitter>[
      for (var i = 0; i < asking.round(); i++)
        scene.play(
          footstep,
          Vector3(
            (1.5 + 0.35 * i) * math.cos(i * 2.4),
            0.0,
            (1.5 + 0.35 * i) * math.sin(i * 2.4),
          ),
        ),
    ];
    final SoundEmitter? loud = shouting
        ? scene.play(shout, Vector3(0.0, 0.0, -3.0))
        : null;
    scene.update(AudioListener());
    // #endregion live
    for (var i = 0; i < _most; i++) {
      final bool asked = i < steps.length;
      _balls[i].visible = asked;
      if (!asked) continue;
      final double angle = i * 2.4;
      final double radius = 1.5 + 0.35 * i;
      _balls[i].setPosition(
        radius * math.cos(angle),
        0.3,
        radius * math.sin(angle),
      );
      _colour(_balls[i], steps[i].audibleGain > 0.0, const <double>[
        0.9,
        0.75,
        0.3,
      ]);
    }
    _shout.visible = loud != null;
    if (loud != null) {
      _colour(_shout, loud.audibleGain > 0.0, const <double>[0.85, 0.35, 0.3]);
    }
    _granted.set(scene.voiceCount / 10.0);
  }

  /// Lit in [lit] colours while it has a voice, dark once it has none.
  void _colour(MeshNode node, bool has, List<double> lit) {
    node.material.baseColor.setValues(
      has ? lit[0] : 0.22,
      has ? lit[1] : 0.22,
      has ? lit[2] : 0.25,
      1.0,
    );
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Voices allowed',
      min: 1,
      max: 10,
      value: () => voices,
      onChanged: (double v) {
        voices = v.roundToDouble();
        _dirty = true;
      },
      format: (double v) => v.round().toString(),
    ),
    SliderControl(
      'Footsteps asking',
      min: 0,
      max: 12,
      value: () => asking,
      onChanged: (double v) {
        asking = v.roundToDouble();
        _dirty = true;
      },
      format: (double v) => v.round().toString(),
    ),
    ToggleControl(
      'Add a shout',
      value: () => shouting,
      onChanged: (bool v) {
        shouting = v;
        _dirty = true;
      },
    ),
  ];

  static String _run() {
    // #region scene
    // A scene with room for three voices, asked for five.
    final scene = AudioScene(backend: SilentBackend(), maxVoices: 3);
    const footstep = SoundDef(name: 'footstep', asset: 'step.wav', priority: 0);
    const shout = SoundDef(name: 'shout', asset: 'shout.wav', priority: 10);
    // #endregion scene

    // #region crowd
    for (var i = 0; i < 4; i++) {
      scene.play(footstep, Vector3(i.toDouble(), 0.0, 0.0));
    }
    final loudOne = scene.play(shout, Vector3(0.0, 0.0, 3.0));
    const requested = 5;
    scene.update(AudioListener());
    // #endregion crowd

    // #region read
    // A one-shot that lost the vote for a voice is dropped on the same
    // update that decided it, which is why what is left over answers both
    // questions at once.
    final gotVoice = scene.voiceCount;
    final shoutWon = loudOne.audibleGain > 0.0;
    // #endregion read

    return '$gotVoice of $requested requested sounds got a voice; '
        'the rest, being one-shots, are already gone\n'
        'the higher-priority shout is one of them: $shoutWon';
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the crowd marker was not drawn');
    }
    if (!_report.contains('3 of 5 requested sounds got a voice')) {
      throw StateError(
        'a scene limited to three voices should give exactly '
        'three of five sounds one',
      );
    }
    if (!_report.contains('is one of them: true')) {
      throw StateError(
        'a higher-priority sound should win a voice over a '
        'lower-priority one',
      );
    }
  }
}
