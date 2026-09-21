/// A sound placed somewhere in the world, heard louder or softer and panned
/// left or right depending on where the listener stands and faces.
///
/// A `SilentBackend` runs this page: it makes no sound and records every
/// voice it is asked for, which is what lets the numbers below be checked
/// without a speaker or a browser's audio stack.
///
/// Quoted by `positional_audio.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_audio/flutter3d_audio.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_showcase/src/demo/scene_kit.dart';
import 'package:vector_math/vector_math.dart';

final class PositionalAudioDemo extends ShowcaseDemo {
  late final String _report;

  double distance = 4.0;
  double angle = 0.0;
  bool orbiting = true;
  bool turnedAway = false;

  late final SoundEmitter _emitter;
  late final AudioScene _audio;
  late final AudioListener _listener;
  late final MeshNode _source;
  late final MeshNode _head;
  late final BarGauge _gain;
  late final RailGauge _pan;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 13.0
      ..pitch = 0.95
      ..yaw = 0.0;
    context.orbit.target.setValues(0.0, 0.0, 1.5);
  }

  @override
  Scene build(DemoContext context) {
    _report = _run();
    _source = ballNode(
      context,
      'source',
      0.5,
      Vector4(0.9, 0.75, 0.3, 1.0),
      at: Vector3(0.0, 0.5, 0.0),
    );
    _head = blockNode(
      context,
      'listener',
      Vector3(0.7, 0.7, 0.7),
      Vector4(0.45, 0.65, 0.95, 1.0),
    );
    // A nose, so it is clear which way the listener faces.
    _head.add(
      blockNode(
        context,
        'nose',
        Vector3(0.2, 0.2, 0.4),
        Vector4(0.95, 0.95, 0.98, 1.0),
        at: Vector3(0.0, 0.0, -0.5),
      ),
    );
    _gain = BarGauge(
      context,
      'gain',
      Vector4(0.9, 0.75, 0.3, 1.0),
      Vector3(-3.0, 0.0, 6.0),
      height: 6.0,
    );
    _pan = RailGauge(
      context,
      'pan',
      Vector4(0.45, 0.65, 0.95, 1.0),
      Vector3(0.0, 0.0, 7.2),
    );

    // #region live
    // The same scene as above, asked again every frame: the listener moves
    // and turns, and what it would hear is read back off the emitter.
    _audio = AudioScene(backend: SilentBackend());
    _emitter = _audio.play(
      const SoundDef(name: 'bell', asset: 'bell.wav'),
      Vector3(0.0, 0.0, 0.0),
    );
    _listener = AudioListener();
    // #endregion live
    return sceneOf(<SceneNode>[
      floorNode(context, width: 18.0, depth: 18.0),
      _source,
      _head,
      ..._gain.nodes,
      ..._pan.nodes,
    ]);
  }

  @override
  void update(DemoContext context, double dt) {
    if (orbiting) angle = (angle + 25.0 * dt + 180.0) % 360.0 - 180.0;
    final double a = angle * math.pi / 180.0;
    final Vector3 at = Vector3(distance * math.cos(a), 0.0, distance * math.sin(a));
    // Facing the source, or a quarter turn from it.
    final double toward = math.atan2(at.x, at.z);
    final double yaw = toward + (turnedAway ? math.pi / 2 : 0.0);
    // #region hear
    _listener.aimAt(at, yaw);
    _audio.update(_listener);
    // #endregion hear
    _head
      ..setPosition(at.x, 0.35, at.z)
      ..setRotationYawPitchRoll(yaw, 0.0, 0.0);
    final double loud = _emitter.audibleGain;
    _source.setUniformScale(0.6 + 0.9 * loud);
    _source.setPosition(0.0, 0.5 * (0.6 + 0.9 * loud), 0.0);
    _gain.set(loud);
    _pan.set(_emitter.pan);
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Distance',
      min: 0.5,
      max: 12.0,
      value: () => distance,
      onChanged: (double v) => distance = v,
      format: (double v) => '${v.toStringAsFixed(1)} m',
    ),
    SliderControl(
      'Angle',
      min: -180.0,
      max: 180.0,
      value: () => angle,
      onChanged: (double v) {
        orbiting = false;
        angle = v;
      },
      format: (double v) => '${v.round()}°',
    ),
    ToggleControl(
      'Walk round it',
      value: () => orbiting,
      onChanged: (bool v) => orbiting = v,
    ),
    ToggleControl(
      'Turn away',
      value: () => turnedAway,
      onChanged: (bool v) => turnedAway = v,
    ),
  ];

  static String _run() {
    // #region scene
    final backend = SilentBackend();
    final scene = AudioScene(backend: backend);
    const bell = SoundDef(name: 'bell', asset: 'bell.wav');
    // #endregion scene

    // #region play
    final emitter = scene.play(bell, Vector3(4.0, 0.0, 0.0));
    final listener = AudioListener()..aimAt(Vector3.zero(), 0.0);
    scene.update(listener);
    // #endregion play

    final farGain = emitter.audibleGain;
    final farPan = emitter.pan;

    // #region move
    // The listener turns to face the source directly and steps closer.
    listener.aimAt(Vector3(2.0, 0.0, 0.0), -1.5707963267948966);
    scene.update(listener);
    // #endregion move

    return 'four metres to the side: gain ${farGain.toStringAsFixed(3)}, '
        'pan ${farPan.toStringAsFixed(2)}\n'
        'two metres away and facing it: gain '
        '${emitter.audibleGain.toStringAsFixed(3)}, pan '
        '${emitter.pan.toStringAsFixed(2)}';
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the source marker was not drawn');
    }
    if (!_report.contains('pan 1.00')) {
      throw StateError(
        'a source straight to the right of the listener '
        'should pan hard right',
      );
    }
  }
}
