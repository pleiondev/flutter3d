/// The last few seconds of a run, kept as one snapshot a second and the raw
/// inputs between them, so a game can live them again for a kill camera or a
/// rewind mechanic; and what each step of that run actually cost.
///
/// Quoted by `rewind.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_showcase/src/demo/scene_kit.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

final class RewindDemo extends ShowcaseDemo {
  late final String _report;

  bool automatic = true;
  bool _rewindAsked = false;

  late RewindBuffer _buffer;
  late final MeshNode _runner;
  late final MeshNode _ghost;
  late final BarGauge _held;
  double _x = 0.0;
  double _owed = 0.0;
  double _clock = 0.0;
  double _sinceRewind = 0.0;

  /// Metres to a unit of `x`.
  static const double _scale = 0.25;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 12.0
      ..pitch = 0.5
      ..yaw = 0.0;
    context.orbit.target.setValues(8.0, 0.0, 0.0);
  }

  @override
  Scene build(DemoContext context) {
    _report = _run();
    _buffer = RewindBuffer(stepsPerSecond: 10, keyframeEvery: 5, history: 5);
    _runner = ballNode(context, 'runner', 0.4, Vector4(0.5, 0.8, 0.6, 1.0));
    _ghost = ballNode(context, 'ghost', 0.4, Vector4(0.45, 0.55, 0.95, 1.0));
    _held = BarGauge(
      context,
      'history',
      Vector4(0.7, 0.4, 0.8, 1.0),
      Vector3(0.0, 0.0, 2.5),
      height: 16.0,
    );
    return sceneOf(<SceneNode>[
      blockNode(
        context,
        'track',
        Vector3(18.0, 0.1, 3.0),
        Vector4(0.34, 0.38, 0.36, 1.0),
        at: Vector3(8.0, -0.05, 0.0),
      ),
      _runner,
      _ghost,
      ..._held.nodes,
    ]);
  }

  @override
  void update(DemoContext context, double dt) {
    _clock += dt;
    _sinceRewind += dt;
    if (automatic && _sinceRewind > 4.0) _rewindAsked = true;
    _owed += dt * 10.0;
    while (_owed >= 1.0) {
      _owed -= 1.0;
      // #region live
      // One step: record the input, take a keyframe when one is due, run the
      // step.
      _buffer.recorder.tape.frames.add(InputFrame(stickX: 1.0));
      if (_buffer.keyframeDue) {
        _buffer.keyframe(Snapshot(<String, Object?>{'x': _x}));
      }
      _x += 1.0;
      // #endregion live
      if (_x * _scale > 15.5) {
        // Off the end of the track: start the run again.
        _buffer.reset();
        _x = 0.0;
      }
    }
    // #region back
    // Where the run stood a second ago, and the way to get there: the state of
    // the nearest keyframe, and the steps to play forward from it.
    final RewindPoint? back = _buffer.rewindBy(1.0);
    final double? then = back == null
        ? null
        : (back.snapshot.data['x']! as num).toDouble() + back.replayed;
    // #endregion back
    if (_rewindAsked && back != null && then != null) {
      _rewindAsked = false;
      _sinceRewind = 0.0;
      // Make that the present: what came after it is forgotten.
      _buffer.cut(back);
      _x = then;
    }
    _rewindAsked = false;
    _runner.setPosition(
      _x * _scale,
      0.4 + 0.15 * (0.5 + 0.5 * math.sin(_clock * 12.0)),
      0.0,
    );
    _ghost.visible = then != null;
    if (then != null) _ghost.setPosition(then * _scale, 0.4, 1.2);
    _held.set(_buffer.step / 160.0);
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Rewind one second',
      value: () => false,
      onChanged: (bool v) {
        if (v) _rewindAsked = true;
      },
    ),
    ToggleControl(
      'Rewind by itself',
      value: () => automatic,
      onChanged: (bool v) => automatic = v,
    ),
  ];

  static String _run() {
    // #region buffer
    final buffer = RewindBuffer(
      stepsPerSecond: 10,
      keyframeEvery: 5,
      history: 5,
    );
    final timing = StepTimeTrace();
    var x = 0.0;
    // #endregion buffer

    // #region step
    for (var i = 0; i < 30; i++) {
      buffer.recorder.tape.frames.add(InputFrame(stickX: 1.0));
      if (buffer.keyframeDue) {
        buffer.keyframe(Snapshot(<String, Object?>{'x': x}));
      }
      timing.record(buffer.step, () => x += 1.0);
    }
    // #endregion step

    // #region rewind
    // One second back from the present, thirty steps in at ten steps a
    // second, lands on step 20.
    final point = buffer.rewindBy(1.0)!;
    // #endregion rewind

    return 'now at step ${buffer.step}, x=$x\n'
        'one second back: step ${point.step}, '
        'x=${point.snapshot.data['x']}, replaying ${point.replayed} inputs\n'
        'mean step cost: ${timing.meanMillis?.toStringAsFixed(3)} ms';
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the runner was not drawn');
    }
    if (!_report.contains('now at step 30') || !_report.contains('step 20')) {
      throw StateError(
        'a rewind of one second at ten steps a second should land on step 20 '
        'of a run now at step 30',
      );
    }
  }
}
