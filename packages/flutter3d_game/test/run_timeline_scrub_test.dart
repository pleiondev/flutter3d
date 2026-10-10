/// `N4`'s time-travel debugger on a live run: scrub through the buffer
/// without losing the future, go back to the present exactly, branch from a
/// scrubbed moment, and read every entity's lanes over what is held.
///
///     flutter test test/run_timeline_scrub_test.dart
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

const GameAction _fire = GameAction('fire');

/// Two entities: a runner that follows the stick and a target that loses
/// health, by the dice, whenever fire is pressed.
final class _Toy {
  _Toy(int seed) : dice = GameRandom(seed);

  final GameRandom dice;
  double x = 0.0;
  int hp = 1000;

  void step(InputState input) {
    x += input.moveAxis.x;
    if (input.pressed(_fire)) hp -= 1 + dice.nextInt(9);
  }

  Snapshot save() => Snapshot(<String, Object?>{
    'entities': <String, Object?>{
      'runner': <String, Object?>{'x': x},
      'target': <String, Object?>{'hp': hp},
    },
    'random': dice.state,
  });

  void restore(Snapshot snapshot) {
    final entities = snapshot.data.object('entities')!;
    x = entities.object('runner')!.number('x');
    hp = entities.object('target')!.integer('hp');
    dice.state = snapshot.data.integer('random');
  }

  String get state => '$x/$hp/${dice.state}';
}

/// [toy] as one part of a fresh loop's snapshots and a system in its step,
/// reading [input]; [rewind], when given, attached to it.
EngineLoop _loopOf(_Toy toy, InputState input, [RewindBuffer? rewind]) {
  final loop = EngineLoop(input: input)
    ..snapshots.add(
      SnapshotPart.of(
        id: 'toy',
        capture: () => toy.save().data,
        restore: (Object? data, int _) {
          if (data is Map) toy.restore(Snapshot(data.cast<String, Object?>()));
        },
      ),
    )
    ..addSystem('toy', LoopPhase.rules, (_) => toy.step(input));
  rewind?.attach(loop);
  return loop;
}

void _play(InputState input, int step) {
  input.setStickAxis(step % 3 == 0 ? 1.0 : -0.5, 0.0);
  if (step % 11 == 0) input.press(_fire);
  if (step % 11 == 4) input.release(_fire);
}

/// A run of [steps] steps under a game loop's own order, with the state
/// before every step written down to compare a scrub against.
({_Toy toy, RewindBuffer rewind, RunTimeline timeline, Map<int, String> seen})
_run(int steps) {
  final toy = _Toy(3);
  final input = InputState();
  final rewind = RewindBuffer(stepsPerSecond: 60, history: 10.0);
  final timeline = RunTimeline(
    rewind: rewind,
    loop: _loopOf(toy, input, rewind),
  );
  final seen = <int, String>{};
  for (var step = 0; step < steps; step++) {
    seen[step] = toy.state;
    _play(input, step);
    timeline.loop.runSteps(1);
  }
  seen[steps] = toy.state;
  return (toy: toy, rewind: rewind, timeline: timeline, seen: seen);
}

void main() {
  test('a scrub lands on the state the run had before that step, back and '
      'forth, and the present comes back exactly', () {
    // Mutation: play forward from the scrubbed step without checking it is
    // at or after the keyframe — a drag to the left then plays on from the
    // right and lands in the future.
    final run = _run(300);
    run.timeline.pause();

    for (final step in <int>[200, 230, 130, 131, 299, 60]) {
      expect(run.timeline.scrubTo(step), isA<ScrubMoved>());
      expect(run.toy.state, run.seen[step], reason: 'scrubbed to $step');
    }
    expect(run.timeline.scrubbedAt, 60);
    expect(run.rewind.step, 300, reason: 'a scrub keeps the tape whole');

    expect(run.timeline.returnToPresent(), isTrue);
    expect(run.toy.state, run.seen[300]);
    expect(run.timeline.scrubbedAt, isNull);
    expect(run.timeline.returnToPresent(), isFalse);
  });

  test('stepping from a scrub walks the tape, and ends at the present', () {
    // Mutation: let `stepOnce` step the simulation while scrubbed. The state
    // then leaves the tape, and the next scrub restores from a keyframe as
    // if nothing happened.
    final run = _run(300);
    run.timeline
      ..pause()
      ..scrubTo(297)
      ..stepOnce();
    expect(run.toy.state, run.seen[298]);
    run.timeline
      ..stepOnce()
      ..stepOnce();
    expect(run.timeline.scrubbedAt, isNull);
    expect(run.toy.state, run.seen[300]);
  });

  test('a scrub on a live run, or outside the buffer, is refused with a '
      'reason, and nothing moves', () {
    // Mutation: scrub a live run. The loop would step the scrubbed state as
    // if it were the present, and the run would jump.
    final run = _run(300);
    final live = run.timeline.scrubTo(100);
    expect(live, isA<ScrubRefused>());
    expect('$live', contains('pause'));

    run.timeline.pause();
    final far = run.timeline.scrubTo(400);
    expect('$far', contains('from step 0 to 300'));
    expect(run.toy.state, run.seen[300]);
    expect(run.timeline.branchHere(), isA<ScrubRefused>());
  });

  test('branching from a scrub cuts the future there and stays paused', () {
    // Mutation: branch without the cut. The buffer then still holds the
    // future the branch replaced, and a later rewind lands in it.
    final run = _run(300);
    run.timeline
      ..pause()
      ..scrubTo(150);

    expect(run.timeline.branchHere(), isA<ScrubMoved>());
    expect(run.rewind.step, 150);
    expect(run.toy.state, run.seen[150]);
    expect(run.timeline.isPaused, isTrue);
    expect(run.timeline.history, <TimelineCommand>[
      const TimelinePaused(),
      const TimelineScrubbed(150),
      const TimelineBranched(150),
    ]);
  });

  test('resuming from a scrub goes on from the present, not the scrub', () {
    // Mutation: drop the `returnToPresent` in `resume`. The loop then goes on
    // from step 120 with a tape that says 300.
    final run = _run(300);
    run.timeline
      ..pause()
      ..scrubTo(120)
      ..resume();
    expect(run.toy.state, run.seen[300]);
    expect(run.rewind.step, 300);
  });

  test('tracks hold every change each entity made over the buffer, and '
      'reading them changes nothing', () {
    // Mutation: drop the final restore in `tracks`. The live state is then
    // the end of a replay that took one more step's capture, and a scrub
    // left open is lost.
    final run = _run(300);
    run.timeline
      ..pause()
      ..scrubTo(140);
    final tracks = run.timeline.tracks(
      part: 'toy',
      layout: EntityLayout.rows('entities'),
    )!;

    expect(run.toy.state, run.seen[140]);
    expect(tracks.entities, <String>['runner', 'target']);
    expect(tracks.span, (first: 0, last: 300));
    // Fire is pressed on every eleventh step from 0, so the target's health
    // changes on the step after each press, 28 times in 300 steps.
    final hits = tracks.samples('target', 'hp');
    expect(hits.length, 1 + 28);
    expect(hits[1].step, 1);
    expect(
      tracks.at('runner', 'x', 140)!.value,
      double.parse(run.seen[140]!.split('/').first),
    );
  });
}
