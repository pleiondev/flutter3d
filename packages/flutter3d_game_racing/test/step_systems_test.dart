/// The systems a game hangs on a race's own moments: their order, the
/// phases they may go in, and the context they are handed.
///
///     flutter test test/step_systems_test.dart
library;

import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

import 'heard.dart';
import 'ring_track.dart';

const double _dt = 1.0 / 60.0;

RacingSimulation _race() => RacingSimulation(
  collision: CollisionWorld(),
  vehicles: const <VehicleController>[],
  race: RaceState(mode: RaceMode.race, track: ringTrack(), racers: 0),
);

void main() {
  test('the phases run in the order the step reaches them', () {
    // Mutation: run `end` before the cars' moment, or skip a phase, and the
    // list is not this.
    final sim = _race();
    final seen = <String>[];
    for (final phase in RacingPhases.all.reversed) {
      sim.addSystem('see ${phase.name}', phase, (LoopContext c) {
        seen.add(c.phase.name);
      });
    }
    sim.step(_dt);
    expect(seen, <String>[
      'racing.begin',
      'racing.afterVehicles',
      'racing.end',
    ]);
  });

  test('systems run in the order added, moved by after and before', () {
    // Mutation: sort by name, or ignore `before`, and the order changes.
    final sim = _race();
    final order = <String>[];
    sim
      ..addSystem('b', RacingPhases.end, (_) => order.add('b'))
      ..addSystem('a', RacingPhases.end, (_) => order.add('a'))
      ..addSystem(
        'first',
        RacingPhases.end,
        (_) => order.add('first'),
        before: <String>['b'],
      )
      ..addSystem(
        'last',
        RacingPhases.end,
        (_) => order.add('last'),
        after: <String>['a', 'not registered'],
      );
    sim.step(_dt);
    expect(order, <String>['first', 'b', 'a', 'last']);
    expect(sim.systemsIn(RacingPhases.end), order);
  });

  test('a phase the genre does not have, and a name used twice, are '
      'refused', () {
    // Mutation: drop either check and nothing throws.
    final sim = _race();
    expect(
      () => sim.addSystem('x', LoopPhase.rules, (_) {}),
      throwsArgumentError,
    );
    sim.addSystem('x', RacingPhases.begin, (_) {});
    expect(
      () => sim.addSystem('x', RacingPhases.end, (_) {}),
      throwsArgumentError,
    );
  });

  test('stepped by hand, a system is told the step, its dt and its phase, '
      'and publishes onto the race\'s bus', () {
    // Mutation: hand the system the loop phase, another dt, or drop the
    // publish, and an expectation fails.
    final sim = _race();
    final heard = Heard(sim);
    final steps = <int>[];
    sim.addSystem('watch', RacingPhases.afterVehicles, (LoopContext c) {
      steps.add(c.step);
      expect(c.dt, _dt);
      expect(c.phase, RacingPhases.afterVehicles);
      expect(() => c.world, throwsStateError);
      c.publish(const RaceFinished());
    });
    sim
      ..step(_dt)
      ..step(_dt);
    expect(steps, <int>[1, 2]);
    expect(heard.take().whereType<RaceFinished>(), hasLength(2));
  });

  test('in a loop, a system is handed the loop\'s context with the genre\'s '
      'phase', () {
    // Mutation: hand the system the loop's own context unchanged, and its
    // phase is `physics`.
    final plugin = RacingPlugin();
    final loop = EngineLoop(
      input: InputState(),
      plugins: <Flutter3dPlugin>[plugin],
    );
    final sim = _race();
    plugin.simulation = sim;
    final seen = <String>{};
    final steps = <int>[];
    sim.addSystem('watch', RacingPhases.begin, (LoopContext c) {
      seen.add(c.phase.name);
      steps.add(c.step);
    });
    loop.runSteps(3);
    expect(seen, <String>{'racing.begin'});
    expect(steps, hasLength(3));
  });

  test('a registration cancelled removes the system, even from inside it', () {
    // Mutation: walk the live list, or ignore the cancel, and the count is
    // not one.
    final sim = _race();
    var ran = 0;
    late final Registration once;
    once = sim.addSystem('once', RacingPhases.begin, (_) {
      ran++;
      once.cancel();
    });
    sim
      ..step(_dt)
      ..step(_dt);
    expect(ran, 1);
    expect(sim.systemsIn(RacingPhases.begin), isEmpty);
  });
}
