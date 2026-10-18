/// What a step is handed: its number, every slot's frame, whether each was
/// heard, guessed or is from a machine gone, and whether the step is being
/// run again.
///
///     dart test test/rollback_step_test.dart
library;

import 'package:flutter3d_net/flutter3d_net.dart';
import 'package:test/test.dart';

PeerSend _frames(Map<int, Map<String, Object?>> byStep) => PeerSend(
  message: <String, Object?>{
    PeerWire.engineKey: RollbackSession.messageKind,
    'frames': <String, Object?>{
      for (final MapEntry(:key, :value) in byStep.entries) '$key': value,
    },
  },
);

void main() {
  test('a step on a guess says so, and the step run again on the frame '
      'that came says it was heard', () {
    // Mutation: drop the guessed set before the call, as before 1.0, and
    // every remote slot reads confirmed, so a predicted hit plays its sound.
    final LoopbackPair(first: ours, second: theirs) = LoopbackWire.pair();
    final steps = <RollbackStep>[];
    final session = RollbackSession<int>(
      wire: ours,
      inputDelay: 0,
      captureLocalFrame: () => const <String, Object?>{'move': 1},
      applyAndStep: steps.add,
      save: () => steps.length,
      restore: (_) {},
    );
    addTearDown(session.dispose);

    session.advance();
    expect(steps.single.step, 0);
    expect(steps.single.resimulated, isFalse);
    expect(steps.single.statusOf(0), InputStatus.confirmed);
    expect(steps.single.statusOf(1), InputStatus.predicted);
    expect(steps.single.frames[0], <String, Object?>{'move': 1});

    // The other machine's frame for step 0 comes, and is not the guess.
    theirs.send(
      _frames(<int, Map<String, Object?>>{
        0: <String, Object?>{'move': -1},
      }),
    );
    ours.step();
    expect(steps, hasLength(2));
    final again = steps.last;
    expect(again.step, 0);
    expect(again.resimulated, isTrue);
    expect(again.statusOf(1), InputStatus.confirmed);
    expect(again.frames[1], <String, Object?>{'move': -1});

    // A frame already in hand for the step about to run is confirmed.
    theirs.send(
      _frames(<int, Map<String, Object?>>{
        1: <String, Object?>{'move': 0},
      }),
    );
    ours.step();
    session.advance();
    expect(steps.last.step, 1);
    expect(steps.last.statusOf(1), InputStatus.confirmed);
  });

  test('a slot behind a closed wire is disconnected, not predicted', () async {
    // Mutation: read only the guessed set, and a player whose connection
    // dropped is predicted for ever, still running on their last hands.
    final LoopbackPair(first: ours) = LoopbackWire.pair();
    final steps = <RollbackStep>[];
    final session = RollbackSession<int>(
      wire: ours,
      captureLocalFrame: () => const <String, Object?>{},
      applyAndStep: steps.add,
      save: () => steps.length,
      restore: (_) {},
    );
    addTearDown(session.dispose);
    await ours.close();
    session.advance();
    expect(steps.single.statusOf(1), InputStatus.disconnected);
    expect(steps.single.statusOf(0), InputStatus.confirmed);
  });

  test('a slot past the players is refused', () {
    const step = RollbackStep(
      step: 3,
      frames: <int, Map<String, Object?>>{
        0: <String, Object?>{},
        1: <String, Object?>{},
      },
      predicted: <int>{1},
      resimulated: false,
    );
    expect(step.statusOf(0), InputStatus.confirmed);
    expect(step.statusOf(1), InputStatus.predicted);
    expect(() => step.statusOf(2), throwsRangeError);
  });

  test('the statuses are an open set with names', () {
    expect(InputStatus.values, <InputStatus>[
      InputStatus.confirmed,
      InputStatus.predicted,
      InputStatus.disconnected,
    ]);
    expect(InputStatus.byName('predicted'), InputStatus.predicted);
    expect(InputStatus.byName('lost'), isNull);
  });
}
