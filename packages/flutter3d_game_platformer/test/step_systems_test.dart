/// The systems a game hangs on the platformer's own moments: their order,
/// the phases they may go in, and the context they are handed.
///
///     flutter test test/step_systems_test.dart
library;

import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

import 'heard.dart';

const double _dt = 1.0 / 60.0;

PlatformerSimulation _run() {
  final level = Level.fromJson(<String, Object?>{
    'version': 1,
    'name': 'floor',
    'materials': <String, Object?>{
      'stone': <String, Object?>{'roughness': 1.0},
    },
    'brushes': <Object?>[
      <String, Object?>{
        'at': <double>[0.0, -0.5, 0.0],
        'size': <double>[20.0, 1.0, 20.0],
        'material': 'stone',
      },
    ],
    'entities': <Object?>[
      <String, Object?>{
        'type': 'player_spawn',
        'at': <double>[0.0, 0.0, 0.0],
      },
    ],
  });
  final world = CollisionWorld();
  level.addTo(world);
  final staged = stagePlatformer(level, world, input: InputState());
  world.update();
  return staged.sim;
}

void main() {
  test('the phases run in the order the step reaches them', () {
    // Mutation: run `end` before the runner's moment, or skip a phase, and
    // the list is not this.
    final sim = _run();
    final seen = <String>[];
    for (final phase in PlatformerPhases.all.reversed) {
      sim.addSystem('see ${phase.name}', phase, (LoopContext c) {
        seen.add(c.phase.name);
      });
    }
    sim.step(_dt);
    expect(seen, <String>[
      'platformer.begin',
      'platformer.afterRunner',
      'platformer.end',
    ]);
  });

  test('systems run in the order added, moved by after and before', () {
    // Mutation: sort by name, or ignore `before`, and the order changes.
    final sim = _run();
    final order = <String>[];
    sim
      ..addSystem('b', PlatformerPhases.begin, (_) => order.add('b'))
      ..addSystem('a', PlatformerPhases.begin, (_) => order.add('a'))
      ..addSystem(
        'first',
        PlatformerPhases.begin,
        (_) => order.add('first'),
        before: <String>['b'],
      )
      ..addSystem(
        'last',
        PlatformerPhases.begin,
        (_) => order.add('last'),
        after: <String>['a', 'not registered'],
      );
    sim.step(_dt);
    expect(order, <String>['first', 'b', 'a', 'last']);
    expect(sim.systemsIn(PlatformerPhases.begin), order);
  });

  test('a phase the genre does not have, and a name used twice, are '
      'refused', () {
    // Mutation: drop either check and nothing throws.
    final sim = _run();
    expect(
      () => sim.addSystem('x', LoopPhase.physics, (_) {}),
      throwsArgumentError,
    );
    sim.addSystem('x', PlatformerPhases.end, (_) {});
    expect(
      () => sim.addSystem('x', PlatformerPhases.begin, (_) {}),
      throwsArgumentError,
    );
  });

  test('stepped by hand, a system is told the step, its dt and its phase, '
      'and publishes onto the run\'s bus', () {
    // Mutation: hand the system the loop phase, a wall-clock dt, or drop
    // the publish, and an expectation fails.
    final sim = _run();
    final heard = Heard();
    sim.publishTo(heard.bus);
    final steps = <int>[];
    sim.addSystem('watch', PlatformerPhases.afterRunner, (LoopContext c) {
      steps.add(c.step);
      expect(c.dt, _dt);
      expect(c.phase, PlatformerPhases.afterRunner);
      expect(c.isResimulated, isFalse);
      expect(() => c.world, throwsStateError);
      c.publish(const RunnerDied());
    });
    sim
      ..step(_dt)
      ..step(_dt);
    expect(steps, <int>[1, 2]);
    expect(heard.take().whereType<RunnerDied>(), hasLength(2));
  });

  test('in a loop, a system is handed the loop\'s context with the genre\'s '
      'phase', () {
    // Mutation: hand the system the loop's own context unchanged, and its
    // phase is `physics`.
    final plugin = PlatformerPlugin();
    final loop = EngineLoop(
      input: InputState(),
      registries: <PluginRegistry>[EntityKinds()],
      plugins: <Flutter3dPlugin>[plugin],
    );
    final sim = _run();
    plugin.simulation = sim;
    final seen = <(String, int)>[];
    sim.addSystem('watch', PlatformerPhases.begin, (LoopContext c) {
      seen.add((c.phase.name, c.step));
      expect(() => c.world, returnsNormally);
    });
    loop.frame(loop.stepSeconds * 2.5);
    expect(seen.map(((String, int) s) => s.$1).toSet(), <String>{
      'platformer.begin',
    });
    expect(seen, isNotEmpty);
  });

  test('a registration cancelled removes the system, even from inside it', () {
    // Mutation: walk the live list, or ignore the cancel, and the count is
    // not one.
    final sim = _run();
    var ran = 0;
    late final Registration once;
    once = sim.addSystem('once', PlatformerPhases.end, (_) {
      ran++;
      once.cancel();
    });
    sim
      ..step(_dt)
      ..step(_dt);
    expect(ran, 1);
    expect(sim.systemsIn(PlatformerPhases.end), isEmpty);
  });
}
