/// The platformer as a plugin: what it puts into an engine, and what it
/// takes out again.
///
///     flutter test test/plugin_test.dart
///
/// Beside it the two pieces the plugin rests on: the simulation's snapshot
/// parts — what a game steps beside the genre saves with the run — and the
/// genre as a tool plays it blind.
library;

import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

/// A floor and somebody standing on it.
Level _floor() => Level.fromJson(<String, Object?>{
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

({PlatformerStaged staged, InputState input}) _stage() {
  final level = _floor();
  final world = CollisionWorld();
  level.addTo(world);
  final input = InputState();
  final staged = stagePlatformer(level, world, input: input);
  world.update();
  return (staged: staged, input: input);
}

/// A counter beside the run, saved as one of its parts.
final class _Tally {
  int count = 0;

  PlatformerSnapshotPart get part => (
    save: () => count,
    restore: (Object? saved) => count = saved is int ? saved : 0,
  );
}

void main() {
  group('PlatformerPlugin', () {
    test(
      'installs its step in the physics phase, its events and its kinds',
      () {
        // Mutation: add the step to `rules`, or under another name, and the
        // first expectation fails. Mutation: drop a declaration, and the
        // landing is not listed. Mutation: add the format's own kinds, and the
        // spawn point is claimed by the genre.
        final plugin = PlatformerPlugin();
        final kinds = EntityKinds();
        final loop = EngineLoop(
          input: InputState(),
          registries: <PluginRegistry>[kinds],
          plugins: <Flutter3dPlugin>[plugin],
        );

        expect(loop.systemsIn(LoopPhase.physics), <String>[
          PlatformerPlugin.stepSystem,
        ]);
        // The engine's own (the floating origin) is the application's.
        final ours = <EventDeclaration>[
          for (final d in loop.events.declared)
            if (d.declaredBy != 'app') d,
        ];
        final declared = <String>[for (final d in ours) d.name];
        expect(declared, contains('platformer.landed'));
        expect(declared, contains('platformer.runnerDied'));
        // The events every genre shares are `flutter3d_sim`'s and the
        // engine's to declare, so switching a genre off never takes them
        // from the others; everything this genre declares is named under it.
        final shared = <String>{
          ActorHurt.eventName,
          ActorDied.eventName,
          SequenceSignal.eventName,
        };
        expect(<String>[
          for (final d in loop.events.declared)
            if (shared.contains(d.name) && d.declaredBy == 'app') d.name,
        ], containsAll(shared));
        expect(
          declared.every((name) => name.startsWith('platformer.')),
          isTrue,
          reason: 'two genres in one engine must never claim one name',
        );
        expect(ours.every((d) => d.declaredBy == PlatformerPlugin.id), isTrue);
        expect(kinds.knows(PlatformerEntities.collectible), isTrue);
        expect(kinds.ownerOf(PlatformerEntities.crate), PlatformerPlugin.id);
        expect(kinds.knows(EntityTypes.playerSpawn), isFalse);
        expect(plugin.manifest.touches, PluginTouches.simulation);
        expect(plugin.manifest.permissions, isEmpty);
      },
    );

    test('steps the run it is given, and points its events at the bus', () {
      // Mutation: step nothing in the system, and the clock does not move.
      // Mutation: leave the run unpublished, and the bus hears nothing.
      final plugin = PlatformerPlugin();
      final loop = EngineLoop(
        input: InputState(),
        plugins: <Flutter3dPlugin>[plugin],
      );
      final (:staged, input: _) = _stage();
      final heard = <String>[];
      loop.events.onStep<GameEvent>('test', (d) => heard.add(d.event.name));

      loop.runSteps(3);
      expect(staged.sim.elapsed, 0.0, reason: 'no run is attached yet');

      plugin.simulation = staged.sim;
      loop.runSteps(30);
      expect(staged.sim.elapsed, closeTo(30 * loop.stepSeconds, 1e-9));

      // An event the run publishes inside a step reaches the step channel:
      // the runner's bus is the engine's while the run is the genre's.
      var say = true;
      loop.addSystem('test.say', LoopPhase.rules, (_) {
        if (say) staged.sim.runner.events?.publish(const RunnerDied());
        say = false;
      });
      loop.runSteps(1);
      // The runner comes down on the floor in this step too, and says so.
      expect(heard, contains(RunnerDied.eventName));
      final spoken = heard.length;

      // Swapped away, the old run neither steps nor speaks.
      plugin.simulation = null;
      final before = staged.sim.elapsed;
      say = true;
      loop.runSteps(5);
      expect(staged.sim.elapsed, before);
      expect(
        heard,
        hasLength(spoken),
        reason: 'the run no longer publishes onto the bus',
      );
    });

    test('switched off, takes out everything it put in', () {
      // Mutation: keep a registration outside the host's tracking — the
      // forward, a kind — and it outlives the plugin.
      final plugin = PlatformerPlugin();
      final kinds = EntityKinds();
      final loop = EngineLoop(
        input: InputState(),
        registries: <PluginRegistry>[kinds],
        plugins: <Flutter3dPlugin>[plugin],
      );
      final (:staged, input: _) = _stage();
      plugin.simulation = staged.sim;

      loop.plugins.disable(PlatformerPlugin.id);
      loop.runSteps(1);

      expect(loop.systemsIn(LoopPhase.physics), isEmpty);
      expect(loop.events.declared.where((d) => d.declaredBy != 'app'), isEmpty);
      expect(kinds.types, isEmpty);
      final before = staged.sim.elapsed;
      loop.runSteps(10);
      expect(staged.sim.elapsed, before);
    });
  });

  group('PlatformerSimulation.parts', () {
    test('a part is saved with the run and handed its own back', () {
      // Mutation: write the parts and not read them, and the count stays
      // where it was moved to.
      final (:staged, input: _) = _stage();
      final tally = _Tally()..count = 7;
      staged.sim.parts['tally'] = tally.part;
      final saved = staged.sim.save();
      tally.count = 40;
      staged.sim.restore(saved);
      expect(tally.count, 7);
    });

    test('a save from before parts hands the old elements their state', () {
      // The demo's elements rode in the dynamics, saved under `bodies` and
      // `elements`; a save written then still restores both halves.
      //
      // Mutation: hand the whole map to the dynamics, and the part is given
      // null.
      final (:staged, input: _) = _stage();
      final tally = _Tally();
      staged.sim.parts['elements'] = tally.part;
      final now = staged.sim.save().data;
      final old = Snapshot(
        <String, Object?>{
          ...now,
          'dynamics': <String, Object?>{
            'bodies': now['dynamics'],
            'elements': 5,
          },
        }..remove('parts'),
      );
      staged.sim.restore(old);
      expect(tally.count, 5);
    });

    test('movedThisStep says whether the world moved', () {
      // Mutation: set it before the early returns, and a finished run says
      // it moved.
      final (:staged, input: _) = _stage();
      staged.sim.step(_dt);
      expect(staged.sim.didMoveThisStep, isTrue);
      staged.sim.state = RunState.finished;
      staged.sim.step(_dt);
      expect(staged.sim.didMoveThisStep, isFalse);
    });
  });

  group('PlatformerHeadlessGame', () {
    test('plays a level blind and says where the runner is', () {
      // Mutation: start the run without staging it, and there is no runner
      // to read.
      const game = PlatformerHeadlessGame();
      expect(game.simulation, platformerSimulationVersion);
      final level = _floor();
      final world = CollisionWorld();
      level.addTo(world);
      final input = InputState()..press(GameAction.moveForward);
      final run = game.start(level, world, input);
      world.update();
      final from = run.position;
      for (var i = 0; i < 30; i++) {
        input.beginStep();
        run.step(_dt);
        input.endStep();
      }
      expect(run.position.distanceTo(from), greaterThan(0.5));
      expect(run.outcome, RunOutcome.playing);
      expect(run.reading['state'], 'running');
      final aim = Vector3.zero();
      run.aim(aim);
      expect(aim.length, closeTo(1.0, 1e-9));
    });

    test('says where the runner is in the world when the origin has moved', () {
      // Mutation: read the body's position with the default origin, as the
      // run did — five kilometres from the origin the runner is reported
      // five kilometres from where it stands.
      final level = _floor();
      final world = CollisionWorld();
      level.addTo(world);
      final run = const PlatformerHeadlessGame().start(
        level,
        world,
        InputState(),
      );
      world.update();
      final before = run.position;
      final eye = run.eye;
      world.moveOriginTo(const WorldPosition(5000.0, 0.0, 0.0));
      expect(run.position.distanceTo(before), lessThan(1e-3));
      expect(run.eye.distanceTo(eye), lessThan(1e-3));
    });
  });
}
