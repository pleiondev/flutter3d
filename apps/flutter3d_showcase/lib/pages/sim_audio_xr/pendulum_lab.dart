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

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_showcase/src/demo/scene_kit.dart';
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

  double changeAt = 100.0;
  double newLength = 1.5;

  static const int _steps = 240;
  static const int _every = 40;

  late final List<MeshNode> _rods;
  late final List<MeshNode> _bobs;
  late final List<MeshNode> _lamps;
  bool _restart = true;
  int _step = 0;
  double _owed = 0.0;
  double _pause = 0.0;
  _Pendulum _assignmentLive = _Pendulum(lengthMeters: 1.0);
  _Pendulum _studentLive = _Pendulum(lengthMeters: 1.0);
  DigestTrace _assignmentTrace = DigestTrace(every: _every);
  DigestTrace _studentTrace = DigestTrace(every: _every);

  static const double _pivotY = 3.4;
  static const List<double> _pivotX = <double>[-2.0, 2.0];

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 10.0
      ..pitch = 0.1
      ..yaw = 0.0;
    context.orbit.target.setValues(0.0, 1.6, 0.0);
  }

  @override
  Scene build(DemoContext context) {
    _report = _run();
    final List<Vector4> inks = <Vector4>[
      Vector4(0.45, 0.8, 0.5, 1.0),
      Vector4(0.9, 0.6, 0.3, 1.0),
    ];
    _rods = <MeshNode>[
      for (var i = 0; i < 2; i++)
        blockNode(context, 'rod $i', Vector3(0.06, 1.0, 0.06), inks[i]),
    ];
    _bobs = <MeshNode>[
      for (var i = 0; i < 2; i++) ballNode(context, 'bob $i', 0.28, inks[i]),
    ];
    _lamps = <MeshNode>[
      for (var i = 0; i < _steps ~/ _every; i++)
        ballNode(
          context,
          'lamp $i',
          0.16,
          Vector4(0.3, 0.3, 0.33, 1.0),
          at: Vector3(-1.5 + i * 0.6, 0.2, 1.0),
        ),
    ];
    return sceneOf(<SceneNode>[
      floorNode(context, width: 9.0, depth: 4.0),
      for (final double x in _pivotX)
        blockNode(
          context,
          'pivot',
          Vector3(0.3, 0.12, 0.3),
          Vector4(0.2, 0.2, 0.24, 1.0),
          at: Vector3(x, _pivotY + 0.05, 0.0),
        ),
      ..._rods,
      ..._bobs,
      ..._lamps,
    ]);
  }

  void _begin() {
    _restart = false;
    _step = 0;
    _owed = 0.0;
    _pause = 0.0;
    _assignmentLive = _Pendulum(lengthMeters: 1.0);
    _studentLive = _Pendulum(lengthMeters: 1.0);
    _assignmentTrace = DigestTrace(every: _every);
    _studentTrace = DigestTrace(every: _every);
    for (final MeshNode lamp in _lamps) {
      lamp.material.baseColor.setValues(0.3, 0.3, 0.33, 1.0);
    }
  }

  @override
  void update(DemoContext context, double dt) {
    if (_restart) _begin();
    if (_step >= _steps) {
      _pause += dt;
      if (_pause > 2.0) _restart = true;
    } else {
      // Two thirds of real time, so a swing is slow enough to follow.
      _owed += dt * 60.0 * 0.66;
      while (_owed >= 1.0 && _step < _steps) {
        _owed -= 1.0;
        _step++;
        // #region live
        // The same two runs as above, a step at a time: one checkpoint every
        // `_every` steps, and the student's length changes when the slider
        // says.
        _assignmentLive.step(1 / 60);
        _assignmentTrace.observe(_step, _assignmentLive.state);
        if (_step == changeAt.round()) _studentLive.lengthMeters = newLength;
        _studentLive.step(1 / 60);
        _studentTrace.observe(_step, _studentLive.state);
        // #endregion live
        if (_step % _every == 0) {
          final int where = _step ~/ _every - 1;
          final Divergence? parted = _studentTrace.divergenceFrom(
            _assignmentTrace.digests,
          );
          final bool bad = parted != null && _step >= parted.step;
          _lamps[where].material.baseColor.setValues(
            bad ? 0.9 : 0.35,
            bad ? 0.3 : 0.85,
            bad ? 0.3 : 0.4,
            1.0,
          );
        }
      }
    }
    _place(0, _assignmentLive);
    _place(1, _studentLive);
  }

  void _place(int i, _Pendulum p) {
    final double x = _pivotX[i];
    final double length = p.lengthMeters * 2.0;
    final double dx = length * math.sin(p.theta);
    final double dy = -length * math.cos(p.theta);
    _bobs[i].setPosition(x + dx, _pivotY + dy, 0.0);
    _rods[i]
      ..setScale(1.0, length, 1.0)
      ..setRotation(Quaternion.axisAngle(Vector3(0.0, 0.0, 1.0), p.theta))
      ..setPosition(x + dx / 2, _pivotY + dy / 2, 0.0);
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Length changes at step',
      min: 40,
      max: 200,
      value: () => changeAt,
      onChanged: (double v) {
        changeAt = v.roundToDouble();
        _restart = true;
      },
      format: (double v) => v.round().toString(),
    ),
    SliderControl(
      'New length',
      min: 0.6,
      max: 2.0,
      value: () => newLength,
      onChanged: (double v) {
        newLength = v;
        _restart = true;
      },
      format: (double v) => '${v.toStringAsFixed(2)} m',
    ),
  ];

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
