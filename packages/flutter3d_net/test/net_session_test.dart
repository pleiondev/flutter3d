/// `net-01`'s acceptance, read literally out of `doc/tooling-plan.md`: two
/// simulation instances converge by digests through a loop with delay and
/// loss, and substituting input on one side gives a named-step desync.
///
///     dart test test/net_session_test.dart
library;

import 'package:flutter3d_net/flutter3d_net.dart';
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

/// A [NetTransport] that forwards everything unchanged except one step's
/// worth of input, whose value it rewrites before handing a message on —
/// the test's stand-in for "a bug, or a cheat, changed what left the wire",
/// which from the far side's point of view is indistinguishable from the
/// sender having lied.
///
/// **Rewrites every occurrence, not only the first.** [NetSession]'s own
/// redundancy resends a captured frame several times over, riding along
/// with later steps' messages — a lie told only once would be overwritten
/// by the sender's own truthful resend a few steps later, healing itself
/// before it could ever be observed as a desync.
final class _LyingTransport implements NetTransport {
  _LyingTransport(this._inner, {required this.lieAtStep});

  final NetTransport _inner;
  final int lieAtStep;

  @override
  void send(Map<String, Object?> message) {
    final frames = message['frames']! as Map<String, Object?>;
    final key = '$lieAtStep';
    final lied = frames[key];
    if (lied == null) {
      _inner.send(message);
      return;
    }
    _inner.send(<String, Object?>{
      'frames': <String, Object?>{
        ...frames,
        key: <String, Object?>{...lied as Map<String, Object?>, 'move': 999.0},
      },
    });
  }

  @override
  void listen(void Function(Map<String, Object?> message) onMessage) =>
      _inner.listen(onMessage);
}

/// Runs [steps] fixed steps of two [NetSession]s joined by [transports],
/// returning each side's own [DigestTrace] of the moves it actually made.
({DigestTrace a, DigestTrace b, NetSession sessionA, NetSession sessionB})
_play(
  (NetTransport, NetTransport) transports, {
  required int steps,
  required void Function() tickA,
  required void Function() tickB,
}) {
  final toyA = _Toy(1);
  final toyB = _Toy(1);
  final digestsA = DigestTrace();
  final digestsB = DigestTrace();
  late final NetSession sessionA;
  late final NetSession sessionB;
  sessionA = NetSession(
    transport: transports.$1,
    captureLocalFrame: () => _sideA(sessionA.step),
    applyAndStep: (local, remote) => toyA.step(local, remote),
    save: toyA.save,
    restore: toyA.restore,
    inputDelay: 2,
    maxRollbackFrames: 16,
    // Digested only once a step can no longer be corrected — see the class
    // doc on `onSettled`. Digesting the live present instead would compare
    // two sides' still-open guesses and call an ordinary, temporary
    // disagreement a desync.
    onSettled: (step, after) => digestsA.observe(step + 1, after.toJson()),
  );
  sessionB = NetSession(
    transport: transports.$2,
    captureLocalFrame: () => _sideB(sessionB.step),
    // B's own input is side B's; the remote frame arriving over the wire is
    // side A's — `toy.step(a, b)` wants them in that order regardless.
    applyAndStep: (local, remote) => toyB.step(remote, local),
    save: toyB.save,
    restore: toyB.restore,
    inputDelay: 2,
    maxRollbackFrames: 16,
    onSettled: (step, after) => digestsB.observe(step + 1, after.toJson()),
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
    final (transportA, transportB) = LoopbackTransport.pair(
      stepsPerSecond: 60,
      delaySeconds: 0.120,
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
      final (transportA, transportB) = LoopbackTransport.pair(
        stepsPerSecond: 60,
        delaySeconds: 0.120,
        lossRate: 0.0,
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
    // `NetSession.receive`'s rollback path on nearly every step, rather than
    // on none of them by accident of favourable timing.
    final (transportA, transportB) = LoopbackTransport.pair(
      stepsPerSecond: 60,
      delaySeconds: 0.150,
      seed: 1,
    );
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
}
