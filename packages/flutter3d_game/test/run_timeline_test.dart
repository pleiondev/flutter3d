/// `rp-02`'s mechanism: pause, step, rewind and branch, without the panel
/// that will eventually call it.
///
///     flutter test test/run_timeline_test.dart
///
/// The acceptance in `doc/tooling-plan.md` is a person dragging a scrubber
/// three seconds back and letting go; what that comes down to underneath is
/// [RunTimeline.releaseAt] restoring a keyframe, replaying the frames between
/// it and the release point, and cutting the buffer there — each pinned on
/// its own, on the same toy `flutter3d_sim/test/rewind_test.dart` already
/// proved the buffer itself with.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

const GameAction _fire = GameAction('fire');

/// The same shape as `flutter3d_sim/test/rewind_test.dart`'s toy: small
/// enough to snapshot in a map, large enough that a dropped entry or a lost
/// die lands somewhere else.
final class _Toy {
  _Toy(int seed) : dice = GameRandom(seed);

  final GameRandom dice;
  double x = 0.0;
  int shots = 0;
  int rolls = 0;

  void step(InputState input) {
    x += input.moveAxis.x;
    if (input.pressed(_fire)) {
      shots++;
      rolls += dice.nextInt(1000);
    }
  }

  Snapshot save() => Snapshot(<String, Object?>{
    'x': x,
    'shots': shots,
    'rolls': rolls,
    'random': dice.state,
  });

  void restore(Snapshot snapshot) {
    final data = snapshot.data;
    x = data.number('x');
    shots = data.integer('shots');
    rolls = data.integer('rolls');
    dice.state = data.integer('random');
  }

  String get state => '$x/$shots/$rolls/${dice.state}';
}

void _play(InputState input, int step) {
  input.setStickAxis(step % 3 == 0 ? 1.0 : -0.5, 0.0);
  if (step % 11 == 0) input.press(_fire);
  if (step % 11 == 4) input.release(_fire);
}

void main() {
  group('pause, resume and stepOnce', () {
    test('stepOnce refuses to run on a live timeline', () {
      final toy = _Toy(1);
      final input = InputState();
      final timeline = RunTimeline(
        rewind: RewindBuffer(stepsPerSecond: 60),
        input: input,
        stepSim: (dt) => toy.step(input),
        restore: toy.restore,
      );

      expect(timeline.isPaused, isFalse);
      expect(() => timeline.stepOnce(), throwsStateError);
    });

    test('pause, step, resume all land in the history in order', () {
      final toy = _Toy(1);
      final input = InputState();
      final timeline = RunTimeline(
        rewind: RewindBuffer(stepsPerSecond: 60),
        input: input,
        stepSim: (dt) => toy.step(input),
        restore: toy.restore,
      );

      timeline.pause();
      expect(timeline.isPaused, isTrue);
      timeline.stepOnce();
      timeline.stepOnce();
      timeline.resume();
      expect(timeline.isPaused, isFalse);

      expect(timeline.history, <TimelineCommand>[
        const TimelinePaused(),
        const TimelineStepped(),
        const TimelineStepped(),
        const TimelineResumed(),
      ]);
    });

    test('pausing twice, or resuming a run that is not paused, is a no-op', () {
      final toy = _Toy(1);
      final input = InputState();
      final timeline = RunTimeline(
        rewind: RewindBuffer(stepsPerSecond: 60),
        input: input,
        stepSim: (dt) => toy.step(input),
        restore: toy.restore,
      )..resume();
      expect(timeline.history, isEmpty);

      timeline.pause();
      timeline.pause();
      expect(timeline.history, <TimelineCommand>[const TimelinePaused()]);
    });
  });

  group('releaseAt', () {
    test('rewinding three seconds back and releasing lands the live state '
        'exactly where a fresh replay to that step would', () {
      final toy = _Toy(7);
      final input = InputState();
      final rewind = RewindBuffer(stepsPerSecond: 60, history: 10.0);
      final timeline = RunTimeline(
        rewind: rewind,
        input: input,
        stepSim: (dt) => toy.step(input),
        restore: toy.restore,
      );

      // Play five seconds, keyframing and recording exactly the way a game
      // loop does — see `GameLoop` for why both happen at this moment.
      for (var step = 0; step < 300; step++) {
        _play(input, step);
        rewind.recorder.record(input);
        input.beginStep();
        if (rewind.keyframeDue) rewind.keyframe(toy.save());
        toy.step(input);
        input.endStep();
      }
      final atFiveSeconds = toy.state;

      final point = timeline.preview(3.0);
      expect(point, isNotNull, reason: 'ten seconds of history holds three');
      timeline.releaseAt(point!);

      expect(timeline.isPaused, isFalse, reason: 'a release keeps playing');
      expect(
        timeline.history.last,
        isA<TimelineBranched>().having((c) => c.step, 'step', point.step),
      );

      // The independent check: replay the same tape from scratch to the
      // branch point and compare states, rather than trusting the
      // mechanism to grade its own homework.
      final independent = _Toy(7);
      final independentInput = InputState();
      for (var step = 0; step < point.step; step++) {
        _play(independentInput, step);
        independentInput.beginStep();
        independent.step(independentInput);
        independentInput.endStep();
      }
      expect(toy.state, independent.state);
      expect(toy.state, isNot(atFiveSeconds), reason: 'time really moved back');
    });

    test('cuts the buffer, so a keyframe past the branch cannot be reached '
        'again', () {
      final toy = _Toy(3);
      final input = InputState();
      final rewind = RewindBuffer(stepsPerSecond: 60, history: 10.0);
      final timeline = RunTimeline(
        rewind: rewind,
        input: input,
        stepSim: (dt) => toy.step(input),
        restore: toy.restore,
      );

      for (var step = 0; step < 300; step++) {
        _play(input, step);
        rewind.recorder.record(input);
        input.beginStep();
        if (rewind.keyframeDue) rewind.keyframe(toy.save());
        toy.step(input);
        input.endStep();
      }

      final point = timeline.preview(3.0)!;
      timeline.releaseAt(point);

      // The step the run was at before releasing is in the future of the
      // branch now — the same rule `RewindBuffer.cut` documents itself with.
      expect(rewind.rewindTo(300), isNull);
    });

    test('mutes the live devices during the fast-forward and restores the '
        'mute flag afterwards', () {
      final toy = _Toy(1);
      final input = InputState();
      final rewind = RewindBuffer(stepsPerSecond: 60, history: 10.0);
      final timeline = RunTimeline(
        rewind: rewind,
        input: input,
        stepSim: (dt) => toy.step(input),
        restore: toy.restore,
      );

      for (var step = 0; step < 120; step++) {
        _play(input, step);
        rewind.recorder.record(input);
        input.beginStep();
        if (rewind.keyframeDue) rewind.keyframe(toy.save());
        toy.step(input);
        input.endStep();
      }

      final point = timeline.preview(1.0)!;
      timeline.releaseAt(point);
      expect(
        input.muted,
        isFalse,
        reason: 'the mute is scoped to the fast-forward, not left behind',
      );
    });
  });
}
