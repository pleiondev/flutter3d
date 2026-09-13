import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'net_transport.dart';

/// A pair of [NetTransport]s joined by a fixed delay and a loss rate, for a
/// test that wants two peers actually separated by an unreliable network
/// rather than by nothing.
///
/// **Not a mock.** Nothing here asserts on a call or records what was sent —
/// a message really does take [delaySeconds] longer than a step to arrive,
/// in [stepsPerSecond] units rounded to the nearest whole step, and some
/// really never arrive at all. [NetSession] cannot tell this apart from a
/// slow, lossy WebRTC data channel by looking at it, which is the whole
/// point of [NetTransport] being an interface: this is `net-01`'s "петля с
/// задержкой и потерями" from `doc/tooling-plan.md`, not a stand-in for it.
///
/// **[tick] drives time, not wall-clock or a real event loop.** A test plays
/// both peers deterministically, one fixed step at a time; calling `tick()`
/// on each side once per step is what "120ms of delay" turns into in that
/// world — round it to steps up front, in [pair], rather than carrying a
/// fractional step through delivery.
final class LoopbackTransport implements NetTransport {
  LoopbackTransport._(this._delaySteps, this._lossRate, this._random);

  final int _delaySteps;
  final double _lossRate;
  final GameRandom _random;
  late final LoopbackTransport _peer;

  int _now = 0;
  final List<(int dueAt, Map<String, Object?> message)> _inbox =
      <(int, Map<String, Object?>)>[];
  void Function(Map<String, Object?> message)? _listener;

  /// Builds two transports, each other's peer — [delaySeconds] and
  /// [lossRate] apply to both directions equally, and [seed] makes which
  /// messages are lost repeatable from one run of a test to the next.
  static (LoopbackTransport, LoopbackTransport) pair({
    required int stepsPerSecond,
    double delaySeconds = 0.0,
    double lossRate = 0.0,
    int seed = 1,
  }) {
    assert(
      lossRate >= 0.0 && lossRate <= 1.0,
      'a loss rate is a fraction of messages, not a count',
    );
    final random = GameRandom(seed);
    final delaySteps = (delaySeconds * stepsPerSecond).round();
    final a = LoopbackTransport._(delaySteps, lossRate, random);
    final b = LoopbackTransport._(delaySteps, lossRate, random);
    a._peer = b;
    b._peer = a;
    return (a, b);
  }

  @override
  void send(Map<String, Object?> message) {
    // Rolled here, on the sender's side, against the one generator the pair
    // shares — so which of the two directions a dropped roll belongs to
    // still comes out of a single, seeded sequence, and a test replaying the
    // same seed sees the same drops in the same order they were asked for.
    if (_random.nextDouble() < _lossRate) return;
    _peer._inbox.add((_peer._now + _delaySteps, Map<String, Object?>.of(message)));
  }

  @override
  void listen(void Function(Map<String, Object?> message) onMessage) {
    _listener = onMessage;
  }

  /// Advances this side's clock by one step, delivering anything whose delay
  /// has elapsed — call once per fixed step, the same step [NetSession]
  /// advances by.
  void tick() {
    _now++;
    _inbox.removeWhere((entry) {
      if (entry.$1 > _now) return false;
      _listener?.call(entry.$2);
      return true;
    });
  }
}
