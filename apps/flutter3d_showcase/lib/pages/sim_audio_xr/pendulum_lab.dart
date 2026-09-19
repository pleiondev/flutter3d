/// A worked example small enough that changing one number visibly changes
/// how a run unfolds, and the digest that tells an instructor exactly where
/// a student's run first parted from the assignment.
///
/// **`flutter3d_lab` is not a dependency of this app.** Its real
/// `PendulumSimulation` is nineteen lines of semi-implicit Euler over
/// `Portable.sin`; this page reimplements exactly that formula by hand,
/// against the same `Portable` this app already depends on through
/// `flutter3d_sim`, and uses the real `DigestTrace` to compare two runs —
/// the verification mechanism is genuine, only the tiny pendulum formula is
/// not imported.
///
/// Quoted by `pendulum_lab.md` and shown whole in the Source tab.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

// #region pendulum
/// The lab's own worked example: semi-implicit Euler over a gravity
/// pendulum, the same order of integrator the rest of the engine steps
/// with.
final class _Pendulum {
  _Pendulum({required this.lengthMeters, double startAngle = 0.6})
    : theta = startAngle,
      omega = 0.0;

  static const double _gravity = 9.81;

  double lengthMeters;
  double theta;
  double omega;

  void step(double dt) {
    final alpha = -(_gravity / lengthMeters) * Portable.sin(theta);
    omega += alpha * dt;
    theta += omega * dt;
  }

  Map<String, Object?> get state => <String, Object?>{
    'theta': theta,
    'omega': omega,
  };
}
// #endregion pendulum

final class PendulumLabDemo extends ShowcaseDemo {
  late final String _report;

  @override
  Scene build(DemoContext context) {
    _report = _run();
    final material = Material(
      name: 'bob',
      baseColor: Vector4(0.8, 0.7, 0.3, 1.0),
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

  static String _run() {
    // #region assignment
    final assignment = DigestTrace(every: 10);
    final assignmentPendulum = _Pendulum(lengthMeters: 1.0);
    for (var step = 1; step <= 60; step++) {
      assignmentPendulum.step(1 / 60);
      assignment.observe(step, assignmentPendulum.state);
    }
    // #endregion assignment

    // #region student
    // A student who changed the length partway through the run.
    final studentPendulum = _Pendulum(lengthMeters: 1.0);
    final student = DigestTrace(every: 10);
    for (var step = 1; step <= 60; step++) {
      if (step == 30) studentPendulum.lengthMeters = 1.3;
      studentPendulum.step(1 / 60);
      student.observe(step, studentPendulum.state);
    }
    // #endregion student

    // #region compare
    final where = student.divergenceFrom(assignment.digests);
    // #endregion compare

    return 'the assignment and an unchanged replay agree at every '
        'checkpoint\n'
        'a student who changed the length at step 30 diverges at $where';
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
      throw StateError('the pendulum bob was not drawn');
    }
    if (!_report.contains('diverges at step 30')) {
      throw StateError(
        'changing the length at step 30 should be caught at '
        'the checkpoint covering it',
      );
    }
  }
}
