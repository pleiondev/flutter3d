/// The one door between machines, and loopbacks that stand in for it.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show Registration;

/// Whether a [PeerWire] carries messages.
///
/// An open class with constants, not an enum: a later minor may add a state
/// (reconnecting, say), and a `switch` written against three would stop
/// compiling.
final class WireState {
  const WireState._(this.name);

  /// Not yet carrying anything: a socket still shaking hands.
  static const WireState connecting = WireState._('connecting');

  /// Carrying messages.
  static const WireState open = WireState._('open');

  /// Closed, from either end; nothing more is carried.
  static const WireState closed = WireState._('closed');

  final String name;

  @override
  String toString() => 'WireState.$name';
}

/// Whatever carries messages between machines: a relay's WebSocket, a
/// WebRTC data channel, a game networking library's connection, a party
/// room's fan-out.
///
/// **The one transport** every mode here speaks, two machines or a party:
/// [send], [listen], [close], [state]. What a party adds is who said a
/// message — [listenFrom] — and this machine's [slot] among them; a wire
/// between two machines answers those too, the other machine being the
/// other slot.
///
/// **Several listeners, each its own registration.** A room, a rollback and
/// a spectator's tape may all hear one wire; each [listen] adds a listener
/// and hands back the [Registration] that takes it away again, so none of
/// them takes the wire over from another.
///
/// **One key is the engine's.** A message whose [engineKey] (`"f3d"`) is set
/// is one the engine's own protocol sent — a rollback's frames, say — and a
/// game never sets it on its own messages: that is how the two share a wire
/// without one mistaking the other's message for its own.
///
/// **Messages are JSON-shaped maps,** because every mode here is a handful of
/// numbers and names, and every transport can carry text. An adapter that
/// moves bytes encodes them as JSON in UTF-8. **What is not a handful of
/// numbers goes as bytes** — [sendBytes] and [listenBytes] — which every
/// wire carries as base64 inside a JSON frame unless it overrides them to
/// carry binary as it is.
///
/// **Two kinds of delivery, asked for per message.** A [send] that is
/// reliable arrives once and in order with the other reliable ones: a
/// handshake, the turn handed over, a target that went down. An unreliable
/// one may be lost, late or out of order, and the mode that sends it copes:
/// a rollback frame that repeats the last few steps, a ghost's position that
/// the next one replaces. A wire that is reliable throughout, as a
/// WebSocket is, treats both alike.
///
/// **Extended outside this package: an `abstract base class` with
/// defaults** (decision 5 of flutter3d's 1.0 review), so a member added in a
/// minor arrives with a default and every adapter keeps compiling. An
/// adapter writes [send], and calls [deliver] with every message that
/// arrives; the rest has bodies.
abstract base class PeerWire {
  PeerWire();

  /// The key the engine's own messages carry, naming which of its
  /// protocols sent them: `{"f3d": "rollback", …}`. Reserved: a game's
  /// message never has it.
  static const String engineKey = 'f3d';

  /// A party carried on [wire], which already hands what one machine sends
  /// to all the others — a relay's party room — each message signed with its
  /// sender's [slot].
  static PeerWire party(PeerWire wire, {required int slot}) =>
      _OverPeer(wire, slot);

  /// This machine's place among the machines the wire joins, the same
  /// number on every machine: nought for whoever made a room, one for who
  /// joined it, up to one fewer than a party's size. Nought by default.
  int get slot => 0;

  /// Whether the wire carries messages. [WireState.open] by default.
  WireState get state => WireState.open;

  /// Hands [message] over for delivery; returns at once.
  void send(Map<String, Object?> message, {bool reliable = true});

  /// Calls [onMessage] for every message delivered from now on, until the
  /// returned registration is cancelled. Every listener hears every
  /// message, in the order they were added.
  Registration listen(void Function(Map<String, Object?> message) onMessage) =>
      listenFrom((_, message) => onMessage(message));

  /// Calls [onMessage] with every message delivered from now on and the
  /// slot of the machine that sent it, until the returned registration is
  /// cancelled.
  Registration listenFrom(
    void Function(int from, Map<String, Object?> message) onMessage,
  ) {
    _listeners.add(onMessage);
    return Registration(() => _listeners.remove(onMessage));
  }

  final List<void Function(int from, Map<String, Object?> message)> _listeners =
      <void Function(int from, Map<String, Object?> message)>[];

  /// Hands [message], arrived from slot [from], to every listener: what an
  /// adapter calls for each message the connection brings. [from] left out
  /// is the other machine of two — `1 - slot`; a party's wire says who.
  ///
  /// A message that is [sendBytes]' frame — `{"f3d": "bytes", …}` — goes to
  /// the byte listeners ([listenBytes]) instead, as its bytes.
  void deliver(Map<String, Object?> message, {int? from}) {
    final sender = from ?? 1 - slot;
    if (message[engineKey] == bytesFrame) {
      final encoded = message[bytesKey];
      if (encoded is String) {
        try {
          deliverBytes(base64Decode(encoded), from: sender);
        } on FormatException {
          // A frame that is not base64 is passed over, as an adapter passes
          // over a payload that is not JSON.
        }
      }
      return;
    }
    for (final listener in List.of(_listeners)) {
      listener(sender, message);
    }
  }

  /// What [sendBytes]' frame carries under [engineKey]: `{"f3d": "bytes",
  /// "b": …}`, the bytes in base64, on a wire that carries only JSON.
  static const String bytesFrame = 'bytes';

  /// The key the bytes are under in [bytesFrame], as base64.
  static const String bytesKey = 'b';

  /// Hands [bytes] over for delivery, as [send] hands a message; returns at
  /// once.
  ///
  /// **For what is not a handful of numbers**: a snapshot, a voice frame, an
  /// encoded published state. By default the bytes travel as base64 inside a
  /// JSON frame ([bytesFrame]) through [send], so every wire carries them; a
  /// wire that carries binary as it is — a WebRTC data channel, a WebSocket,
  /// a loopback — overrides this and [deliverBytes] is called with what
  /// arrives. The two ends need not agree on which: a frame arriving at a
  /// wire that overrides this is still delivered as bytes.
  void sendBytes(Uint8List bytes, {bool reliable = true}) => send(
    <String, Object?>{engineKey: bytesFrame, bytesKey: base64Encode(bytes)},
    reliable: reliable,
  );

  /// Calls [onBytes] with every byte message delivered from now on and the
  /// slot of the machine that sent it, until the returned registration is
  /// cancelled. A byte message never reaches [listen]'s listeners, nor a
  /// JSON one these.
  Registration listenBytes(void Function(int from, Uint8List bytes) onBytes) {
    _byteListeners.add(onBytes);
    return Registration(() => _byteListeners.remove(onBytes));
  }

  final List<void Function(int from, Uint8List bytes)> _byteListeners =
      <void Function(int from, Uint8List bytes)>[];

  /// Hands [bytes], arrived from slot [from], to every byte listener: what an
  /// adapter that carries binary calls for each binary message. [from] as
  /// [deliver] reads it.
  void deliverBytes(Uint8List bytes, {int? from}) {
    final sender = from ?? 1 - slot;
    for (final listener in List.of(_byteListeners)) {
      listener(sender, bytes);
    }
  }

  /// Lets the connection go. Nothing by default; an adapter over a socket
  /// closes it.
  Future<void> close() async {}
}

/// Two [PeerWire]s joined to each other in one process, as late and as lossy
/// as a test asks, and repeatable from its seed.
///
/// **Time is steps, and the test turns them.** A message sent is delivered
/// [delaySteps] calls of [tick] later on the other side. An unreliable one is
/// lost one time in `1 / lossRate`, rolled from a generator both sides share,
/// so the same seed loses the same messages; a reliable one is never lost,
/// which is the promise it stands for. The first end is slot nought, the
/// second slot one.
final class LoopbackWire extends PeerWire {
  LoopbackWire._(this._delaySteps, this._lossRate, this._random, this.slot);

  /// Two ends of one wire, slot nought and slot one. [delaySteps] calls of
  /// [tick] a message takes; [lossRate] the share of unreliable ones lost.
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
    final a = LoopbackWire._(delaySteps, lossRate, random, 0);
    final b = LoopbackWire._(delaySteps, lossRate, random, 1);
    a._peer = b;
    b._peer = a;
    return (a, b);
  }

  final int _delaySteps;
  final double _lossRate;
  final _Xorshift _random;
  late final LoopbackWire _peer;
  int _now = 0;
  bool _closed = false;
  // A message or bytes, each with the tick it is due at.
  final List<(int, Object)> _inbox = <(int, Object)>[];

  @override
  final int slot;

  @override
  WireState get state => _closed ? WireState.closed : WireState.open;

  /// Unreliable messages lost so far, from this side.
  int lost = 0;

  @override
  void send(Map<String, Object?> message, {bool reliable = true}) {
    if (_closed || _peer._closed) return;
    if (!reliable && _random.nextDouble() < _lossRate) {
      lost++;
      return;
    }
    // Copied as a real wire would, so the sender changing its map later
    // changes nothing on the far side.
    _peer._inbox.add((_peer._now + _delaySteps, _deepCopy(message)));
  }

  /// Carried as bytes, not as a base64 frame: a copy, so the sender
  /// reusing its buffer changes nothing on the far side, lost and late as
  /// a message is.
  @override
  void sendBytes(Uint8List bytes, {bool reliable = true}) {
    if (_closed || _peer._closed) return;
    if (!reliable && _random.nextDouble() < _lossRate) {
      lost++;
      return;
    }
    _peer._inbox.add((_peer._now + _delaySteps, Uint8List.fromList(bytes)));
  }

  @override
  Future<void> close() async {
    _closed = true;
    _inbox.clear();
  }

  /// One step of this side's clock: delivers what is due, messages and
  /// bytes in the order they were sent.
  void tick() {
    _now++;
    final due = <Object>[
      for (final (at, message) in _inbox)
        if (at <= _now) message,
    ];
    _inbox.removeWhere((entry) => entry.$1 <= _now);
    for (final message in due) {
      switch (message) {
        case final Uint8List bytes:
          deliverBytes(bytes);
        case final Map<String, Object?> map:
          deliver(map);
      }
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

final class _OverPeer extends PeerWire {
  _OverPeer(this._wire, this.slot) {
    _wire.listen((Map<String, Object?> envelope) {
      final from = envelope['from'];
      final body = envelope['body'];
      if (from is! int || body is! Map) return;
      deliver(body.cast<String, Object?>(), from: from);
    });
  }

  final PeerWire _wire;

  @override
  final int slot;

  @override
  WireState get state => _wire.state;

  @override
  void send(Map<String, Object?> message, {bool reliable = true}) => _wire.send(
    <String, Object?>{'from': slot, 'body': message},
    reliable: reliable,
  );

  @override
  Future<void> close() => _wire.close();
}

/// [size] machines on one wire in one process, as late and as lossy as a
/// test asks, the same losses for the same seed — the party's
/// [LoopbackWire].
final class LoopbackParty {
  LoopbackParty(
    this.size, {
    this.delaySteps = 0,
    this.lossRate = 0.0,
    int seed = 1,
  }) : _random = math.Random(seed),
       assert(size >= 2, 'a party is at least two');

  final int size;

  /// How many [tick]s a message takes to arrive.
  final int delaySteps;

  /// The share of unreliable messages that never arrive.
  final double lossRate;
  final math.Random _random;

  // A message or bytes, each with when it is due, who sent it and to whom.
  final List<({int at, int from, int to, Object message})> _inFlight =
      <({int at, int from, int to, Object message})>[];
  final Map<int, _LoopbackMember> _members = <int, _LoopbackMember>{};
  int _now = 0;

  /// The wire machine [slot] holds: the same one every time it is asked.
  PeerWire wire(int slot) => _members[slot] ??= _LoopbackMember(this, slot);

  /// Machines the wire carries nothing to or from, as a dropped connection
  /// does — the party goes on without them.
  final Set<int> cut = <int>{};

  /// One step of time: whatever is due arrives, in the order it was sent.
  void tick() {
    _now++;
    final due = _inFlight.where((m) => m.at <= _now).toList();
    _inFlight.removeWhere((m) => m.at <= _now);
    for (final m in due) {
      if (cut.contains(m.to) || cut.contains(m.from)) continue;
      final member = _members[m.to];
      switch (m.message) {
        case final Uint8List bytes:
          member?.deliverBytes(bytes, from: m.from);
        case final Map<String, Object?> map:
          member?.deliver(map, from: m.from);
      }
    }
  }

  void _send(int from, Object message, bool reliable) {
    for (var to = 0; to < size; to++) {
      if (to == from) continue;
      // Rolled for every copy, kept or not, so a seed loses the same ones.
      final lost = _random.nextDouble() < lossRate;
      if (!reliable && lost) continue;
      _inFlight.add((
        at: _now + delaySteps,
        from: from,
        to: to,
        message: message,
      ));
    }
  }
}

final class _LoopbackMember extends PeerWire {
  _LoopbackMember(this._party, this.slot);

  final LoopbackParty _party;

  @override
  final int slot;

  @override
  WireState get state =>
      _party.cut.contains(slot) ? WireState.closed : WireState.open;

  @override
  void send(Map<String, Object?> message, {bool reliable = true}) =>
      _party._send(slot, message, reliable);

  @override
  void sendBytes(Uint8List bytes, {bool reliable = true}) =>
      _party._send(slot, Uint8List.fromList(bytes), reliable);
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
