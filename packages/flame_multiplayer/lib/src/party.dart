/// More than two machines: a spectator played the tape the party settled,
/// and the other model — one machine the authority, the rest predicting.
///
/// The wire is the one [PeerWire] (`PeerWire.party` over a relay's party
/// room, [LoopbackParty] in a test), and the rollback the one
/// [RollbackSession], with `players` above two.
library;

import 'package:flutter3d_net/flutter3d_net.dart'
    show LoopbackParty, PeerWire, RollbackSession;

/// The party's settled steps, sent to whoever only watches — a spectator
/// played the tape rather than taking part in the rollback.
///
/// **From one machine, the [host]**, since every machine settles the same
/// steps the same way and one copy is enough; reliable, since a spectator
/// cannot ask a lost step again. A spectator who arrives late says so
/// ([PartyTapeWatcher] does) and is sent the state of the last settled
/// step, then every step after it.
final class PartyTape<S> {
  PartyTape({required this.wire, required this.encode, this.host = 0});

  final PeerWire wire;

  /// A state as something a wire carries.
  final Object? Function(S state) encode;

  /// Which slot does the sending.
  final int host;

  ({int step, S after})? _last;
  bool _anybodyWatching = false;

  bool get _hosting => wire.slot == host;

  /// Hands a settled step on — wire this to [RollbackSession.onSettled].
  void settled(int step, S after, Map<int, Map<String, Object?>> frames) {
    _last = (step: step, after: after);
    if (!_hosting || !_anybodyWatching) return;
    wire.send(<String, Object?>{
      'tape': step,
      'frames': <String, Object?>{
        for (final MapEntry(:key, :value) in frames.entries) '$key': value,
      },
    });
  }

  /// A message that is a spectator saying it is there — the rollback's
  /// own messages pass through untouched; call this for every one.
  void hear(int from, Map<String, Object?> message) {
    if (!_hosting || message['watching'] != true) return;
    _anybodyWatching = true;
    final last = _last;
    if (last == null) return;
    wire.send(<String, Object?>{
      'tapeFrom': last.step + 1,
      'state': encode(last.after),
    });
  }
}

/// A spectator: says it is watching, takes the state it is sent and the
/// settled steps after it, and plays them in order at its own pace.
final class PartyTapeWatcher<S> {
  PartyTapeWatcher({
    required this.wire,
    required this.decode,
    required this.restore,
    required this.applyAndStep,
  }) {
    wire.listenFrom(hear);
  }

  final PeerWire wire;
  final S Function(Object? encoded) decode;
  final void Function(S state) restore;
  final void Function(Map<int, Map<String, Object?>> frames) applyAndStep;

  final Map<int, Map<int, Map<String, Object?>>> _steps =
      <int, Map<int, Map<String, Object?>>>{};
  int? _next;

  /// The next step it will play, or null before the state has come.
  int? get next => _next;

  /// How many settled steps have come and not been played.
  int get waiting =>
      _next == null ? 0 : _steps.keys.where((s) => s >= _next!).length;

  /// Says it is here, so the host starts sending. Again until the state
  /// comes, since the host may not have heard it the first time.
  void ask() {
    if (_next == null) wire.send(const <String, Object?>{'watching': true});
  }

  void hear(int from, Map<String, Object?> message) {
    if (message['tapeFrom'] case final int from when _next == null) {
      restore(decode(message['state']));
      _next = from;
    }
    if (message['tape'] case final int step) {
      final frames = message['frames'];
      if (frames is! Map) return;
      _steps[step] = <int, Map<String, Object?>>{
        for (final MapEntry(:key, :value) in frames.entries)
          int.parse('$key'): (value as Map).cast<String, Object?>(),
      };
    }
  }

  /// Plays the next settled step if it has come; whether it did.
  bool advance() {
    final at = _next;
    if (at == null) return false;
    final frames = _steps.remove(at);
    if (frames == null) return false;
    applyAndStep(frames);
    _next = at + 1;
    return true;
  }
}

/// The other model, for a party too large to roll back: one machine runs
/// the game for everybody and sends what it is, and the others only send
/// their hands and show what they predict until it says otherwise.
///
/// **The authority**: each step it takes every slot's next frame in the
/// order they were sent — the last one again when the next has not come —
/// runs the step on them, and every [snapshotEvery] steps sends the state
/// with, for each slot, the last frame it ran, so that slot's machine knows
/// which of its own it can stop predicting.
final class AuthorityServer<S> {
  AuthorityServer({
    required this.wire,
    required this.players,
    required this.applyAndStep,
    required this.save,
    required this.encode,
    this.snapshotEvery = 3,
  }) {
    wire.listenFrom(receive);
  }

  final PeerWire wire;
  final int players;
  final void Function(Map<int, Map<String, Object?>> frames) applyAndStep;
  final S Function() save;
  final Object? Function(S state) encode;
  final int snapshotEvery;

  int _step = 0;
  int get step => _step;

  final Map<int, Map<int, Map<String, Object?>>> _queued =
      <int, Map<int, Map<String, Object?>>>{};
  final Map<int, int> _ran = <int, int>{};
  final Map<int, Map<String, Object?>> _held = <int, Map<String, Object?>>{};

  void receive(int from, Map<String, Object?> message) {
    final inputs = message['inputs'];
    if (inputs is! Map) return;
    final queue = _queued[from] ??= <int, Map<String, Object?>>{};
    for (final MapEntry(:key, :value) in inputs.entries) {
      final sequence = int.tryParse('$key');
      if (sequence == null || value is! Map) continue;
      if (sequence <= (_ran[from] ?? -1)) continue;
      queue[sequence] = value.cast<String, Object?>();
    }
  }

  /// One step of the game, for everybody.
  void advance() {
    final frames = <int, Map<String, Object?>>{};
    for (var slot = 0; slot < players; slot++) {
      if (slot == wire.slot) continue;
      final next = (_ran[slot] ?? -1) + 1;
      final frame = _queued[slot]?.remove(next);
      if (frame != null) {
        _ran[slot] = next;
        _held[slot] = frame;
      }
      frames[slot] = _held[slot] ?? const <String, Object?>{};
    }
    applyAndStep(frames);
    _step++;
    if (_step % snapshotEvery == 0) {
      wire.send(<String, Object?>{
        'snapshot': _step,
        'state': encode(save()),
        'ran': <String, Object?>{
          for (final MapEntry(:key, :value) in _ran.entries) '$key': value,
        },
      }, reliable: false);
    }
  }
}

/// A machine under an [AuthorityServer]: sends its hands, numbered, and
/// runs them at once on its own copy so the player sees them now; when the
/// authority's state arrives, takes it, and runs again on top of it the
/// hands the authority had not got to yet.
final class PredictingClient<S> {
  PredictingClient({
    required this.wire,
    required this.captureLocalFrame,
    required this.predict,
    required this.restore,
    required this.decode,
    this.redundancy = 8,
  }) {
    wire.listenFrom(receive);
  }

  final PeerWire wire;
  final Map<String, Object?> Function() captureLocalFrame;

  /// Runs one step of this machine's copy on its own [frame] alone — the
  /// others as the last state the authority sent left them.
  final void Function(Map<String, Object?> frame) predict;
  final void Function(S state) restore;
  final S Function(Object? encoded) decode;
  final int redundancy;

  int _sequence = -1;
  int _lastSnapshot = -1;
  final Map<int, Map<String, Object?>> _unacknowledged =
      <int, Map<String, Object?>>{};

  /// Hands sent and not yet run by the authority — what a game shows as
  /// how far behind the authority this machine is running, and what a test
  /// of the connection reads.
  int get unacknowledged => _unacknowledged.length;

  /// How many steps were run again on top of a state from the authority.
  int replayed = 0;

  void advance() {
    final frame = captureLocalFrame();
    _unacknowledged[++_sequence] = frame;
    wire.send(<String, Object?>{
      'inputs': <String, Object?>{
        for (final s in _unacknowledged.keys.where(
          (s) => s > _sequence - redundancy,
        ))
          '$s': _unacknowledged[s],
      },
    }, reliable: false);
    predict(frame);
  }

  void receive(int from, Map<String, Object?> message) {
    final at = message['snapshot'];
    if (at is! int || at <= _lastSnapshot) return;
    _lastSnapshot = at;
    final ran = (message['ran'] as Map?)?['${wire.slot}'];
    restore(decode(message['state']));
    if (ran is int) _unacknowledged.removeWhere((s, _) => s <= ran);
    for (final s in _unacknowledged.keys.toList()..sort()) {
      predict(_unacknowledged[s]!);
      replayed++;
    }
  }
}
