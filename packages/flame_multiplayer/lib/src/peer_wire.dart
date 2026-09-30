/// The one door between two machines, and a loopback that stands in for it.
library;

/// Whatever carries messages between the two machines: a relay's WebSocket,
/// a WebRTC data channel, a game networking library's connection.
///
/// **Messages are JSON-shaped maps,** because every mode here is a handful of
/// numbers and names, and every transport can carry text. An adapter that
/// moves bytes encodes them as JSON.
///
/// **Two kinds of delivery, asked for per message.** A [reliable] message
/// arrives once and in order with the other reliable ones: a handshake, the
/// turn handed over, a target that went down. An unreliable one may be lost,
/// late or out of order, and the mode that sends it copes: a rollback frame
/// that repeats the last few steps, a ghost's position that the next one
/// replaces. A wire that is reliable throughout, as a WebSocket is, treats
/// both alike; one that is not, as UDP is, sends the unreliable kind
/// without waiting for anything.
abstract interface class PeerWire {
  /// Hands [message] over for delivery; returns at once.
  void send(Map<String, Object?> message, {bool reliable = true});

  /// Calls [onMessage] for every message delivered from now on. One
  /// listener; a second call replaces the first.
  void listen(void Function(Map<String, Object?> message) onMessage);
}

/// Two [PeerWire]s joined to each other in one process, as late and as lossy
/// as a test asks, and repeatable from its seed.
///
/// **Time is steps, and the test turns them.** A message sent is delivered
/// [delaySteps] calls of [tick] later on the other side. An unreliable one is
/// lost one time in `1 / lossRate`, rolled from a generator both sides share,
/// so the same seed loses the same messages; a reliable one is never lost,
/// which is the promise it stands for.
final class LoopbackWire implements PeerWire {
  LoopbackWire._(this._delaySteps, this._lossRate, this._random);

  /// Two ends of one wire.
  static (LoopbackWire, LoopbackWire) pair({
    int delaySteps = 0,
    double lossRate = 0.0,
    int seed = 1,
  }) {
    assert(delaySteps >= 0, 'a message cannot arrive before it was sent');
    assert(
      lossRate >= 0.0 && lossRate <= 1.0,
      'a loss rate is a fraction of messages',
    );
    final random = _Xorshift(seed);
    final a = LoopbackWire._(delaySteps, lossRate, random);
    final b = LoopbackWire._(delaySteps, lossRate, random);
    a._peer = b;
    b._peer = a;
    return (a, b);
  }

  final int _delaySteps;
  final double _lossRate;
  final _Xorshift _random;
  late final LoopbackWire _peer;
  int _now = 0;
  final List<(int, Map<String, Object?>)> _inbox =
      <(int, Map<String, Object?>)>[];
  void Function(Map<String, Object?> message)? _listener;

  /// Unreliable messages lost so far, from this side.
  int lost = 0;

  @override
  void send(Map<String, Object?> message, {bool reliable = true}) {
    if (!reliable && _random.nextDouble() < _lossRate) {
      lost++;
      return;
    }
    // Copied as a real wire would, so the sender changing its map later
    // changes nothing on the far side.
    _peer._inbox.add((_peer._now + _delaySteps, _deepCopy(message)));
  }

  @override
  void listen(void Function(Map<String, Object?> message) onMessage) =>
      _listener = onMessage;

  /// One step of this side's clock: delivers what is due.
  void tick() {
    _now++;
    final due = <Map<String, Object?>>[
      for (final (at, message) in _inbox)
        if (at <= _now) message,
    ];
    _inbox.removeWhere((entry) => entry.$1 <= _now);
    for (final message in due) {
      _listener?.call(message);
    }
  }

  static Map<String, Object?> _deepCopy(Map<String, Object?> map) =>
      <String, Object?>{
        for (final MapEntry(:key, :value) in map.entries) key: _copy(value),
      };

  static Object? _copy(Object? value) => switch (value) {
    final Map<Object?, Object?> map => <String, Object?>{
      for (final MapEntry(:key, :value) in map.entries) '$key': _copy(value),
    },
    final List<Object?> list => <Object?>[for (final v in list) _copy(v)],
    _ => value,
  };
}

/// A small seeded generator, so the loopback needs no package for one.
final class _Xorshift {
  _Xorshift(int seed) : _state = seed == 0 ? 0x9E3779B9 : seed & 0xFFFFFFFF;

  int _state;

  double nextDouble() {
    var x = _state;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    _state = x;
    return x / 0x100000000;
  }
}
