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

/// [toy] as one part of a fresh loop's snapshots and a system in its step,
/// reading [input]; [rewind], when given, attached to it.
EngineLoop _loopOf(_Toy toy, InputState input, [RewindBuffer? rewind]) {
  final loop = EngineLoop(input: input)
    ..snapshots.add(
      SnapshotPart.of(
        id: 'toy',
        capture: () => toy.save().data,
        restore: (context) {
          final data = context.data;
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

void main() {
  group('pause, resume and stepOnce', () {
    test('stepOnce refuses to run on a live timeline', () {
      final toy = _Toy(1);
      final input = InputState();
      final timeline = RunTimeline(
        rewind: RewindBuffer(stepsPerSecond: 60),
        loop: _loopOf(toy, input),
      );

      expect(timeline.isPaused, isFalse);
      expect(() => timeline.stepOnce(), throwsStateError);
    });

    test('pause, step, resume all land in the history in order', () {
      final toy = _Toy(1);
      final input = InputState();
      final timeline = RunTimeline(
        rewind: RewindBuffer(stepsPerSecond: 60),
        loop: _loopOf(toy, input),
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
        loop: _loopOf(toy, input),
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
        loop: _loopOf(toy, input, rewind),
      );

      // Play five seconds through the loop, which records each step's input
      // into the attached buffer and keyframes its own capture.
      for (var step = 0; step < 300; step++) {
        _play(input, step);
        timeline.loop.runSteps(1);
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
        loop: _loopOf(toy, input, rewind),
      );

      for (var step = 0; step < 300; step++) {
        _play(input, step);
        timeline.loop.runSteps(1);
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
        loop: _loopOf(toy, input, rewind),
      );

      for (var step = 0; step < 120; step++) {
        _play(input, step);
        timeline.loop.runSteps(1);
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

  group('a demo across a branch', () {
    /// Plays [steps] through [timeline]'s loop from [from], each step's
    /// input from [play].
    void playOn(
      RunTimeline timeline,
      InputState input,
      int from,
      int steps, [
      void Function(InputState input, int step) play = _play,
    ]) {
      for (var step = from; step < from + steps; step++) {
        play(input, step);
        timeline.loop.runSteps(1);
      }
    }

    /// The state [demo]'s tape reaches from its start, played on a fresh toy.
    String replayed(DemoRecording demo, int seed) {
      final toy = _Toy(seed)..restore(demo.start);
      final input = InputState();
      final playback = InputTapePlayback.tape(demo.recorder.tape);
      while (!playback.isFinished) {
        playback.applyTo(input);
        input.beginStep();
        toy.step(input);
        input.endStep();
      }
      return toy.state;
    }

    test('a release cuts the demo there, so its tape replays the branch '
        'that was played', () {
      // Mutation: leave `onBranched` uncalled in `releaseAt`, and the demo
      // keeps the old future's steps ahead of the branch's: its replay goes
      // where neither run went.
      final toy = _Toy(9);
      final input = InputState();
      final rewind = RewindBuffer(stepsPerSecond: 60, history: 10.0);
      DemoRecording? demo;
      final timeline = RunTimeline(
        rewind: rewind,
        loop: _loopOf(toy, input, rewind),
        onBranched: (branch) =>
            expect(demo!.branched(stepsAgo: branch.stepsAgo), isTrue),
      );
      playOn(timeline, input, 0, 60);
      demo = DemoRecording(
        level: 'toy',
        levelHash: '0',
        start: toy.save(),
        seed: 9,
      )..attach(timeline.loop);
      playOn(timeline, input, 60, 240);

      final point = timeline.preview(2.0)!;
      timeline.releaseAt(point);
      expect(demo.steps, point.step - 60);
      // Another future: the stick held the other way.
      playOn(timeline, input, 1000, 90, (input, step) {
        input.setStickAxis(0.25, 0.0);
        if (step % 7 == 0) input.press(_fire);
        if (step % 7 == 2) input.release(_fire);
      });

      expect(demo.steps, point.step - 60 + 90);
      expect(replayed(demo, 9), toy.state);
    });

    test('a branch from a scrub cuts the demo as a release does', () {
      // Mutation: leave `onBranched` uncalled in `branchHere`.
      final toy = _Toy(4);
      final input = InputState();
      final rewind = RewindBuffer(stepsPerSecond: 60, history: 10.0);
      final heard = <TimelineBranch>[];
      final timeline = RunTimeline(
        rewind: rewind,
        loop: _loopOf(toy, input, rewind),
        onBranched: heard.add,
      );
      playOn(timeline, input, 0, 200);
      timeline
        ..pause()
        ..scrubTo(150)
        ..branchHere();
      expect(heard, const <TimelineBranch>[
        TimelineBranch(step: 150, stepsAgo: 50),
      ]);
    });

    test("a branch back past the demo's start says so and changes nothing", () {
      final toy = _Toy(2);
      final input = InputState();
      final rewind = RewindBuffer(stepsPerSecond: 60, history: 10.0);
      final timeline = RunTimeline(
        rewind: rewind,
        loop: _loopOf(toy, input, rewind),
      );
      playOn(timeline, input, 0, 200);
      final demo = DemoRecording(
        level: 'toy',
        levelHash: '0',
        start: toy.save(),
        seed: 2,
      )..attach(timeline.loop);
      playOn(timeline, input, 200, 30);

      expect(demo.branched(stepsAgo: 31), isFalse);
      expect(demo.steps, 30);
      expect(() => demo.branched(stepsAgo: -1), throwsRangeError);
    });
  });
}
