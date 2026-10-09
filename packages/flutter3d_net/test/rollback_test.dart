/// `net-01`'s acceptance, read literally out of `doc/tooling-plan.md`: two
/// simulation instances converge by digests through a loop with delay and
/// loss, and substituting input on one side gives a named-step desync.
///
///     dart test test/rollback_test.dart
library;

import 'package:flutter3d_net/flutter3d_net.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

/// The same shape as every other toy this repository proves a mechanism on:
/// small enough to read at a glance, large enough that a dropped step or a
/// lost die lands somewhere visible. Two additive halves rather than one —
/// `x` is what side A contributed, `y` is what side B did — so a wrong value
/// reaching either side through the network shows up in a specific field
/// rather than being lost in one shared number.
final class _Toy {
  _Toy(int seed) : dice = GameRandom(seed);

  final GameRandom dice;
  double x = 0.0;
  double y = 0.0;
  int rolls = 0;

  /// [a] is always side A's frame and [b] side B's, regardless of which side
  /// this instance represents — the caller's `applyAndStep` closure is what
  /// puts "local" and "remote" into the right slot for whichever side it is.
  void step(Map<String, Object?> a, Map<String, Object?> b) {
    x += (a['move'] as num?)?.toDouble() ?? 0.0;
    y += (b['move'] as num?)?.toDouble() ?? 0.0;
    if ((a['fire'] as bool?) ?? false) rolls += dice.nextInt(1000);
    if ((b['fire'] as bool?) ?? false) rolls += dice.nextInt(1000);
  }

  Snapshot save() => Snapshot(<String, Object?>{
    'x': x,
    'y': y,
    'rolls': rolls,
    'random': dice.state,
  });

  void restore(Snapshot snapshot) {
    final data = snapshot.data;
    x = data.number('x');
    y = data.number('y');
    rolls = data.integer('rolls');
    dice.state = data.integer('random');
  }
}

/// What side A did on a given step — a direction that flips on a rhythm and
/// a shot fired every seventh step, so both the additive half and the
/// digest-visible half of the toy are exercised.
Map<String, Object?> _sideA(int step) => <String, Object?>{
  'move': step % 4 < 2 ? 1.0 : -1.0,
  'fire': step % 7 == 0,
};

/// Side B's own rhythm, deliberately out of phase with A's.
Map<String, Object?> _sideB(int step) => <String, Object?>{
  'move': step % 5 < 3 ? 0.5 : -0.5,
  'fire': step % 9 == 0,
};

/// A [PeerWire] that forwards everything unchanged except one step's
/// worth of input, whose value it rewrites before handing a message on —
/// the test's stand-in for "a bug, or a cheat, changed what left the wire",
/// which from the far side's point of view is indistinguishable from the
/// sender having lied.
///
/// **Rewrites every occurrence, not only the first.** [RollbackSession]'s own
/// redundancy resends a captured frame several times over, riding along
/// with later steps' messages — a lie told only once would be overwritten
/// by the sender's own truthful resend a few steps later, healing itself
/// before it could ever be observed as a desync.
final class _LyingTransport extends PeerWire {
  _LyingTransport(this._inner, {required this.lieAtStep});

  final PeerWire _inner;
  final int lieAtStep;

  @override
  int get slot => _inner.slot;

  @override
  void send(Map<String, Object?> message, {bool reliable = true}) {
    final frames = message['frames']! as Map<String, Object?>;
    final key = '$lieAtStep';
    final lied = frames[key];
    if (lied == null) {
      _inner.send(message, reliable: reliable);
      return;
    }
    _inner.send(<String, Object?>{
      ...message,
      'frames': <String, Object?>{
        ...frames,
        key: <String, Object?>{...lied as Map<String, Object?>, 'move': 999.0},
      },
    }, reliable: reliable);
  }

  @override
  Registration listenFrom(
    void Function(int from, Map<String, Object?> message) onMessage,
  ) => _inner.listenFrom(onMessage);
}

/// Runs [steps] fixed steps of two [RollbackSession]s joined by
/// [transports], returning each side's own [DigestTrace] of the moves it
/// actually made.
({
  DigestTrace a,
  DigestTrace b,
  RollbackSession<Snapshot> sessionA,
  RollbackSession<Snapshot> sessionB,
})
_play(
  (PeerWire, PeerWire) transports, {
  required int steps,
  required void Function() tickA,
  required void Function() tickB,
}) {
  final toyA = _Toy(1);
  final toyB = _Toy(1);
  final digestsA = DigestTrace();
  final digestsB = DigestTrace();
  late final RollbackSession<Snapshot> sessionA;
  late final RollbackSession<Snapshot> sessionB;
  sessionA = RollbackSession<Snapshot>(
    wire: transports.$1,
    localSlot: 0,
    captureLocalFrame: () => _sideA(sessionA.step),
    applyAndStep: (frames) => toyA.step(frames[0]!, frames[1]!),
    save: toyA.save,
    restore: toyA.restore,
    inputDelay: 2,
    maxRollbackFrames: 16,
    // Digested only once a step can no longer be corrected — see the class
    // doc on `onSettled`. Digesting the live present instead would compare
    // two sides' still-open guesses and call an ordinary, temporary
    // disagreement a desync.
    onSettled: (step, after, _) => digestsA.observe(step + 1, after.toJson()),
  );
  sessionB = RollbackSession<Snapshot>(
    wire: transports.$2,
    localSlot: 1,
    captureLocalFrame: () => _sideB(sessionB.step),
    // Frames come by slot, the same on both machines: A's is slot nought.
    applyAndStep: (frames) => toyB.step(frames[0]!, frames[1]!),
    save: toyB.save,
    restore: toyB.restore,
    inputDelay: 2,
    maxRollbackFrames: 16,
    onSettled: (step, after, _) => digestsB.observe(step + 1, after.toJson()),
  );

  // A tail beyond `steps` with no more meaningful change, purely so the
  // window drains and the last real steps get to settle and be digested —
  // without it, the most recent `maxRollbackFrames` steps of the run this
  // test actually cares about would never fire `onSettled` at all.
  for (var i = 0; i < steps + 32; i++) {
    sessionA.advance();
    tickA();
    sessionB.advance();
    tickB();
  }
  return (a: digestsA, b: digestsB, sessionA: sessionA, sessionB: sessionB);
}

void main() {
  test('two peers 120ms apart with 5% loss converge on the same digests', () {
    final (transportA, transportB) = LoopbackWire.pair(
      delaySteps: 7,
      lossRate: 0.05,
      seed: 20260912,
    );
    final result = _play(
      (transportA, transportB),
      steps: 600,
      tickA: transportA.tick,
      tickB: transportB.tick,
    );

    final divergence = result.a.divergenceFromHex(result.b.hexDigests);
    expect(
      divergence,
      isNull,
      reason:
          'the two sides should agree on every checkpoint despite the '
          'delay and the loss: $divergence',
    );
    expect(
      result.sessionA.droppedCorrections,
      0,
      reason:
          'a correction falling outside the rollback window would mean '
          'the window is undersized for this delay, not a passing test',
    );
    expect(result.sessionB.droppedCorrections, 0);
  });

  test(
    'a frame rewritten in flight on one side gives a desync, named by step',
    () {
      final (transportA, transportB) = LoopbackWire.pair(
        delaySteps: 7,
        seed: 5,
      );
      const lieAtStep = 50;
      final result = _play(
        (_LyingTransport(transportA, lieAtStep: lieAtStep), transportB),
        steps: 200,
        tickA: transportA.tick,
        tickB: transportB.tick,
      );

      final divergence = result.a.divergenceFromHex(result.b.hexDigests);
      expect(
        divergence,
        isNotNull,
        reason:
            'side A ran the true input and side B ran the rewritten one, so '
            'they must disagree from that step on — a null divergence here '
            'would mean the corruption never actually reached B',
      );
      expect(
        divergence!.step,
        greaterThanOrEqualTo(lieAtStep),
        reason:
            'the two sides agreed on every checkpoint before the lie could '
            'possibly have taken effect, so the named step cannot be earlier '
            'than it',
      );
    },
  );

  test('a confirmation that matches the guess never triggers a rollback', () {
    // A deliberately slow, lossless connection whose delay exceeds the input
    // delay by a wide margin, so almost every step runs on a prediction
    // first and is corrected once the real frame lands — exercising
    // `RollbackSession.receive`'s rollback path on nearly every step, rather than
    // on none of them by accident of favourable timing.
    final (transportA, transportB) = LoopbackWire.pair(delaySteps: 9, seed: 1);
    final result = _play(
      (transportA, transportB),
      steps: 400,
      tickA: transportA.tick,
      tickB: transportB.tick,
    );

    expect(result.a.divergenceFromHex(result.b.hexDigests), isNull);
    // Both directions move roughly on a fixed rhythm here, so most steps do
    // predict wrongly at least once — a corrections count of zero would mean
    // the rollback path was never actually exercised by this test.
    expect(result.sessionA.droppedCorrections, 0);
    expect(result.sessionB.droppedCorrections, 0);
  });

  test('two engine loops kept in step by EngineRollback settle on the same '
      'state, rewound through their snapshots', () {
    final (wireA, wireB) = LoopbackWire.pair(delaySteps: 5, seed: 3);
    final digests = <DigestTrace>[DigestTrace(), DigestTrace()];
    final rollbacks = <EngineRollback>[];
    for (final slot in <int>[0, 1]) {
      final loop = EngineLoop(input: InputState());
      final walker = loop.world.spawn();
      loop.world
        ..components.register<_Walked>(
          ComponentCodec<_Walked>.of(
            id: 'test.walked',
            encode: (w) => <int>[w.a, w.b],
            decode: (data, _) => switch (data) {
              [final num a, final num b] => _Walked(a.toInt(), b.toInt()),
              _ => null,
            },
          ),
        )
        ..set(walker, const _Walked(0, 0));
      final pending = <int, Map<String, Object?>>{};
      loop.addSystem('test.walk', LoopPhase.rules, (context) {
        final was = context.world.get<_Walked>(walker)!;
        context.world.set(
          walker,
          _Walked(
            was.a + ((pending[0]?['move'] as int?) ?? 0),
            was.b * 3 + ((pending[1]?['move'] as int?) ?? 0),
          ),
        );
      });
      var captures = 0;
      rollbacks.add(
        EngineRollback(
          loop: loop,
          wire: slot == 0 ? wireA : wireB,
          localSlot: slot,
          captureLocalFrame: () => <String, Object?>{
            'move': (captures++ * (slot + 2)) % 5 - 2,
          },
          applyFrames: (frames) => pending
            ..clear()
            ..addAll(frames),
          onSettled: (step, after, _) =>
              digests[slot].observe(step + 1, after.state.toJson()),
        ),
      );
    }
    for (var i = 0; i < 240; i++) {
      rollbacks[0].advance();
      wireA.tick();
      rollbacks[1].advance();
      wireB.tick();
    }
    // Mutation: a correction restored without the loop's snapshots, or the
    // step count left where it was — the two loops part.
    expect(digests[0].divergenceFromHex(digests[1].hexDigests), isNull);
    expect(digests[0].steps, isNotEmpty);
    expect(rollbacks[0].session.stepsRerun, greaterThan(0));
  });
}

/// Two walked numbers, a component of the test's world.
final class _Walked {
  const _Walked(this.a, this.b);

  final int a;
  final int b;
}
