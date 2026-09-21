/// The interface a tool that plays a game blind is written against: no
/// window, no renderer, only a step, a save and a sentence about how things
/// stand.
///
/// Quoted by `headless_run.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_showcase/src/demo/scene_kit.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

// #region run
/// A toy game: a walker that moves towards x=10 and stops.
final class _WalkerRun implements HeadlessRun {
  final Vector3 _position = Vector3.zero();

  @override
  void step(double dt) {
    if (outcome != RunOutcome.playing) return;
    _position.x += 2.0 * dt;
    if (_position.x >= 10.0) {
      _position.x = 10.0;
      outcome = RunOutcome.won;
    }
  }

  @override
  Snapshot save() => Snapshot(<String, Object?>{'x': _position.x});

  @override
  RunOutcome outcome = RunOutcome.playing;

  @override
  Vector3 get position => _position;

  @override
  void eye(Vector3 out) => out.setValues(_position.x, 1.7, _position.z);

  @override
  void aim(Vector3 out) => out.setValues(1.0, 0.0, 0.0);

  @override
  String get summary =>
      'walking at x=${_position.x.toStringAsFixed(2)}, ${outcome.name}';

  @override
  Map<String, Object?> get reading => <String, Object?>{
    'x': _position.x,
    'outcome': outcome.name,
  };
}
// #endregion run

final class HeadlessRunDemo extends ShowcaseDemo {
  late final String _report;

  bool _againAsked = false;
  _WalkerRun _live = _WalkerRun();
  late final MeshNode _walker;
  late final BarGauge _progress;
  late final MeshNode _flag;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 14.0
      ..pitch = 0.4
      ..yaw = 0.2;
    context.orbit.target.setValues(5.0, 0.5, 0.0);
  }

  @override
  Scene build(DemoContext context) {
    _report = _drive();
    _walker = ballNode(context, 'walker', 0.45, Vector4(0.8, 0.65, 0.3, 1.0));
    _flag = blockNode(
      context,
      'goal',
      Vector3(0.2, 2.0, 0.2),
      Vector4(0.4, 0.85, 0.45, 1.0),
      at: Vector3(10.0, 1.0, 0.0),
    );
    _progress = BarGauge(
      context,
      'progress',
      Vector4(0.7, 0.45, 0.85, 1.0),
      Vector3(0.0, 0.0, 2.0),
      height: 10.0,
    );
    return sceneOf(<SceneNode>[
      blockNode(
        context,
        'track',
        Vector3(13.0, 0.1, 3.0),
        Vector4(0.34, 0.38, 0.36, 1.0),
        at: Vector3(5.0, -0.05, 0.0),
      ),
      _walker,
      _flag,
      ..._progress.nodes,
    ]);
  }

  @override
  void update(DemoContext context, double dt) {
    if (_againAsked) {
      _againAsked = false;
      _live = _WalkerRun();
    }
    // The same object the blind loop drives, stepped once a frame; when it
    // has won it waits a moment and starts again.
    _live.step(dt);
    if (_live.outcome != RunOutcome.playing && _live.position.x >= 10.0) {
      _pause += dt;
      if (_pause > 1.5) {
        _pause = 0.0;
        _live = _WalkerRun();
      }
    }
    _walker.setPosition(_live.position.x, 0.45, 0.0);
    _progress.set(_live.position.x / 10.0);
    _flag.material.baseColor.setValues(
      _live.outcome == RunOutcome.won ? 0.4 : 0.85,
      _live.outcome == RunOutcome.won ? 0.9 : 0.4,
      0.4,
      1.0,
    );
  }

  double _pause = 0.0;

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Run it again',
      value: () => false,
      onChanged: (bool v) {
        if (v) _againAsked = true;
      },
    ),
  ];

  /// What a tool that plays this blind does: step until the run is over.
  static String _drive() {
    // #region loop
    final run = _WalkerRun();
    var steps = 0;
    while (run.outcome == RunOutcome.playing && steps < 1000) {
      run.step(1 / 60);
      steps++;
    }
    // #endregion loop

    // #region report
    return '${run.summary} after $steps steps\n'
        'reading: ${run.reading}\n'
        'save: ${run.save().toJson()}';
    // #endregion report
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the walker was not drawn');
    }
    if (!_report.contains('won')) {
      throw StateError(
        'a walker driven with no screen should still reach '
        'the outcome its own rules describe',
      );
    }
  }
}
