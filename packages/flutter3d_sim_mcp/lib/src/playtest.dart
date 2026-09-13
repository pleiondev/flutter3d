import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'staging.dart';

const double _dt = 1.0 / 60.0;

/// How one playthrough ended.
enum PlaytestOutcome {
  /// [GameSimulation.state] reached [GameState.dead].
  died,

  /// [GameSimulation.state] reached [GameState.complete].
  exited,

  /// The player's own position moved less than [Playtest.stuckStride]
  /// metres over the last [Playtest.stuckAfter] steps — wedged in geometry,
  /// most often, or circling something a policy this blind can never think
  /// its way past.
  stuck,

  /// Neither of the above happened within [Playtest.maxSteps].
  timedOut,
}

/// The arguments one playthrough needs, bundled so [Isolate.run] has one
/// value to send rather than several — everything in it is data, which is
/// the whole reason it can cross an isolate boundary at all.
typedef _PlaytestArgs = ({
  String levelPath,
  int seed,
  int maxSteps,
  int sampleEvery,
  int stuckAfter,
  double stuckStride,
});

/// One playthrough, played to an ending rather than to a snapshot —
/// [Playtest.run] asks for many of these at once.
final class PlaytestRun {
  const PlaytestRun({
    required this.seed,
    required this.steps,
    required this.outcome,
    required this.positions,
  });

  final int seed;
  final int steps;
  final PlaytestOutcome outcome;

  /// Sampled every [Playtest.sampleEvery] steps — the trail
  /// [Playtest.heatmap] bins into cells.
  final List<(double x, double z)> positions;
}

/// `ai-01`: many independent playthroughs of the same level, run in
/// parallel isolates, driven by nothing but a seeded random policy — where
/// a level swallows a player who never learns it, rather than where one
/// who is choosing well happens to go.
///
/// **Not `dart run flutter3d:playtest`, the literal command the plan
/// names.** Checked the same way `rp-05`, `net-04` and `ai-00` each found
/// out for themselves: the shooter genre this plays needs the Flutter SDK,
/// so the terminal command is `flutter3d_build`/`ap-10`'s to build, not
/// this package's — what is here is the mechanism `ap-10`'s command would
/// call, proven under `flutter test` the same way `ai-00`'s own tools are.
///
/// **Isolates, because 200 runs of a crypt are 200 independent worlds and
/// nothing between them is shared** — one `Isolate.run` per playthrough
/// and `Future.wait` at the end, no lock, no queue. A run that hangs (an
/// infinite corridor a policy this dumb can loop forever) is bounded by
/// [maxSteps] rather than by a timeout on the isolate, since a killed
/// isolate would report nothing about why.
final class Playtest {
  const Playtest({
    this.maxSteps = 3600,
    this.sampleEvery = 10,
    this.stuckAfter = 300,
    this.stuckStride = 0.5,
  });

  /// A cap this run stops at regardless of outcome — a minute at sixty
  /// steps a second, long enough for a policy this blind to reach a
  /// crypt's first door and short enough that two hundred of them still
  /// finish before anyone is waiting on purpose.
  final int maxSteps;

  /// How often a position is kept for the heatmap — every step would be a
  /// trail with sixty points a second of a level three metres wide.
  final int sampleEvery;

  /// How many steps without moving [stuckStride] metres counts as stuck.
  final int stuckAfter;
  final double stuckStride;

  /// Plays [levelPath] [runs] times, seeded `0` through `runs - 1` so the
  /// same call reproduces the same batch.
  Future<List<PlaytestRun>> run(String levelPath, int runs) => Future.wait(
    <Future<PlaytestRun>>[
      for (var seed = 0; seed < runs; seed++)
        Isolate.run(
          () => _playOneForIsolate((
            levelPath: levelPath,
            seed: seed,
            maxSteps: maxSteps,
            sampleEvery: sampleEvery,
            stuckAfter: stuckAfter,
            stuckStride: stuckStride,
          )),
        ),
    ],
  );

  /// Bins every sampled position from [runs] into square cells [cellSize]
  /// metres on a side, counting how many positions from how many distinct
  /// runs landed in each — the JSON `ai-01`'s own row promises, and the
  /// same shape `ai-02`'s editor layer draws directly over the level.
  static Map<String, Object?> heatmap(
    List<PlaytestRun> runs, {
    double cellSize = 1.0,
  }) {
    final counts = <(int, int), int>{};
    final runsThroughCell = <(int, int), Set<int>>{};
    for (final run in runs) {
      for (final (x, z) in run.positions) {
        final cell = ((x / cellSize).floor(), (z / cellSize).floor());
        counts[cell] = (counts[cell] ?? 0) + 1;
        (runsThroughCell[cell] ??= <int>{}).add(run.seed);
      }
    }
    return <String, Object?>{
      'cellSize': cellSize,
      'cells': <Map<String, Object?>>[
        for (final entry in counts.entries)
          <String, Object?>{
            'x': entry.key.$1,
            'z': entry.key.$2,
            'samples': entry.value,
            'runs': runsThroughCell[entry.key]!.length,
          },
      ],
      'deaths': <Map<String, Object?>>[
        for (final run in runs)
          if (run.outcome == PlaytestOutcome.died && run.positions.isNotEmpty)
            <String, Object?>{
              'seed': run.seed,
              'step': run.steps,
              'x': run.positions.last.$1,
              'z': run.positions.last.$2,
            },
      ],
      'outcomes': <String, int>{
        for (final outcome in PlaytestOutcome.values)
          outcome.name: runs.where((r) => r.outcome == outcome).length,
      },
    };
  }
}

/// A random policy's intent for one step — held for a stretch rather than
/// rerolled every step, the same reason every other synthetic driver in
/// this repository does that: noise averages to standing still, and a wall
/// a level is worth mapping is a wall this has to actually walk into.
final class _RandomDriver {
  _RandomDriver(this._dice);

  final GameRandom _dice;
  double _moveX = 0.0;
  double _moveY = 0.0;
  double _lookX = 0.0;
  bool _firing = false;
  int _holdFor = 0;

  void apply(InputState input) {
    if (_holdFor <= 0) {
      _moveX = _dice.nextDouble() * 2.0 - 1.0;
      _moveY = _dice.nextDouble() < 0.7 ? 1.0 : -0.3;
      _lookX = (_dice.nextDouble() * 2.0 - 1.0) * 0.05;
      _firing = _dice.nextDouble() < 0.1;
      _holdFor = 20 + _dice.nextInt(80);
    }
    _holdFor--;
    input.setStickAxis(_moveX, _moveY);
    input.addLook(_lookX, 0.0);
    if (_firing) {
      if (!input.pressed(ShooterActions.fire)) input.press(ShooterActions.fire);
    } else {
      if (input.pressed(ShooterActions.fire)) input.release(ShooterActions.fire);
    }
  }
}

/// The actual playthrough — a top-level function because [Isolate.run]
/// sends its argument to a fresh isolate with no access to anything a
/// [Playtest] instance closed over.
PlaytestRun _playOneForIsolate(_PlaytestArgs args) {
  final level = Level.fromJson(
    jsonDecode(File(args.levelPath).readAsStringSync()) as Map<String, Object?>,
  );
  final world = CollisionWorld();
  level.addTo(world);
  final input = InputState();
  final staged = stage(level, world, input: input);
  world.update();

  final driver = _RandomDriver(GameRandom(args.seed + 1));
  final positions = <(double, double)>[];
  var stuckSince = 0;
  var lastStuckCheck = staged.player.body.position.clone();

  for (var step = 1; step <= args.maxSteps; step++) {
    driver.apply(input);
    input.beginStep();
    staged.sim.step(_dt);
    input.endStep();

    if (step % args.sampleEvery == 0) {
      final at = staged.player.body.position;
      positions.add((at.x, at.z));
    }

    if (staged.sim.state != GameState.playing) {
      return PlaytestRun(
        seed: args.seed,
        steps: step,
        outcome: staged.sim.state == GameState.dead
            ? PlaytestOutcome.died
            : PlaytestOutcome.exited,
        positions: positions,
      );
    }

    stuckSince++;
    if (stuckSince >= args.stuckAfter) {
      final now = staged.player.body.position;
      if ((now - lastStuckCheck).length < args.stuckStride) {
        return PlaytestRun(
          seed: args.seed,
          steps: step,
          outcome: PlaytestOutcome.stuck,
          positions: positions,
        );
      }
      stuckSince = 0;
      lastStuckCheck = now.clone();
    }
  }

  return PlaytestRun(
    seed: args.seed,
    steps: args.maxSteps,
    outcome: PlaytestOutcome.timedOut,
    positions: positions,
  );
}
