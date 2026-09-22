/// A number that says whether two runs of the same simulation are the same
/// run, taken every so many steps so a divergence can be bracketed to where
/// it happened.
///
/// A `Demo` is the file this rides in: a level, the state a run started from,
/// its tape of inputs and this checkpoint trace, so a server can replay a
/// submitted run and know exactly where it stopped agreeing.
///
/// Quoted by `replay_digest.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_showcase/src/demo/scene_kit.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

final class ReplayDigestDemo extends ShowcaseDemo {
  late final String _report;

  double driftAt = 9.0;
  bool _dirty = true;
  late final List<BarGauge> _original;
  late final List<BarGauge> _replay;
  late final List<MeshNode> _lamps;

  static const int _checkpoints = 5;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 12.0
      ..pitch = 0.45
      ..yaw = 0.0;
    context.orbit.target.setValues(0.0, 1.4, 0.0);
  }

  @override
  Scene build(DemoContext context) {
    _report = _run();
    BarGauge tower(String name, Vector4 ink, double x, double z) => BarGauge(
      context,
      name,
      ink,
      Vector3(x, 0.0, z),
      height: 3.0,
      width: 0.8,
      vertical: true,
    );
    _original = <BarGauge>[
      for (var k = 0; k < _checkpoints; k++)
        tower(
          'original $k',
          Vector4(0.45, 0.65, 0.95, 1.0),
          -4.0 + k * 2.0,
          -0.8,
        ),
    ];
    _replay = <BarGauge>[
      for (var k = 0; k < _checkpoints; k++)
        tower('replay $k', Vector4(0.95, 0.65, 0.3, 1.0), -4.0 + k * 2.0, 0.8),
    ];
    _lamps = <MeshNode>[
      for (var k = 0; k < _checkpoints; k++)
        ballNode(
          context,
          'lamp $k',
          0.3,
          Vector4(0.3, 0.3, 0.33, 1.0),
          at: Vector3(-4.0 + k * 2.0, 3.7, 0.0),
        ),
    ];
    return sceneOf(<SceneNode>[
      floorNode(context, width: 12.0, depth: 5.0),
      for (final BarGauge g in _original) ...g.nodes,
      for (final BarGauge g in _replay) ...g.nodes,
      ..._lamps,
    ]);
  }

  @override
  void update(DemoContext context, double dt) {
    if (!_dirty) return;
    _dirty = false;
    // #region live
    // The original, and a replay that drifts by one from the chosen step on.
    // A checkpoint every four steps: the tower is the state there, and its
    // lamp is green while the two digests agree.
    final DigestTrace original = _record(20, (int step) => step);
    final DigestTrace replay = _record(
      20,
      (int step) => step >= driftAt.round() ? step + 1 : step,
    );
    // #endregion live
    for (var k = 0; k < _checkpoints; k++) {
      final int step = (k + 1) * 4;
      _original[k].set(step / 22.0);
      _replay[k].set((step >= driftAt.round() ? step + 1 : step) / 22.0);
      final bool same = original.digests[k] == replay.digests[k];
      _lamps[k].material.baseColor.setValues(
        same ? 0.35 : 0.9,
        same ? 0.85 : 0.3,
        same ? 0.4 : 0.3,
        1.0,
      );
    }
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Drift starts at step',
      min: 1,
      max: 21,
      value: () => driftAt,
      onChanged: (double v) {
        driftAt = v.roundToDouble();
        _dirty = true;
      },
      format: (double v) => v.round() > 20 ? 'never' : v.round().toString(),
    ),
  ];

  /// A toy step: a counter that walks forward, standing in for a simulation.
  static Map<String, Object?> _stepOf(int x) => <String, Object?>{'x': x};

  static DigestTrace _record(int steps, int Function(int step) valueAt) {
    final trace = DigestTrace(every: 4);
    for (var step = 1; step <= steps; step++) {
      trace.observe(step, _stepOf(valueAt(step)));
    }
    return trace;
  }

  static String _run() {
    // #region agree
    // Two recordings of the same run agree at every checkpoint.
    final original = _record(20, (int step) => step);
    final replay = _record(20, (int step) => step);
    final agree = replay.divergenceFrom(original.digests) == null;
    // #endregion agree

    // #region diverge
    // A replay whose state drifts from step 9 onward parts company with the
    // original at the first checkpoint after that.
    final drifted = _record(20, (int step) => step >= 9 ? step + 1 : step);
    final where = drifted.divergenceFrom(original.digests);
    // #endregion diverge

    // #region wire
    // What a `.f3drun` actually carries: the trace as hex digits, written
    // out and read back.
    final wireForm = original.toJson();
    final reread = DigestTrace.fromJson(wireForm);
    final roundTrips = reread.divergenceFrom(original.digests) == null;
    // #endregion wire

    return 'a faithful replay agrees: $agree\n'
        'a drifted one diverges at $where\n'
        'a trace written to JSON and read back still agrees: $roundTrips';
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the marker was not drawn');
    }
    if (!_report.contains('agrees: true')) {
      throw StateError('two recordings of the same run must agree');
    }
    // The drift starts at step 9; the checkpoint every 4 steps that first
    // covers it is step 12.
    if (!_report.contains('step 12')) {
      throw StateError(
        'the divergence should be reported at the first '
        'checkpoint that covers the drift',
      );
    }
    if (!_report.contains('still agrees: true')) {
      throw StateError('a trace should read back exactly what it wrote');
    }
  }
}
