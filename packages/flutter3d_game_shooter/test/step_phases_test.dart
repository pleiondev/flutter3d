/// A rule this genre never heard of, running inside its step.
///
///     flutter test test/step_phases_test.dart
///
/// **What a plugin boundary is worth is where its seams are**, and a registry
/// that announced one phase at the end of the step would be a boundary in name
/// only: a curse that ticks, a floor that burns, a score that decays are all
/// rules about *when*. So this file is mostly about the order the phases are
/// announced in and about what is true by the time each one is — the same
/// argument `WorldStep` makes about the six calls it holds.
///
/// `step_systems_test.dart` in `flutter3d_game` covers the registry itself.
/// Nothing here re-tests it; what is tested here is the wiring.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

CollisionWorld _ground() {
  final world = CollisionWorld();
  world.addBox(Vector3(0.0, -0.5, 0.0), Vector3(20.0, 1.0, 20.0));
  return world;
}

({GameSimulation sim, Player player, InputState input}) _harness() {
  final world = _ground();
  final input = InputState();
  final player = Player(
    body: CharacterController(world: world, position: Vector3(0.0, 0.9, 0.0)),
  );
  final mechanisms = MechanismWorld(world);
  world.update();
  return (
    sim: GameSimulation(
      random: GameRandom(1),
      player: player,
      collision: world,
      input: input,
      mechanisms: mechanisms,
    ),
    player: player,
    input: input,
  );
}

/// The phases this genre announces, in the order it announces them.
const List<StepPhase> _order = <StepPhase>[
  StepPhase.begin,
  ShooterPhases.afterPlayer,
  ShooterPhases.afterWorld,
  ShooterPhases.afterWeapons,
  ShooterPhases.afterActors,
  StepPhase.end,
];

void main() {
  test('every phase is announced, once, in the documented order', () {
    // **The documentation is on `ShooterPhases` and this is what holds it to
    // being true.** A phase announced out of the order its own doc comment
    // gives is worse than an undocumented one: somebody would have written a
    // rule against the sentence.
    //
    // Mutation: move any `systems.run` line — fails here, naming both orders.
    final harness = _harness();
    final seen = <String>[];
    for (final phase in _order) {
      harness.sim.systems.add(phase, (_) => seen.add(phase.name));
    }

    harness.sim.step(_dt);

    expect(seen, <String>[for (final phase in _order) phase.name]);
  });

  test('and a level with no doors announces them all the same', () {
    // **Announced unconditionally, which is the whole reason a phase can be
    // relied on.** `afterWorld` sits beside the mechanism block, and the
    // tempting shape is to announce it inside — where it would exist only on
    // levels that happen to have a door, and a rule written against it would
    // work in the crypt and not in the arena.
    //
    // Mutation: move the `afterWorld` announcement inside `if (doors != null)`
    // — fails here and passes the test above, which has mechanisms.
    final world = _ground();
    final input = InputState();
    final sim = GameSimulation(
      random: GameRandom(1),
      player: Player(
        body:
            CharacterController(world: world, position: Vector3(0.0, 0.9, 0.0)),
      ),
      collision: world,
      input: input,
    );
    final seen = <String>[];
    for (final phase in _order) {
      sim.systems.add(phase, (_) => seen.add(phase.name));
    }

    sim.step(_dt);

    expect(seen, <String>[for (final phase in _order) phase.name]);
  });

  test('and a system sees the player where this step left them', () {
    // What `afterPlayer` claims. The player is walking; a rule reading their
    // position at that phase must read the position this step produced, not the
    // one the previous step ended on.
    //
    // Mutation: announce `afterPlayer` before `player.body.step` — the observed
    // position is a step stale and this fails.
    final harness = _harness();
    harness.input.setStickAxis(0.0, 1.0);

    var observed = 0.0;
    harness.sim.systems.add(
      ShooterPhases.afterPlayer,
      (_) => observed = harness.player.body.position.z,
    );

    for (var i = 0; i < 30; i++) {
      harness.sim.step(_dt);
    }

    expect(observed, harness.player.body.position.z);
    expect(observed.abs(), greaterThan(0.1),
        reason: 'a player who never moved would prove nothing');
  });

  test('and the state a system reads at the end is this step\'s', () {
    // What `StepPhase.end` claims: the game state is resolved by then. A rule
    // that reacts to the player dying — a message, a sound, a save — should not
    // be a step behind the death.
    //
    // Mutation: announce `end` before the `!player.isAlive` check — the system
    // sees `playing` on the step the player died and this fails.
    final harness = _harness();
    final states = <GameState>[];
    harness.sim.systems.add(StepPhase.end, (_) => states.add(harness.sim.state));

    harness.sim.step(_dt);
    harness.player.applyDamage(1000.0);
    harness.sim.step(_dt);

    expect(states, <GameState>[GameState.playing, GameState.dead]);
  });

  test('and a system that unregisters itself leaves the step alone', () {
    // A scripted event is the ordinary case, not an exotic one. Covered as a
    // property of the registry elsewhere; covered here because it has to hold
    // while a real step is running through it.
    final harness = _harness();
    var ran = 0;
    late SystemRegistration once;
    once = harness.sim.systems.add(ShooterPhases.afterActors, (_) {
      ran++;
      harness.sim.systems.remove(once);
    });

    harness.sim.step(_dt);
    harness.sim.step(_dt);

    expect(ran, 1);
  });
}
