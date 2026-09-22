/// Pausing, stepping and rewinding a running game from outside it, built on
/// a live rewind buffer.
///
/// **`flutter3d_game`'s real `RunTimeline` is not a dependency of this
/// app.** Every field it holds and every line it runs is a type this app
/// already depends on through `flutter3d_sim` — `RewindBuffer`,
/// `InputState`, `InputTapePlayback`, `Snapshot` — so this page carries the
/// class over in full rather than approximating it.
///
/// Quoted by `run_timeline.md` and shown whole in the Source tab.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

// #region timeline
/// Pause, step and rewind, over a live [RewindBuffer] — carried over from
/// `flutter3d_game`'s real class, whose whole body is `flutter3d_sim` types.
final class _RunTimeline {
  _RunTimeline({
    required this.rewind,
    required this.input,
    required this.stepSim,
    required this.restore,
    this.stepSeconds = 1.0 / 60.0,
  });

  final RewindBuffer rewind;
  final InputState input;
  final void Function(double dt) stepSim;
  final void Function(Snapshot snapshot) restore;
  final double stepSeconds;

  bool _paused = false;
  bool get isPaused => _paused;

  void pause() => _paused = true;
  void resume() => _paused = false;

  void stepOnce() {
    if (!_paused) {
      throw StateError('stepOnce is only valid while the timeline is paused');
    }
    stepSim(stepSeconds);
  }

  RewindPoint? preview(double secondsAgo) => rewind.rewindBy(secondsAgo);

  void releaseAt(RewindPoint point) {
    restore(point.snapshot);
    final toPoint = InputTapePlayback(point.tapeToPoint);
    while (!toPoint.isFinished) {
      toPoint.applyTo(input);
      stepSim(stepSeconds);
    }
    rewind.cut(point);
    _paused = false;
  }
}
// #endregion timeline

final class RunTimelineDemo extends ShowcaseDemo {
  late final String _report;
  late final double _beforePause;
  late final double _afterOneStep;
  late final double _afterRelease;
  late final bool _timelinePausedAfterRelease;

  @override
  Scene build(DemoContext context) {
    final (
      String report,
      double beforePause,
      double afterOneStep,
      double afterRelease,
      bool timelinePausedAfterRelease,
    ) = _run();
    _report = report;
    _beforePause = beforePause;
    _afterOneStep = afterOneStep;
    _afterRelease = afterRelease;
    _timelinePausedAfterRelease = timelinePausedAfterRelease;
    final material = Material(
      name: 'runner',
      baseColor: Vector4(0.6, 0.8, 0.5, 1.0),
    );
    final node = MeshNode(
      DeviceMesh.upload(context.device, SphereShape(segments: 16).build()),
      material,
    );
    return Scene()
      ..add(node)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
  }

  static (String, double, double, double, bool) _run() {
    var x = 0.0;
    final buffer = RewindBuffer(
      stepsPerSecond: 10,
      keyframeEvery: 5,
      history: 5,
    );
    final timeline = _RunTimeline(
      rewind: buffer,
      input: InputState(),
      stepSim: (double dt) => x += 1.0,
      restore: (Snapshot s) => x = (s.data['x']! as num).toDouble(),
      stepSeconds: 1 / 10,
    );

    // #region play
    // Twenty steps of ordinary play, recorded the way a game loop already
    // records every step for the rewind buffer.
    for (var i = 0; i < 20; i++) {
      buffer.recorder.tape.frames.add(InputFrame(stickX: 1.0));
      if (buffer.keyframeDue) {
        buffer.keyframe(Snapshot(<String, Object?>{'x': x}));
      }
      timeline.stepSim(1 / 10);
    }
    final beforePause = x;
    // #endregion play

    // #region pause
    timeline.pause();
    timeline.stepOnce();
    final afterOneStep = x;
    // #endregion pause

    // #region rewind
    final point = timeline.preview(1.0)!;
    timeline.releaseAt(point);
    final afterRelease = x;
    // #endregion rewind

    final report =
        'after twenty steps: x=$beforePause\n'
        'paused, then stepped once by hand: x=$afterOneStep\n'
        'rewound one second and released: x=$afterRelease, timeline paused: '
        '${timeline.isPaused}';
    return (report, beforePause, afterOneStep, afterRelease, timeline.isPaused);
  }

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) =>
      Container(
        color: const Color(0xFF14161A),
        padding: const EdgeInsets.all(24),
        alignment: Alignment.topLeft,
        child: DefaultTextStyle(
          style: const TextStyle(color: Color(0xFFE8E8EC), fontSize: 16),
          child: Text(_report),
        ),
      );

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the runner marker was not drawn');
    }
    // Compared as numbers, not read back out of `_report`: each of these is
    // a whole-number double, and a web backend prints one of those without
    // its trailing `.0` — a compiled `20` failing a substring match against
    // `'x=20.0'` would be this check catching its own string, not the
    // timeline.
    if (_beforePause != 20.0) {
      throw StateError('twenty recorded steps of one each should reach 20');
    }
    if (_afterOneStep != 21.0) {
      throw StateError('a manual step while paused should still advance x');
    }
    if (_afterRelease != 10.0) {
      throw StateError(
        'rewinding one second on a ten-steps-a-second buffer should land '
        'on the recorded state ten steps back, discarding the manual step '
        'that was never recorded',
      );
    }
    if (_timelinePausedAfterRelease) {
      throw StateError(
        'releasing a rewind point should leave the timeline '
        'running, not paused',
      );
    }
  }
}
