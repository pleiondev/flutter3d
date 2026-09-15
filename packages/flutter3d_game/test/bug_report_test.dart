/// `rp-04`'s game-side half: "send this run" as the last few seconds
/// [RewindBuffer] already kept, turned into what a [Demo] needs to start
/// from.
///
///     flutter test test/bug_report_test.dart
library;

import 'dart:convert';

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

const GameAction _fire = GameAction('fire');

final class _Toy {
  _Toy(int seed) : dice = GameRandom(seed);
  final GameRandom dice;
  double x = 0.0;
  int rolls = 0;

  void step(InputState input) {
    x += input.moveAxis.x;
    if (input.pressed(_fire)) rolls += dice.nextInt(1000);
  }

  Snapshot save() =>
      Snapshot(<String, Object?>{'x': x, 'rolls': rolls, 'random': dice.state});

  void restore(Snapshot snapshot) {
    final data = snapshot.data;
    x = data.number('x');
    rolls = data.integer('rolls');
    dice.state = data.integer('random');
  }

  String get state => '$x/$rolls/${dice.state}';
}

void _play(InputState input, int step) {
  input.setStickAxis(step % 5 == 0 ? 1.0 : -0.25, 0.0);
  if (step % 13 == 0) input.press(_fire);
  if (step % 13 == 3) input.release(_fire);
}

void main() {
  test('null before the first keyframe — nothing to report yet', () {
    final rewind = RewindBuffer(stepsPerSecond: 60);
    expect(bugReportTape(rewind), isNull);
  });

  test('reports exactly the window RewindBuffer has kept, replayed to the '
      'same bit as the live run', () {
    final toy = _Toy(11);
    final input = InputState();
    final rewind = RewindBuffer(stepsPerSecond: 60, history: 3.0);

    // Fifteen seconds live — five times the three-second window, so the
    // buffer has long since forgotten the start of the run.
    for (var step = 0; step < 900; step++) {
      _play(input, step);
      rewind.recorder.record(input);
      input.beginStep();
      if (rewind.keyframeDue) rewind.keyframe(toy.save());
      toy.step(input);
      input.endStep();
    }
    final atTheEnd = toy.state;

    final report = bugReportTape(rewind);
    expect(report, isNotNull);

    // Roughly three seconds, not the whole fifteen — `RewindBuffer`'s own
    // doc promises "never more than history plus one keyframe interval",
    // which at a keyframe a second is four here.
    expect(report!.tape.frames.length, lessThanOrEqualTo(4 * 60));
    expect(report.tape.frames.length, greaterThan(2 * 60));

    // Independently: replay the reported tape from its own start and check
    // it lands exactly on the state the live run was in.
    final replay = _Toy(11)..restore(report.start);
    final replayInput = InputState();
    final playback = InputTapePlayback(report.tape);
    while (!playback.isFinished) {
      playback.applyTo(replayInput);
      replayInput.beginStep();
      replay.step(replayInput);
      replayInput.endStep();
    }
    expect(replay.state, atTheEnd);
  });

  test('a Demo built from the report round-trips through JSON', () {
    final toy = _Toy(3);
    final input = InputState();
    final rewind = RewindBuffer(stepsPerSecond: 60, history: 2.0);
    for (var step = 0; step < 400; step++) {
      _play(input, step);
      rewind.recorder.record(input);
      input.beginStep();
      if (rewind.keyframeDue) rewind.keyframe(toy.save());
      toy.step(input);
      input.endStep();
    }

    final report = bugReportTape(rewind)!;
    final checkpoints = DigestTrace(every: 10);
    final replayForCheckpoints = _Toy(3)..restore(report.start);
    final replayInput = InputState();
    final playback = InputTapePlayback(report.tape);
    var replayedStep = 0;
    while (!playback.isFinished) {
      playback.applyTo(replayInput);
      replayInput.beginStep();
      replayForCheckpoints.step(replayInput);
      replayedStep++;
      checkpoints.observe(replayedStep, replayForCheckpoints.save().toJson());
      replayInput.endStep();
    }

    final demo = Demo(
      level: 'assets/levels/crypt.json',
      levelHash: 'deadbeef',
      start: report.start,
      tape: report.tape,
      buildStamp: 'test-build',
      checkpoints: checkpoints,
      platform: 'macos',
    );

    final read = Demo.fromJson(
      jsonDecode(jsonEncode(demo.toJson())) as Map<String, Object?>,
    );
    expect(read.steps, report.tape.steps);
    expect(read.platform, 'macos');
  });
}
