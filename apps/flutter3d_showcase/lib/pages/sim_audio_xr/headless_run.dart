/// The interface a tool that plays a game blind is written against: no
/// window, no renderer, only a step, a save and a sentence about how things
/// stand.
///
/// Quoted by `headless_run.md` and shown whole in the Source tab.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
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

  @override
  Scene build(DemoContext context) {
    _report = _drive();
    final material = Material(
      name: 'walker',
      baseColor: Vector4(0.7, 0.6, 0.3, 1.0),
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
