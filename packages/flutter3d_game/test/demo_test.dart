/// A run as a file: where it started and what the player did.
///
///     flutter test test/demo_test.dart
///
/// A demo is a save plus a tape, and these pin the two halves that make it a
/// document rather than a pair of objects: the refusals, which have to say
/// why, and the loop's part in recording — the moment in a step where the
/// tape is written and read, which is the part a caller gets wrong.
library;

import 'dart:convert';

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const GameAction _fire = GameAction('fire');

Demo _demo({int steps = 3}) => Demo(
  level: 'assets/levels/crypt.json',
  start: const Snapshot(<String, Object?>{'random': 7, 'health': 100}),
  tape: InputTape(
    seed: 7,
    frames: <InputFrame>[
      for (var i = 0; i < steps; i++)
        InputFrame(pressed: i == 0 ? const <String>['fire'] : const <String>[]),
    ],
  ),
);

void main() {
  group('the document', () {
    test('survives a round trip through JSON', () {
      final written = _demo();

      final read = Demo.fromJson(
        jsonDecode(jsonEncode(written.toJson())) as Map<String, Object?>,
      );

      expect(read.level, written.level);
      expect(read.start.data, written.start.data);
      expect(read.tape.seed, written.tape.seed);
      expect(read.steps, written.steps);
      expect(read.tape.frames.first.pressed, <String>['fire']);
    });

    test('refuses a demo from a newer build, and says so', () {
      // The case the version exists for: the file can still be opened by the
      // build that wrote it, and "could not be read" would hide that.
      final json = _demo().toJson()..['version'] = Demo.formatVersion + 1;

      expect(
        () => Demo.fromJson(json),
        throwsA(
          isA<DemoFormatException>().having(
            (e) => e.message,
            'message',
            contains('newer build'),
          ),
        ),
      );
    });

    test('refuses a demo with no tape, naming what is missing', () {
      // Not "an empty tape": a document without one was cut short by whatever
      // wrote it, and the player who attached it deserves to be told which.
      final json = _demo().toJson()..remove('tape');

      expect(
        () => Demo.fromJson(json),
        throwsA(
          isA<DemoFormatException>().having(
            (e) => e.message,
            'message',
            contains('no tape'),
          ),
        ),
      );
    });

    test('refuses a demo with no level or no start', () {
      expect(
        () => Demo.fromJson(_demo().toJson()..remove('level')),
        throwsA(isA<DemoFormatException>()),
      );
      expect(
        () => Demo.fromJson(_demo().toJson()..remove('run')),
        throwsA(isA<DemoFormatException>()),
      );
      expect(
        () => Demo.fromJson(<String, Object?>{}),
        throwsA(isA<DemoFormatException>()),
        reason: 'an empty object has no version, which is the first thing said',
      );
    });

    test('and a starting state from the future is refused through it', () {
      final json = _demo().toJson();
      (json['run']! as Map<String, Object?>)['version'] =
          Snapshot.formatVersion + 1;

      expect(
        () => Demo.fromJson(json),
        throwsA(
          isA<DemoFormatException>().having(
            (e) => e.message,
            'message',
            contains('starting state'),
          ),
        ),
      );
    });
  });

  group('the loop', () {
    test('records one entry per step, with the step\'s look in it', () {
      // The moment is the whole point: after the look for the step is added
      // and before the step runs. Recording after the step records the
      // latches it cleared, and recording before the look records a step
      // where the mouse never moved.
      final input = InputState();
      final seen = <double>[];
      final loop = GameLoop(
        input: input,
        onStep: (_) => seen.add(input.lookDelta.x),
        drainLook: (out) => out.setValues(0.3, 0.0),
      )..recorders.add(InputTapeRecorder(seed: 1));

      input.press(_fire);
      final steps = loop.advance(3 / 60);

      expect(steps, 3);
      final tape = loop.recorders.single.tape;
      expect(tape.steps, 3);
      expect(tape.frames.first.pressed, <String>['fire']);
      expect(
        tape.frames.map((f) => f.lookX).toList(),
        seen,
        reason: 'the tape holds the look each step was given, per step',
      );
    });

    test('a tape being played drives the input and the mouse does not', () {
      final tape = InputTape(
        seed: 1,
        frames: <InputFrame>[
          const InputFrame(pressed: <String>['fire'], lookX: 0.5, slot: 3),
          const InputFrame(lookX: 0.25),
        ],
      );
      final input = InputState();
      final fired = <bool>[];
      final looked = <double>[];
      final slots = <int?>[];
      final loop = GameLoop(
        input: input,
        onStep: (_) {
          fired.add(input.held(_fire));
          looked.add(input.lookDelta.x);
          slots.add(input.slotRequest);
        },
        // The mouse moves the whole time, and none of it may reach the run.
        drainLook: (out) => out.setValues(9.0, 9.0),
      )..playback = InputTapePlayback(tape);

      loop.advance(2 / 60);

      expect(fired, <bool>[true, true]);
      expect(looked, <double>[0.5, 0.25]);
      expect(slots, <int?>[
        3,
        null,
      ], reason: 'a slot request is one-shot, and the tape carries it');
    });

    test('a slot request survives the round trip', () {
      // The crypt found this one: a tape of presses and releases has nowhere
      // to put "switch to the shotgun", and a replay without it fires the
      // wrong gun with the wrong ammunition.
      final input = InputState()..requestSlot(2);
      final recorder = InputTapeRecorder(seed: 1)..record(input);

      final read = InputTape.fromJson(
        jsonDecode(jsonEncode(recorder.tape.toJson())) as Map<String, Object?>,
      );
      final replayed = InputState();
      InputTapePlayback(read).applyTo(replayed);

      expect(replayed.slotRequest, 2);
    });

    test('and when the tape runs out the devices are back', () {
      // The frame's look is split evenly over its steps, so two steps of a
      // frame that moved by two get one apiece — and the first of them is the
      // tape's, not the mouse's.
      final input = InputState();
      final looked = <double>[];
      final loop =
          GameLoop(
              input: input,
              onStep: (_) => looked.add(input.lookDelta.x),
              drainLook: (out) => out.setValues(2.0, 0.0),
            )
            ..playback = InputTapePlayback(
              InputTape(
                seed: 1,
                frames: const <InputFrame>[InputFrame(lookX: 0.5)],
              ),
            );

      loop.advance(2 / 60);

      expect(looked, <double>[0.5, 1.0]);
    });

    test('a mute drops the devices and lets the tape through', () {
      // A kill camera's problem: the keyboard writes into the same object the
      // tape does, and a hold from the keyboard would leave the tape's
      // releases releasing nothing.
      final input = InputState()..muted = true;

      input.press(_fire);
      expect(input.held(_fire), isFalse, reason: 'the keyboard is dropped');

      InputTapePlayback(
        InputTape(
          seed: 1,
          frames: const <InputFrame>[
            InputFrame(pressed: <String>['fire']),
          ],
        ),
      ).applyTo(input);

      expect(input.held(_fire), isTrue, reason: 'the tape gets through');
      expect(input.muted, isTrue, reason: 'and the mute is put back');
    });

    test('a recording that begins mid-hold writes the hold down', () {
      // The player was already walking when the recording began. The press
      // that started the walk happened before the first entry, so the first
      // entry has to say so or the replay stands still.
      final input = InputState()..press(GameAction.moveForward);
      input.endStep(); // the press is now history; only the hold remains
      final loop = GameLoop(input: input, onStep: (_) {})
        ..recorders.add(InputTapeRecorder(seed: 1));

      loop.advance(2 / 60);

      final frames = loop.recorders.single.tape.frames;
      expect(frames.first.pressed, contains('moveForward'));
      expect(
        frames[1].pressed,
        isNot(contains('moveForward')),
        reason: 'once only; afterwards the hold follows from the tape',
      );

      // And the replay walks.
      final replayed = InputState();
      InputTapePlayback(loop.recorders.single.tape).applyTo(replayed);
      expect(replayed.moveAxis, Vector2(0.0, 1.0));
    });
  });
}
