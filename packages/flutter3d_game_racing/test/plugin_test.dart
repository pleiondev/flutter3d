import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ring_track.dart';

/// A one-car race on the ring, behind the lights, as the headless game
/// lines it up.
RestorableRun _run(InputState input, {int rivals = 0}) =>
    RacingHeadlessGame(
          track: ringTrack(),
          rivals: rivals,
        ).start(Level(name: 'ring'), CollisionWorld(), input)
        as RestorableRun;

void main() {
  group('RacingPlugin', () {
    test('steps its race in the physics phase, and nothing else', () {
      final plugin = RacingPlugin();
      final loop = EngineLoop(
        input: InputState(),
        plugins: <Flutter3dPlugin>[plugin],
      );
      // Mutation: register the step in `rules`, after a game's own rules have
      // read last step's race. The phase is the plugin's promise to a game
      // that writes its drivers' inputs in `input` and reads laps in
      // `publish`.
      expect(loop.systemsIn(LoopPhase.physics), <String>[
        RacingPlugin.stepSystem,
      ]);
      for (final phase in LoopPhase.stepPhases) {
        if (phase == LoopPhase.physics) continue;
        expect(loop.systemsIn(phase), isEmpty, reason: phase.name);
      }
      // A loop with no race staged steps nothing, and does not throw.
      expect(() => loop.runSteps(3), returnsNormally);
    });

    test('steps the race it is given, a step a step', () {
      final plugin = RacingPlugin();
      final loop = EngineLoop(
        input: InputState(),
        plugins: <Flutter3dPlugin>[plugin],
      );
      final sim = RacingSimulation(
        collision: CollisionWorld(),
        vehicles: const <VehicleController>[],
        race: RaceState(mode: RaceMode.race, track: ringTrack(), racers: 0),
      );
      plugin.simulation = sim;
      loop.runSteps(30);
      // Mutation: step with a `dt` of the plugin's own rather than the
      // loop's. Thirty steps of the world's rate are half a second of race.
      expect(sim.race.elapsed, closeTo(30 * loop.stepSeconds, 1e-9));
    });

    test('declares the genre\'s own events under racing. names', () {
      final loop = EngineLoop(
        input: InputState(),
        plugins: <Flutter3dPlugin>[RacingPlugin()],
      );
      // The genre's own, beside the ones every genre shares (`actor.hurt`
      // and the rest), which the first genre installed declares.
      final declared = <EventDeclaration>[
        for (final d in loop.events.declared)
          if (d.name.startsWith('racing.')) d,
      ];
      // Mutation: drop a declaration. A tool lists what a game says from
      // here, and an event left out is one an agent never learns to wait for.
      expect(<String>[
        for (final d in declared) d.name,
      ], RacingPlugin.eventNames);
      expect(declared.every((d) => d.declaredBy == RacingPlugin.id), isTrue);
      // Mutation: declare one without its codec. Its digest would fall back
      // to the name alone, and two runs that lapped in different times
      // would publish the same digest.
      expect(declared.every((d) => d.codec != null), isTrue);
      expect(
        declared.firstWhere((d) => d.name == 'racing.lapCompleted').type,
        LapCompleted,
      );
    });

    test('puts the race\'s events on the step channel, under their declared '
        'names', () {
      final plugin = RacingPlugin();
      final loop = EngineLoop(
        input: InputState(),
        plugins: <Flutter3dPlugin>[plugin],
      );
      final heard = <String>[];
      loop.events.onStep<CountdownTicked>(
        'test',
        (Delivered<CountdownTicked> d) => heard.add(d.event.name),
      );
      final sim = RacingSimulation(
        collision: CollisionWorld(),
        vehicles: const <VehicleController>[],
        race: RaceState(mode: RaceMode.race, track: ringTrack(), racers: 0),
      );
      plugin.simulation = sim;
      // A second and a bit: the first light goes out.
      loop.runSteps(70);
      // Mutation: forget to hand the race the bus. It would publish
      // nowhere, and nothing on the bus would hear the lights.
      expect(heard, isNotEmpty);
      expect(heard.toSet(), <String>{CountdownTicked.eventName});
    });

    test('a race swapped out stops reaching the bus', () {
      final plugin = RacingPlugin();
      final loop = EngineLoop(
        input: InputState(),
        plugins: <Flutter3dPlugin>[plugin],
      );
      var heard = 0;
      loop.events.onStep<CountdownTicked>('test', (_) => heard++);
      final old = RacingSimulation(
        collision: CollisionWorld(),
        vehicles: const <VehicleController>[],
        race: RaceState(mode: RaceMode.race, track: ringTrack(), racers: 0),
      );
      plugin
        ..simulation = old
        ..simulation = null;
      // Stepped by hand, as a level's leftovers might be.
      for (var i = 0; i < 70; i++) {
        loop.runSteps(1);
        old.step(loop.stepSeconds);
      }
      // Mutation: keep the old race's bus when it is swapped. A torn
      // down circuit would go on speaking on the bus of the next one.
      expect(heard, 0);
    });

    test('switched off, it takes its step and its events with it', () {
      final plugin = RacingPlugin();
      final loop = EngineLoop(
        input: InputState(),
        plugins: <Flutter3dPlugin>[plugin],
      );
      loop.plugins.disable(RacingPlugin.id);
      loop.runSteps(1);
      // Mutation: register through the loop itself rather than the host's
      // scoped registry. Nothing would be tracked and nothing withdrawn.
      expect(loop.systemsIn(LoopPhase.physics), isEmpty);
      // The engine's own (the floating origin) stays: it is the
      // application's.
      expect(loop.events.declared.where((d) => d.declaredBy != 'app'), isEmpty);
    });
  });

  group('RacingHeadlessGame', () {
    test('drives the player from the stick', () {
      final input = InputState();
      final run = _run(input);
      // Through the lights first: three seconds behind them.
      for (var i = 0; i < 200; i++) {
        run.step(1 / 60);
      }
      final from = run.position;
      input.press(GameAction.moveForward);
      for (var i = 0; i < 120; i++) {
        run.step(1 / 60);
      }
      // Mutation: read the throttle from the game's own `throttle` action,
      // which no blind tool holds. The car would stay on the grid.
      expect(run.position.distanceTo(from), greaterThan(1.0));
      expect(run.outcome, RunOutcome.playing);
    });

    test('says which simulation it is', () {
      final game = RacingHeadlessGame(track: ringTrack());
      // Mutation: name the engine's version alone. A tool would play a
      // racing run recorded on other rules.
      expect(game.simulation, racingSimulationVersion);
      expect(game.name, 'racing');
      expect(game.buttons.keys, contains('handbrake'));
    });

    test('a saved run comes back to the same place', () {
      final input = InputState()..press(GameAction.moveForward);
      final run = _run(input, rivals: 2);
      for (var i = 0; i < 240; i++) {
        run.step(1 / 60);
      }
      final saved = run.save();
      final at = run.position;
      for (var i = 0; i < 60; i++) {
        run.step(1 / 60);
      }
      run.restore(saved);
      // Mutation: restore the race and not the cars. The car would stay a
      // second further on.
      expect(run.position.distanceTo(at), lessThan(1e-9));
    });

    test('says where the car is in the world when the origin has moved', () {
      // Mutation: read the car's position with the default origin, as the
      // run did — five kilometres from the origin the car is reported five
      // kilometres from where it stands.
      final world = CollisionWorld();
      final run = RacingHeadlessGame(
        track: ringTrack(),
      ).start(Level(name: 'ring'), world, InputState());
      final before = run.position;
      final eye = run.eye;
      world.moveOriginTo(const WorldPosition(5000.0, 0.0, 0.0));
      expect(run.position.distanceTo(before), lessThan(1e-3));
      expect(run.eye.distanceTo(eye), lessThan(1e-3));
    });
  });
}
