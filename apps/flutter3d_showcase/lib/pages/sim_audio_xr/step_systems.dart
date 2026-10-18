/// Work a game adds to the loop's fixed step without owning the step itself,
/// and the events a step reports so a frame can react without polling.
///
/// Quoted by `step_systems.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_showcase/src/demo/scene_kit.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

final class _ScoreChanged extends GameEvent {
  const _ScoreChanged(this.total);
  final int total;

  @override
  String get name => 'ScoreChanged($total)';
}

/// The `step-systems` page: a coin collected by systems added to the fixed
/// step. Its check is that a lower order runs first whatever the
/// registration order, and that a removed system does not run.
final class StepSystemsDemo extends ShowcaseDemo {
  late final String _report;

  /// Whether scoring runs before input rather than after it.
  bool scoringFirst = false;

  /// Whether the logging system is registered.
  bool loggingOn = true;

  bool _dirty = true;
  late EngineLoop _loop;
  final List<String> _ran = <String>[];
  late final List<MeshNode> _slots;
  late final BarGauge _tower;
  int _score = 0;
  double _sinceStep = 0.0;

  static const Map<String, List<double>> _colors = <String, List<double>>{
    'input': <double>[0.45, 0.65, 0.95],
    'scoring': <double>[0.95, 0.8, 0.3],
    'logging': <double>[0.75, 0.45, 0.85],
  };

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 10.0
      ..pitch = 0.75
      ..yaw = 0.0;
    context.orbit.target.setValues(1.0, 0.5, 0.0);
  }

  @override
  Scene build(DemoContext context) {
    _report = _run();
    _slots = <MeshNode>[
      for (var i = 0; i < 3; i++)
        blockNode(
          context,
          'slot $i',
          Vector3(1.4, 0.5, 1.4),
          Vector4(0.25, 0.26, 0.3, 1.0),
          at: Vector3(-1.5 + i * 2.0, 0.25, 1.5),
        ),
    ];
    _tower = BarGauge(
      context,
      'score',
      Vector4(0.95, 0.8, 0.3, 1.0),
      Vector3(-5.0, 0.0, 0.0),
      height: 4.0,
      width: 1.0,
      vertical: true,
    );
    return sceneOf(<SceneNode>[
      floorNode(context, width: 14.0, depth: 8.0),
      ..._slots,
      ..._tower.nodes,
    ]);
  }

  /// The three systems of the page, registered in one order and asked to run
  /// in another: `scoring` is registered before `input` and, unless the
  /// toggle says otherwise, named to run after it.
  void _register() {
    // #region live
    final loop = EngineLoop(input: InputState());
    loop.addSystem('scoring', LoopPhase.rules, (LoopContext step) {
      _ran.add('scoring');
      _score += 5;
    }, after: scoringFirst ? const <String>[] : const <String>['input']);
    loop.addSystem(
      'input',
      LoopPhase.rules,
      (LoopContext step) => _ran.add('input'),
    );
    if (loggingOn) {
      loop.addSystem(
        'logging',
        LoopPhase.rules,
        (LoopContext step) => _ran.add('logging'),
        after: const <String>['scoring', 'input'],
      );
    }
    // #endregion live
    _loop = loop;
  }

  @override
  void update(DemoContext context, double dt) {
    if (_dirty) {
      _dirty = false;
      _register();
    }
    _sinceStep += dt;
    if (_sinceStep >= 0.6) {
      _sinceStep = 0.0;
      _ran.clear();
      _loop.runSteps(1);
      if (_score >= 100) _score = 0;
    }
    // Slot i shows whichever system ran i-th this step, dimming as the next
    // step approaches.
    final double glow = 1.0 - _sinceStep / 0.6;
    for (var i = 0; i < _slots.length; i++) {
      final List<double> c = i < _ran.length
          ? _colors[_ran[i]]!
          : const <double>[0.25, 0.26, 0.3];
      final double k = i < _ran.length ? 0.35 + 0.65 * glow : 1.0;
      _slots[i].material.baseColor = LinearColor.fromSrgb(
        c[0] * k,
        c[1] * k,
        c[2] * k,
        1.0,
      );
    }
    _tower.set(_score / 100.0);
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Scoring before input',
      value: () => scoringFirst,
      onChanged: (bool v) {
        scoringFirst = v;
        _dirty = true;
      },
    ),
    ToggleControl(
      'Logging registered',
      value: () => loggingOn,
      onChanged: (bool v) {
        loggingOn = v;
        _dirty = true;
      },
    ),
  ];

  static String _run() {
    // #region systems
    final loop = EngineLoop(input: InputState());
    // The bus the step publishes onto. A game's is its `EngineLoop`'s, whose
    // step channel is heard at the end of the step; this page wants each
    // event as it is published, so a `DirectBus`.
    final events = DirectBus();
    final heard = <GameEvent>[];
    events.onStep<GameEvent>('step_systems.heard', (d) => heard.add(d.event));
    var score = 0;
    final order = <String>[];

    final logging = loop.addSystem(
      'logging',
      LoopPhase.rules,
      (LoopContext step) => order.add('logging'),
      after: const <String>['scoring'],
    );
    loop.addSystem('scoring', LoopPhase.rules, (LoopContext step) {
      order.add('scoring');
      score += 5;
      events.publish(_ScoreChanged(score));
    });
    // #endregion systems

    // #region run
    // Registered "logging" first but named to run after "scoring": the
    // constraint wins, and only what nothing names falls back on
    // registration.
    loop.runSteps(1);
    final published = List<GameEvent>.of(heard);
    final firstOrder = List<String>.of(order);
    // #endregion run

    // #region remove
    // The handle `addSystem` returned removes the system again; a step run
    // after that no longer calls it.
    logging.cancel();
    order.clear();
    loop.runSteps(1);
    final afterRemoval = List<String>.of(order);
    // #endregion remove

    return 'ran in order: ${firstOrder.join(', ')}; '
        'score is now $score; '
        'events this step: ${published.map((GameEvent e) => e.name).join(', ')}; '
        'after removing logging: $afterRemoval';
  }

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
