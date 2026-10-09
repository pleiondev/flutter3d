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

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const GameAction _fire = GameAction('fire');

Demo _demo({int steps = 3}) {
  final checkpoints = DigestTrace(every: 1);
  for (var step = 1; step <= steps; step++) {
    checkpoints.observe(step, <String, Object?>{'step': step});
  }
  return Demo(
    level: 'assets/levels/crypt.json',
    levelHash: 'deadbeef',
    start: const Snapshot(<String, Object?>{'random': 7, 'health': 100}),
    tape: InputTape(
      seed: 7,
      frames: <InputFrame>[
        for (var i = 0; i < steps; i++)
          InputFrame(
            pressed: i == 0 ? const <String>['fire'] : const <String>[],
          ),
      ],
    ),
    buildStamp: 'test-build',
    checkpoints: checkpoints,
  );
}

void main() {
  group('the document', () {
    test('survives a round trip through JSON', () {
      final written = _demo();

      final read = Demo.fromJson(
        jsonDecode(jsonEncode(written.toJson())) as Map<String, Object?>,
      );

      expect(read.level, written.level);
      expect(read.levelHash, written.levelHash);
      expect(read.start.data, written.start.data);
      expect(read.tape.seed, written.tape.seed);
      expect(read.steps, written.steps);
      expect(read.tape.frames.first.pressed, <String>['fire']);
      expect(read.buildStamp, written.buildStamp);
      expect(read.checkpoints.hexDigests, written.checkpoints.hexDigests);
      expect(read.checkpoints.steps, written.checkpoints.steps);
      expect(read.platform, isNull);
      expect(read.recordedBy, isNull);
      expect(read.physics, isNull);
    });

    test(
      'carries platform, who recorded it and on what physics, when given them',
      () {
        final written = Demo(
          level: 'assets/levels/crypt.json',
          levelHash: 'deadbeef',
          start: const Snapshot(<String, Object?>{}),
          tape: InputTape(seed: 1, frames: const <InputFrame>[]),
          buildStamp: 'test-build',
          checkpoints: DigestTrace(every: 1),
          platform: 'macos',
          recordedBy: 'dmitrii',
          physics: 'dart',
        );

        final read = Demo.fromJson(
          jsonDecode(jsonEncode(written.toJson())) as Map<String, Object?>,
        );

        expect(read.platform, 'macos');
        expect(read.recordedBy, 'dmitrii');
        // What it replays on. Mutation: dropping it on the way out.
        expect(read.physics, 'dart');
      },
    );

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

    test('refuses a demo with no level, no start, no hash, no stamp or no '
        'checkpoints', () {
      for (final field in <String>[
        'level',
        'run',
        'levelHash',
        'buildStamp',
        'checkpoints',
      ]) {
        expect(
          () => Demo.fromJson(_demo().toJson()..remove(field)),
          throwsA(isA<DemoFormatException>()),
          reason: 'missing "$field" should be refused',
        );
      }
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

    test('and malformed checkpoints are refused through it', () {
      final json = _demo().toJson();
      (json['checkpoints']! as Map<String, Object?>)['digests'] = <String>[
        'onlyone',
      ];

      expect(
        () => Demo.fromJson(json),
        throwsA(
          isA<DemoFormatException>().having(
            (e) => e.message,
            'message',
            contains('checkpoints'),
          ),
        ),
      );
    });
  });

  group('HR3: a level swapped under the run', () {
    Demo swapped(List<DemoLevelSwap> swaps) {
      final plain = _demo(steps: 6);
      return Demo(
        level: plain.level,
        levelHash: plain.levelHash,
        start: plain.start,
        tape: plain.tape,
        buildStamp: plain.buildStamp,
        checkpoints: plain.checkpoints,
        levelSwaps: swaps,
      );
    }

    test('carries the document and its step through JSON', () {
      final edit = Level(name: 'crypt', fogDensity: 0.02);
      final json =
          jsonDecode(
                jsonEncode(
                  swapped(<DemoLevelSwap>[
                    DemoLevelSwap(step: 4, level: edit),
                  ]).toJson(),
                ),
              )
              as Map<String, Object?>;

      final read = Demo.fromJson(json);

      expect(read.levelSwaps.single.step, 4);
      expect(read.levelSwaps.single.levelHash, edit.digestHex);
      expect(read.levelSwaps.single.level.fogDensity, 0.02);
      // Mutation: write 1 whatever the run holds — a build that cannot
      // replay the swap opens the file and plays through it to a divergence.
      expect(json['version'], 2);
    });

    test('a run with no swap is still written as format 1', () {
      // Mutation: always write `formatVersion` — every demo this build
      // records becomes unreadable to the build before it, for nothing.
      expect(_demo().toJson()['version'], 1);
      expect(_demo().toJson().containsKey('levelSwaps'), isFalse);
    });

    test('refuses a document that no longer digests to its hash', () {
      final json = swapped(<DemoLevelSwap>[
        DemoLevelSwap(step: 2, level: Level(name: 'crypt')),
      ]).toJson();
      final swap = (json['levelSwaps']! as List<Map<String, Object?>>).single;
      (swap['document']! as Map<String, Object?>)['fogDensity'] = 0.5;

      // Mutation: trust the hash — the replay swaps in a level nobody played.
      expect(
        () =>
            Demo.fromJson(jsonDecode(jsonEncode(json)) as Map<String, Object?>),
        throwsA(
          isA<DemoFormatException>().having(
            (e) => e.message,
            'message',
            contains('digests to'),
          ),
        ),
      );
    });

    test('refuses swaps out of order, or past the end of the tape', () {
      final level = Level(name: 'crypt');
      for (final swaps in <List<DemoLevelSwap>>[
        <DemoLevelSwap>[
          DemoLevelSwap(step: 4, level: level),
          DemoLevelSwap(step: 2, level: level),
        ],
        <DemoLevelSwap>[
          DemoLevelSwap(step: 3, level: level),
          DemoLevelSwap(step: 3, level: level),
        ],
        <DemoLevelSwap>[DemoLevelSwap(step: 7, level: level)],
      ]) {
        // Mutation: drop the order check — a replay walking the list once
        // would skip the swap that came second and play the wrong level.
        expect(
          () => Demo.fromJson(
            jsonDecode(jsonEncode(swapped(swaps).toJson()))
                as Map<String, Object?>,
          ),
          throwsA(isA<DemoFormatException>()),
          reason: 'steps ${swaps.map((s) => s.step).toList()}',
        );
      }
    });

    test('a trace forgets what was observed after a step, and keeps the '
        'rest', () {
      final trace = DigestTrace(every: 2);
      for (var step = 1; step <= 8; step++) {
        trace.observe(step, <String, Object?>{'step': step});
      }

      trace.forgetAfter(5);

      // Mutation: forget from the step on — the checkpoint at the swap's own
      // step, taken under the old level and still true, goes with it.
      expect(trace.steps, <int>[2, 4]);
      trace.forgetAfter(4);
      expect(trace.steps, <int>[2, 4]);
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
      final loop =
          EngineLoop(input: input, drainLook: (out) => out.setValues(0.3, 0.0))
            ..addSystem('look', LoopPhase.rules, (_) {
              seen.add(input.lookDelta.x);
            })
            ..recorders.add(InputTapeRecorder(seed: 1));

      input.press(_fire);
      final steps = loop.frame(3 / 60);

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
      final loop =
          EngineLoop(
              input: input,
              // The mouse moves the whole time, and none of it may reach the
              // run.
              drainLook: (out) => out.setValues(9.0, 9.0),
            )
            ..addSystem('read', LoopPhase.rules, (_) {
              fired.add(input.held(_fire));
              looked.add(input.lookDelta.x);
              slots.add(input.slotRequest);
            })
            ..playback = InputTapePlayback(tape);

      loop.frame(2 / 60);

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
          EngineLoop(input: input, drainLook: (out) => out.setValues(2.0, 0.0))
            ..addSystem('look', LoopPhase.rules, (_) {
              looked.add(input.lookDelta.x);
            })
            ..playback = InputTapePlayback(
              InputTape(
                seed: 1,
                frames: const <InputFrame>[InputFrame(lookX: 0.5)],
              ),
            );

      loop.frame(2 / 60);

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
      final loop = EngineLoop(input: input)
        ..recorders.add(InputTapeRecorder(seed: 1));

      loop.frame(2 / 60);

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
