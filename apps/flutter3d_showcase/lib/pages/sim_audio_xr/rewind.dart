/// The last few seconds of a run, kept as one snapshot a second and the raw
/// inputs between them, so a game can live them again for a kill camera or a
/// rewind mechanic; and what each step of that run actually cost.
///
/// Quoted by `rewind.md` and shown whole in the Source tab.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

final class RewindDemo extends ShowcaseDemo {
  late final String _report;

  @override
  Scene build(DemoContext context) {
    _report = _run();
    final material = Material(
      name: 'runner',
      baseColor: Vector4(0.5, 0.8, 0.6, 1.0),
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
