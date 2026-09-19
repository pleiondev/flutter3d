/// Work a game hangs off a fixed step without owning the step itself, and the
/// events a step reports so a frame can react without polling.
///
/// Quoted by `step_systems.md` and shown whole in the Source tab.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

final class _ScoreChanged extends GameEvent {
  const _ScoreChanged(this.total);
  final int total;

  @override
  String get name => 'ScoreChanged($total)';
}

final class StepSystemsDemo extends ShowcaseDemo {
  late final String _report;

  @override
  Scene build(DemoContext context) {
    _report = _run();
    final material = Material(
      name: 'coin',
      baseColor: Vector4(0.9, 0.8, 0.2, 1.0),
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
    // #region systems
    final systems = StepSystems();
    final events = GameEvents();
    var score = 0;
    final order = <String>[];

    final logging = systems.add(
      StepPhase.begin,
      (StepContext step) => order.add('logging'),
      order: 10,
      label: 'logging',
    );
    systems.add(
      StepPhase.begin,
      (StepContext step) {
        order.add('scoring');
        score += 5;
        events.add(_ScoreChanged(score));
      },
      order: 0,
      label: 'scoring',
    );
    // #endregion systems

    // #region run
    // Registered "logging" first but ordered after "scoring": order wins,
    // and only ties fall back on registration.
    systems.run(StepPhase.begin, 1 / 60);
    final drained = events.drain();
    final firstOrder = List<String>.of(order);
    // #endregion run

    // #region remove
    // The handle `add` returned removes the system again; a step run after
    // that no longer calls it.
    systems.remove(logging);
    order.clear();
    systems.run(StepPhase.begin, 1 / 60);
    final afterRemoval = List<String>.of(order);
    // #endregion remove

    return 'ran in order: ${firstOrder.join(', ')}; '
        'score is now $score; '
        'events this step: ${drained.map((GameEvent e) => e.name).join(', ')}; '
        'after removing logging: $afterRemoval';
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
      throw StateError('the coin was not drawn');
    }
    if (!_report.contains('ran in order: scoring, logging')) {
      throw StateError(
        'a lower order number should run first, whatever order '
        'the systems were registered in',
      );
    }
    if (!_report.contains('after removing logging: [scoring]')) {
      throw StateError('a removed system should not run on the next step');
    }
  }
}
