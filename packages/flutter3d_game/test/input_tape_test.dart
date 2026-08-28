/// A run, recorded as what the player did and played back exactly.
///
///     flutter test test/input_tape_test.dart
///
/// **What is being pinned is a property of the whole simulation, not of a
/// class.** A step here reaches for no clock and no loose dice — a scan in
/// `tool/structure.dart` holds it to that — and its randomness is a
/// [GameRandom] with a readable state. So the same start fed the same intents
/// goes to the same place, and this file is where that claim is measured rather
/// than asserted.
library;

import 'dart:convert';

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';

const GameAction _fire = GameAction('fire');
const GameAction _jump = GameAction('jump');
const GameAction _throttle = GameAction('throttle');

/// What a step of this toy simulation is: read the input, move, roll a die.
///
/// Deliberately not a real game, but not arbitrary either — it has to read each
/// of the things a tape carries, or a tape that dropped one of them would replay
/// the run correctly and the test would say nothing. So: the stick moves it, a
/// press rolls a die, **a hold that only a release ever ends** moves it further,
/// and an analogue reading scales that. [held] is the reason the releases are
/// load-bearing here; a toy reading only [InputState.pressed] leaves them free
/// to be dropped.
final class _Toy {
  _Toy(int seed) : dice = GameRandom(seed);

  final GameRandom dice;
  double x = 0.0;
  double aim = 0.0;
  int shots = 0;
  int rolls = 0;

  void step(InputState input) {
    x += input.moveAxis.x;
    aim += input.lookDelta.x;
    if (input.pressed(_fire)) {
      shots++;
      rolls += dice.nextInt(1000);
    }
    if (input.held(_fire)) x += 0.125;
    // Read unconditionally: an analogue reading is not a hold, and a toy that
    // guarded this with `held` would leave the recorded values free to be
    // dropped without any of this failing.
    x += input.value(_throttle) * 0.5;
    input.endStep();
  }

  /// Everything a replay has to land on.
  String get ending =>
      '${x.toStringAsFixed(6)}/${aim.toStringAsFixed(6)}/$shots/$rolls';
}

/// Drives [input] for step [i] the way a player might have.
void _play(InputState input, int i) {
  if (i % 7 == 0) input.press(_fire);
  if (i % 7 == 3) input.release(_fire);
  if (i == 11) input.press(_jump);
  input.setStickAxis(i.isEven ? 0.5 : -0.25, 0.0);
  input.addLook(i * 0.01, 0.0);
  if (i % 5 == 0) input.setActionValue(_throttle, 0.3);
}

void main() {
  group('a recorded run', () {
    test('plays back to exactly where it ended', () async {
      // **The whole claim, measured.** Not "close": the same string.
      //
      // Mutations, all of them run and all of them caught here: stop recording
      // the releases; stop recording the analogue readings; replay the stick
      // only when it changed; scale the look delta. Each is a plausible thing
      // for somebody to think is an optimisation.
      const seed = 4242;
      final recorder = InputTapeRecorder(seed: seed);
      final live = _Toy(seed);
      final input = InputState();

      for (var i = 0; i < 60; i++) {
        _play(input, i);
        // Recorded after the input is filled and before the step runs: the step
        // clears the latches, so recording afterwards records nothing happening.
        recorder.record(input);
        live.step(input);
      }

      final replay = _Toy(recorder.tape.seed);
      final playback = InputTapePlayback(recorder.tape);
      final replayed = InputState();
      while (!playback.isFinished) {
        playback.applyTo(replayed);
        replay.step(replayed);
      }

      expect(replay.ending, equals(live.ending));
      expect(
        replay.shots,
        greaterThan(0),
        reason: 'a run where nothing happened would prove nothing',
      );
    });

    test('and is one entry per step', () {
      final recorder = InputTapeRecorder(seed: 1);
      final input = InputState();
      for (var i = 0; i < 12; i++) {
        _play(input, i);
        recorder.record(input);
        input.endStep();
      }

      expect(recorder.tape.steps, 12);
    });

    test('and survives a round trip through JSON', () {
      // A tape is worth having because it can be attached to a bug report.
      //
      // Mutation: drop `seed` from `toJson` — the replay runs against different
      // dice, which is the failure this catches before anybody debugs it.
      final recorder = InputTapeRecorder(seed: 99);
      final input = InputState();
      for (var i = 0; i < 20; i++) {
        _play(input, i);
        recorder.record(input);
        input.endStep();
      }

      final written = jsonEncode(recorder.tape.toJson());
      final read = InputTape.fromJson(
        jsonDecode(written) as Map<String, Object?>,
      );

      expect(read.seed, 99);
      expect(read.steps, recorder.tape.steps);

      final before = _Toy(recorder.tape.seed);
      final after = _Toy(read.seed);
      for (final tape in <InputTape>[recorder.tape, read]) {
        final toy = identical(tape, recorder.tape) ? before : after;
        final playback = InputTapePlayback(tape);
        final state = InputState();
        while (!playback.isFinished) {
          playback.applyTo(state);
          toy.step(state);
        }
      }
      expect(after.ending, equals(before.ending));
    });

    test('and holds an action a genre invented', () {
      // `GameAction` wraps a string so a genre can add its own, and a tape that
      // stored indices into a list this package knows about could not carry a
      // shooter's `reload`.
      //
      // Mutation: record `action.hashCode` instead of `action.name` — the
      // replay presses nothing and this fails.
      const invented = GameAction('unfoldTheChair');
      final recorder = InputTapeRecorder(seed: 1);
      final input = InputState()..press(invented);
      recorder.record(input);

      final replayed = InputState();
      InputTapePlayback(recorder.tape).applyTo(replayed);

      expect(replayed.pressed(invented), isTrue);
    });

    test('and a tape that runs out stops driving', () {
      // A replay that ended should hand the controls back, not jam them on the
      // last frame's keys. Mutation: clamp the index to the last frame instead
      // of finishing — the action stays pressed forever and this fails.
      final recorder = InputTapeRecorder(seed: 1);
      final input = InputState()..press(_jump);
      recorder.record(input);

      final playback = InputTapePlayback(recorder.tape);
      final replayed = InputState();
      playback.applyTo(replayed);
      expect(playback.isFinished, isTrue);

      replayed
        ..endStep()
        ..release(_jump)
        ..endStep();
      // Nothing more comes off the tape, so nothing presses it again.
      playback.applyTo(replayed);
      expect(replayed.held(_jump), isFalse);
    });

    test('and an idle step says so', () {
      // What a compressor would key on later, and what makes "a few bytes a
      // second" true rather than aspirational.
      expect(const InputFrame().isIdle, isTrue);
      expect(const InputFrame(pressed: <String>['fire']).isIdle, isFalse);
      expect(const InputFrame(stickX: 0.2).isIdle, isFalse);
    });
  });
}
