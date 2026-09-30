/// `HR4`: after a code reload, the last seconds lived again under the new
/// code, and the first place that run parts from the old one named.
///
///     flutter test test/run_timeline_new_code_replay_test.dart
///
/// The toy's step is a function the test swaps, the way a hot reload swaps
/// the code behind a step: the new rule only differs once the walker is past
/// a mark, so the old and new runs agree for a while and then do not.
///
/// Mutation: skip `compare(step)` inside the loop and the divergence is
/// found only at the present; replay without restoring the keyframe and the
/// state after the replay is not the fresh run's.
library;

import 'package:flutter3d_app/flutter3d_app.dart' show HotSwap;
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Rule = double Function(double x, double push);

double _old(double x, double push) => x + push * 0.05;

/// Walks at double speed once past 8: the same run as [_old] until then.
double _new(double x, double push) => x + push * (x > 8.0 ? 0.1 : 0.05);

final class _Walker {
  _Rule rule = _old;
  double x = 0.0;

  void step(InputState input) => x = rule(x, input.moveAxis.x);

  Snapshot save() => Snapshot(<String, Object?>{'x': x});
  void restore(Snapshot snapshot) => x = snapshot.data.number('x');
}

({_Walker walker, InputState input, RewindBuffer rewind, RunTimeline timeline})
_run() {
  final walker = _Walker();
  final input = InputState();
  final rewind = RewindBuffer(stepsPerSecond: 60, history: 10.0);
  return (
    walker: walker,
    input: input,
    rewind: rewind,
    timeline: RunTimeline(
      rewind: rewind,
      input: input,
      stepSim: (dt) => walker.step(input),
      restore: walker.restore,
    ),
  );
}

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
    it.input.setStickAxis(step % 5 == 0 ? 0.0 : 1.0, 0.0);
    it.rewind.recorder.record(it.input);
    it.input.beginStep();
    if (it.rewind.keyframeDue) it.rewind.keyframe(it.walker.save());
    it.walker.step(it.input);
    it.input.endStep();
  }
}

void main() {
  test('the replay arrives where a run with the new code from the keyframe '
      'does, and names where the two first part', () {
    final live = _run();
    _steps(live, 0, 300);
    // x passes 8 at about step 200, well inside the last three seconds.
    live.walker.rule = _new;

    final replay = live.timeline.replayUnderNewCode(
      seconds: 3.0,
      capture: live.walker.save,
    )!;

    expect(replay.fromStep, 120);
    expect(replay.toStep, 300);

    final fresh = _run();
    _steps(fresh, 0, replay.fromStep);
    fresh.walker.rule = _new;
    _steps(fresh, replay.fromStep, 300);
    expect(live.walker.x, fresh.walker.x);

    final divergence = replay.divergence!;
    expect(divergence.path, 'x');
    // The keyframes are 60 steps apart: agreed at 180, parted by 240.
    expect(divergence.agreedAt, 180);
    expect(divergence.step, 240);
    expect(
      divergence.after! as double,
      greaterThan(divergence.before! as double),
    );
    expect(live.timeline.history.last, const TimelineReplayed(120));
  });

  test('code that changes nothing here says so', () {
    final live = _run();
    _steps(live, 0, 300);
    final x = live.walker.x;
    live.walker.rule = (x, push) => push * 0.05 + x;

    final replay = live.timeline.replayUnderNewCode(
      seconds: 3.0,
      capture: live.walker.save,
    )!;

    expect(replay.divergence, isNull);
    expect(live.walker.x, x);
  });

  test('the old code\'s keyframes are not rewound into afterwards', () {
    final live = _run();
    _steps(live, 0, 300);
    live.walker.rule = _new;
    live.timeline.replayUnderNewCode(seconds: 3.0, capture: live.walker.save);

    expect(live.rewind.keyframesAfter(120), isEmpty);
    expect(live.rewind.rewindTo(100), isNull);
  });

  test('a buffer that does not reach back replays nothing', () {
    final live = _run();
    expect(
      live.timeline.replayUnderNewCode(seconds: 3.0, capture: live.walker.save),
      isNull,
    );
  });

  group('after a hot reload, on its own', () {
    test('the swap replays the last seconds and names the parting', () async {
      // Mutation: drop the listener in `replayAfterHotSwap` and nothing is
      // replayed when the swap finishes.
      final live = _run();
      _steps(live, 0, 300);
      final hotSwap = HotSwap(enabled: true);
      final replays = <CodeReplay>[];
      replayAfterHotSwap(
        live.timeline,
        capture: live.walker.save,
        hotSwap: hotSwap,
        onReplayed: replays.add,
      );

      live.walker.rule = _new;
      await hotSwap.swap();

      expect(replays, hasLength(1));
      expect(replays.single.toStep, 300);
      expect(replays.single.divergence?.path, contains('x'));
    });

    test('stopped, a swap replays nothing', () async {
      final live = _run();
      _steps(live, 0, 300);
      final hotSwap = HotSwap(enabled: true);
      final replays = <CodeReplay>[];
      final stop = replayAfterHotSwap(
        live.timeline,
        capture: live.walker.save,
        hotSwap: hotSwap,
        onReplayed: replays.add,
      );

      await hotSwap.swap();
      expect(replays.single.divergence, isNull, reason: 'the same code');

      stop();
      await hotSwap.swap();
      expect(replays, hasLength(1));
    });
  });
}
