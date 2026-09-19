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

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

final class ReplayDigestDemo extends ShowcaseDemo {
  late final String _report;

  @override
  Scene build(DemoContext context) {
    _report = _run();
    final material = Material(
      name: 'tape',
      baseColor: Vector4(0.6, 0.5, 0.9, 1.0),
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
