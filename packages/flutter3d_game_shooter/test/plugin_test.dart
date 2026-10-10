/// The shooter installed into an engine as a plugin, and taken out again.
///
///     flutter test test/plugin_test.dart
///
/// **What the plugin promises is that the engine steps the game and nothing
/// else does**: one system in the physics phase, the genre's own events
/// declared and carried on the bus, the kinds it was given in the engine's
/// registry — and all of it gone when the plugin is switched off. The order
/// inside the step is `step_phases_test.dart`'s; this file is the wiring.
library;

import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

GameSimulation _sim(InputState input) {
  final world = CollisionWorld()
    ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(20.0, 1.0, 20.0));
  final player = Player(
    body: CharacterController(world: world, position: Vector3(0.0, 0.9, 0.0)),
  );
  final mechanisms = MechanismWorld(world);
  world.update();
  return GameSimulation(
    random: GameRandom(1),
    player: player,
    collision: world,
    input: input,
    mechanisms: mechanisms,
  );
}

void main() {
  late InputState input;
  late GameSimulation sim;
  late ShooterPlugin plugin;
  late EntityKinds kinds;
  late EngineLoop loop;
  late int stepped;

  setUp(() {
    input = InputState();
    sim = _sim(input);
    stepped = 0;
    sim.systems.add(StepPhase.begin, (StepContext _) => stepped++);
    plugin = ShooterPlugin(kinds: const <EntityKind>[SecretKind(), NoteKind()])
      ..simulation = sim;
    kinds = EntityKinds();
    loop = EngineLoop(
      input: input,
      plugins: <Flutter3dPlugin>[plugin],
      registries: <PluginRegistry>[kinds],
    );
  });

  test('the step is one system in the physics phase', () {
    // Mutation: register `shooter.step` in `LoopPhase.rules` — fails here.
    expect(loop.systemsIn(LoopPhase.physics), <String>[
      ShooterPlugin.stepSystem,
    ]);
    loop.runSteps(3);
    // Mutation: step with nothing (`(_) {}`) — the count stays 0.
    expect(stepped, 3, reason: 'the engine steps the simulation, once a step');
  });

  test('the genre declares its own events, and the bus carries them', () {
    final names = <String>[
      for (final d in loop.events.declared)
        if (d.declaredBy == ShooterPlugin.id) d.name,
    ];
    // Mutation: drop the `PlayerDied` declaration — the list is short a name.
    expect(
      names,
      containsAll(<String>[ShotFired.eventName, PlayerDied.eventName]),
    );
    expect(
      names.every((n) => n.startsWith('shooter.')),
      isTrue,
      reason: 'a genre combined with another must not claim a bare name',
    );

    final heard = <int>[];
    loop.events.onStep<PlayerDied>('test', (d) => heard.add(d.step));
    sim.systems.add(StepPhase.end, (StepContext _) => sim.hurtPlayer(1e9));
    loop.runSteps(1);
    // Mutation: `publishEvents` not overridden — nothing reaches the bus.
    expect(heard, <int>[0]);
    expect(
      loop.events.declared
          .singleWhere((d) => d.name == PlayerDied.eventName)
          .codec,
      isNotNull,
      reason: 'declared without a codec, a digest cannot read the event',
    );
  });

  test('a new simulation is stepped and forwarded in place of the old', () {
    final next = _sim(input);
    var nextStepped = 0;
    next.systems.add(StepPhase.begin, (StepContext _) => nextStepped++);
    plugin.simulation = next;
    final heard = <String>[];
    loop.events.onStep<SecretFound>('test', (d) => heard.add('found'));
    loop.events.onStep<PlayerDied>('test', (d) => heard.add('died'));
    // The old run speaks from inside a step, where a bus it still held would
    // put it on the step channel.
    loop.addSystem(
      'test.old run',
      LoopPhase.publish,
      (LoopContext _) => sim.hurtPlayer(1e9),
    );
    loop.runSteps(1);
    // Mutation: leave the old run on the bus — the old run's event is heard.
    expect(heard, isEmpty, reason: 'the old run no longer speaks on the bus');
    expect((stepped, nextStepped), (0, 1));
  });

  test('the kinds it was given are the engine’s while it is on', () {
    // Mutation: drop `addAll(kinds)` — neither type is known.
    expect(kinds.knows(ShooterEntities.secret), isTrue);
    expect(kinds.ownerOf(ShooterEntities.note), ShooterPlugin.id);
  });

  test('switched off, everything it registered goes', () {
    loop.plugins.disable(ShooterPlugin.id);
    loop.runSteps(2);
    // Mutation: keep a registration outside the host — one of these stays.
    expect(loop.systemsIn(LoopPhase.physics), isEmpty);
    expect(stepped, 0, reason: 'nothing steps a switched-off genre');
    expect(kinds.knows(ShooterEntities.secret), isFalse);
    expect(
      loop.events.declared.where((d) => d.declaredBy == ShooterPlugin.id),
      isEmpty,
    );
  });
}
