/// `HR3`: a level edited under a running game, swapped through the timeline
/// so the run stays one a replay can reach.
///
///     flutter test test/run_timeline_level_swap_test.dart
///
/// The toy walks into a wall the snapshots do not carry — the level's part of
/// the world — so a swap that forgot to replay would leave the walker where
/// the old wall stopped it, and one that replayed from the wrong keyframe
/// would stop it somewhere a fresh run never does.
///
/// Mutation: skip the replay loop in `swapLevel` and the first test's states
/// part; drop `rebaseAt` and the rewind through the old level's keyframe
/// succeeds.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

/// A walker that stops at [wall], with a die it rolls at every stop.
final class _Walker {
  _Walker(this.wall) : dice = GameRandom(3);

  /// The level: not in [save], as a level is not in a game's snapshot.
  double wall;
  final GameRandom dice;
  double x = 0.0;
  int bumps = 0;

  void step(InputState input) {
    x += input.moveAxis.x * 0.1;
    if (x > wall) {
      x = wall;
      bumps += dice.nextInt(100);
    }
  }

  Snapshot save() =>
      Snapshot(<String, Object?>{'x': x, 'bumps': bumps, 'random': dice.state});

  void restore(Snapshot snapshot) {
    x = snapshot.data.number('x');
    bumps = snapshot.data.integer('bumps');
    dice.state = snapshot.data.integer('random');
  }

  String get state => '$x/$bumps/${dice.state}';
}

void _play(InputState input, int step) =>
    input.setStickAxis(step % 7 == 0 ? -1.0 : 1.0, 0.0);

/// [walker] as one part of a fresh loop's snapshots, under `walker`, and a
/// system in its step, reading [input]; [rewind] attached to it.
EngineLoop _loopOf(_Walker walker, InputState input, RewindBuffer rewind) {
  final loop = EngineLoop(input: input)
    ..snapshots.add(
      SnapshotPart.of(
        id: 'walker',
        capture: () => walker.save().data,
        restore: (Object? data, int _) {
          if (data is Map) {
            walker.restore(Snapshot(data.cast<String, Object?>()));
          }
        },
      ),
    )
    ..addSystem('walker', LoopPhase.rules, (_) => walker.step(input));
  rewind.attach(loop);
  return loop;
}

({_Walker walker, InputState input, RewindBuffer rewind, RunTimeline timeline})
_run() {
  final walker = _Walker(5.0);
  final input = InputState();
  final rewind = RewindBuffer(stepsPerSecond: 60, history: 10.0);
  return (
    walker: walker,
    input: input,
    rewind: rewind,
    timeline: RunTimeline(rewind: rewind, loop: _loopOf(walker, input, rewind)),
  );
}

/// Steps [from] to [to] through the loop, which records each step into the
/// attached buffer and keyframes its own capture.
void _steps(
  ({
    _Walker walker,
    InputState input,
    RewindBuffer rewind,
    RunTimeline timeline,
  })
  it,
  int from,
  int to,
) {
  for (var step = from; step < to; step++) {
    _play(it.input, step);
    it.timeline.loop.runSteps(1);
  }
}

void main() {
  test('a run with a level swapped at step K arrives where a fresh run with '
      'the new level from step K does', () {
    final live = _run();
    _steps(live, 0, 150);
    final at = live.timeline.swapLevel(
      () => live.walker.wall = 9.0,
      levelDigest: 'b',
    );
    _steps(live, 150, 400);

    // The keyframe before step 150, a second apart.
    expect(at, 120);
    expect(live.timeline.history.last, const TimelineLevelSwapped(120, 'b'));

    final fresh = _run();
    _steps(fresh, 0, at);
    fresh.walker.wall = 9.0;
    _steps(fresh, at, 400);

    expect(live.walker.state, fresh.walker.state);
  });

  test('without the swap the run ends elsewhere, so the check above has '
      'something to say', () {
    final kept = _run();
    _steps(kept, 0, 400);
    final swapped = _run();
    _steps(swapped, 0, 150);
    swapped.timeline.swapLevel(
      () => swapped.walker.wall = 9.0,
      levelDigest: 'b',
    );
    _steps(swapped, 150, 400);

    expect(swapped.walker.state, isNot(kept.walker.state));
  });

  test('nothing from before the swap can be rewound into afterwards', () {
    final live = _run();
    _steps(live, 0, 150);
    live.timeline.swapLevel(() => live.walker.wall = 9.0, levelDigest: 'b');

    expect(live.rewind.rewindTo(100), isNull, reason: 'the old level\'s');
    expect(live.rewind.rewindTo(130), isNotNull);
    expect(live.rewind.step, 150, reason: 'the tape since is kept');
  });

  test('before the first keyframe the level is simply swapped', () {
    final live = _run();
    final at = live.timeline.swapLevel(
      () => live.walker.wall = 9.0,
      levelDigest: 'b',
    );

    expect(at, 0);
    expect(live.walker.wall, 9.0);
  });
}
