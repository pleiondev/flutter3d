/// The one path for state, and the boundary the view reads through
/// (`tasks/1.0-arch-review.md`, Must 1 and decision A).
///
///     dart test test/one_path_test.dart
///
/// A genre's run is part of the loop's snapshots, so a rewind restores it; a
/// rewind that would restore nothing refuses; the view reads a run's actors
/// from published state; input handed to the simulation as values is queued
/// and lands on the tape; a question is asked by name. Each test was written
/// by breaking what it covers first; the mutation that would defeat it is
/// named in the test.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

/// A run that counts its steps and keeps the count in its own fields.
final class _Run {
  int steps = 0;

  Snapshot save() => Snapshot(<String, Object?>{'steps': steps});

  void restore(Snapshot state) => steps = state.data.integer('steps');
}

final class _Genre extends GenrePlugin<_Run> {
  _Genre({this.world});

  /// The world the run's actors live in, published when given.
  final EcsWorld? world;

  @override
  PluginManifest get manifest => PluginManifest(
    id: 'test.genre',
    apiVersion: PluginApiVersion.current,
    touches: PluginTouches.simulation,
  );

  @override
  String get systemName => 'test.step';

  @override
  void stepSimulation(_Run simulation, LoopContext context) =>
      simulation.steps++;

  @override
  Snapshot captureSimulation(_Run simulation) => simulation.save();

  @override
  void restoreSimulation(_Run simulation, Snapshot state) =>
      simulation.restore(state);

  @override
  EcsWorld? publishedWorldOf(_Run simulation) => world;
}

void main() {
  group("a genre's run", () {
    test('is in the loop\'s snapshots, so a rewind puts it back', () {
      // The review's first Must: the run lived outside the loop, and a
      // rewind set the step count back and left the run where it was.
      // Mutation: drop the part `GenrePlugin.install` adds — the count stays
      // at five after the rewind.
      final genre = _Genre();
      final loop = EngineLoop(
        input: InputState(),
        plugins: <Flutter3dPlugin>[genre],
      );
      final run = _Run();
      genre.simulation = run;
      expect(loop.snapshots.parts, <String>['world', 'test.genre']);

      loop.runSteps(2);
      final atTwo = loop.capture();
      loop.runSteps(3);
      expect(run.steps, 5);

      loop.rewindTo(2, state: atTwo);
      expect(run.steps, 2);
      expect(loop.step, 2);
    });

    test("converts between its own snapshot and the loop's", () {
      // A tape's start is the run's own save, which is what keeps recorded
      // tapes replaying. Mutation: key the part by anything but the plugin
      // id — the run is not restored.
      final genre = _Genre();
      final loop = EngineLoop(
        input: InputState(),
        plugins: <Flutter3dPlugin>[genre],
      );
      final run = _Run();
      genre.simulation = run;
      loop.rewindTo(
        0,
        state: genre.loopStateOf(Snapshot(<String, Object?>{'steps': 7})),
      );
      expect(run.steps, 7);
      expect(genre.runStateOf(loop.capture())?.data, <String, Object?>{
        'steps': 7,
      });
    });
  });

  group('a rewind that would restore nothing', () {
    test('refuses when no state is given and none is kept', () {
      // Mutation: set the count and return, as an empty world once did — the
      // loop claims step 0 and the world is where it was.
      final loop = EngineLoop(input: InputState())..runSteps(3);
      expect(() => loop.rewindTo(0), throwsStateError);
      expect(loop.step, 3);
    });

    test('refuses a snapshot holding none of its parts', () {
      // A run's own save handed to the loop: nothing in it is a part.
      final loop = EngineLoop(input: InputState());
      expect(
        () => loop.restore(Snapshot(<String, Object?>{'steps': 3})),
        throwsStateError,
      );
    });

    test('goes back to the step keeping began at', () {
      final genre = _Genre();
      final loop = EngineLoop(
        input: InputState(),
        plugins: <Flutter3dPlugin>[genre],
      );
      final run = _Run();
      genre.simulation = run;
      loop
        ..keep(window: 10)
        ..runSteps(4)
        ..rewindTo(0);
      expect(run.steps, 0);
    });
  });

  test("the view reads a run's actors from published state", () {
    // Decision A: the actors are drawn from what the step published.
    // Mutation: leave the run's world out of `PublishedWorlds` — there is no
    // row for the walker.
    final world = EcsWorld();
    registerActorComponents(world);
    final walker = world.spawn();
    world.set<Facing>(walker, Facing(yaw: 0.5));
    final genre = _Genre(world: world);
    final loop = EngineLoop(
      input: InputState(),
      plugins: <Flutter3dPlugin>[genre],
    );
    genre.simulation = _Run();
    expect(loop.publishedWorlds.worlds, <EcsWorld>[world]);

    final state = loop.published;
    expect(state.read<Facing>(ActorCodecs.facing, walker)?.yaw, 0.5);

    genre.simulation = null;
    expect(loop.publishedWorlds.worlds, isEmpty);
  });

  group('a local simulation', () {
    test('queues what it is handed and puts it on the tape', () {
      // Mutation: keep only the last submission per seat — the press is lost
      // to the release; or apply it in the `input` phase, after the
      // recorders — the tape holds nothing.
      final input = InputState();
      final loop = EngineLoop(input: input);
      final recorder = InputTapeRecorder(seed: 0);
      loop.recorders.add(recorder);
      final applied = <Object?>[];
      final handle = LocalSimulation(
        loop,
        applyInput: (seat, value) {
          applied.add(value);
          input.tune('test.$value', 1.0);
        },
      );
      handle
        ..submit('press')
        ..submit('release');
      loop.runSteps(1);
      expect(applied, <Object?>['press', 'release']);
      expect(recorder.tape.frames.single.tunes.keys, <String>[
        'test.press',
        'test.release',
      ]);
    });

    test('answers a question by name, and refuses one it does not know', () {
      final loop = EngineLoop(input: InputState());
      loop.queries.add('test.count', (world, _) => world.length);
      final handle = LocalSimulation(loop, applyInput: (_, _) {});
      loop.world.spawn();
      expect(handle.ask('test.count'), completion(1));
      expect(
        handle.ask('test.missing'),
        throwsA(isA<SimulationCapabilityException>()),
      );
    });
  });

  test('a simulation names every genre it was played by', () {
    // Mutation: drop `otherGenres` from the wire — a tape of two genres
    // reads back as one, and replays where only one is installed.
    const two = SimulationVersion(
      genre: 'racing',
      genreVersion: 2,
      otherGenres: <String, int>{'shooter': 3},
    );
    final read = SimulationVersion.fromJson(two.toJson());
    expect(read, two);
    expect(read.genres, <String, int>{'racing': 2, 'shooter': 3});
    expect(
      two.refusalOn(const SimulationVersion(genre: 'racing', genreVersion: 2)),
      isNotNull,
    );
  });
}
