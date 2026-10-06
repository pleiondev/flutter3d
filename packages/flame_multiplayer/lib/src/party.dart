/// More than two machines: a wire that carries everybody's messages to
/// everybody, rollback for a party of them, a spectator played the tape the
/// party settled, and the other model — one machine the authority, the rest
/// predicting.
library;

import 'dart:math' as math;

import 'peer_wire.dart';

/// Every machine in a party, on one wire: what one sends, all the others
/// hear, with who sent it.
///
/// **A slot is a machine's place in the party**, nought up to one fewer
/// than its size, and the same number on every machine — the room hands
/// them out (see the relay's party rooms), so nobody has to agree on it.
abstract interface class PartyWire {
  /// This machine's slot.
  int get slot;

  /// Hands [message] to every other machine; returns at once. Reliable and
  /// unreliable as on a [PeerWire].
  void send(Map<String, Object?> message, {bool reliable = true});

  /// Calls [onMessage] with each message delivered from now on and the
  /// slot it came from. One listener; a second call replaces the first.
  void listen(void Function(int from, Map<String, Object?> message) onMessage);

  /// A party carried on a [PeerWire] that already hands what one machine
  /// sends to all the others — a relay's party room — each message signed
  /// with its sender's [slot].
  static PartyWire over(PeerWire wire, {required int slot}) =>
      _OverPeer(wire, slot);
}

final class _OverPeer implements PartyWire {
  _OverPeer(this._wire, this.slot);

  final PeerWire _wire;

  @override
  final int slot;

  @override
  void send(Map<String, Object?> message, {bool reliable = true}) => _wire.send(
    <String, Object?>{'from': slot, 'body': message},
    reliable: reliable,
  );

  @override
  void listen(
    void Function(int from, Map<String, Object?> message) onMessage,
  ) => _wire.listen((Map<String, Object?> envelope) {
    final from = envelope['from'];
    final body = envelope['body'];
    if (from is! int || body is! Map) return;
    onMessage(from, body.cast<String, Object?>());
  });
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

  final List<({int at, int from, int to, Map<String, Object?> message})>
  _inFlight = <({int at, int from, int to, Map<String, Object?> message})>[];
  final Map<int, void Function(int, Map<String, Object?>)> _listeners =
      <int, void Function(int, Map<String, Object?>)>{};
  int _now = 0;

  /// The wire machine [slot] holds.
  PartyWire wire(int slot) => _LoopbackMember(this, slot);

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
      _listeners[m.to]?.call(m.from, m.message);
    }
  }

  void _send(int from, Map<String, Object?> message, bool reliable) {
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

final class _LoopbackMember implements PartyWire {
  _LoopbackMember(this._party, this.slot);

  final LoopbackParty _party;

  @override
  final int slot;

  @override
  void send(Map<String, Object?> message, {bool reliable = true}) =>
      _party._send(slot, message, reliable);

  @override
  void listen(
    void Function(int from, Map<String, Object?> message) onMessage,
  ) => _party._listeners[slot] = onMessage;
}

/// What one step ran on: the state before it, every slot's frame, and which
/// of them were guesses.
final class _PartyRan<S> {
  const _PartyRan(this.before, this.frames, this.guessed);

  final S before;
  final Map<int, Map<String, Object?>> frames;
  final Set<int> guessed;
}

/// Rollback for a party: every machine runs every step on every slot's
/// frame, its own known and the others' guessed from their last until they
/// arrive, and runs again from the first step a guess was wrong.
///
/// **[RollbackSession] for more than one other machine**, and the same in
/// every other way — a fixed [inputDelay], frames sent unreliably with the
/// last [redundancy] steps of them, a window of [maxRollbackFrames] — so
/// what it says about each holds here per slot. A wrong guess about one
/// machine rolls back to the step it was made on; a later guess about
/// another stays a guess until its own frame comes.
///
/// [onSettled] is told of a step as it leaves the window, with the state it
/// ended in and the frames it ran on — the step every machine now agrees
/// on, which is what a spectator is fed (see [PartyTape]).
final class PartyRollback<S> {
  PartyRollback({
    required this.wire,
    required this.players,
    required this.captureLocalFrame,
    required this.applyAndStep,
    required this.save,
    required this.restore,
    this.inputDelay = 2,
    this.maxRollbackFrames = 8,
    this.redundancy = 8,
    this.onSettled,
    this.onMessage,
  }) : assert(players >= 2 && players <= 32, 'a party of two to thirty-two'),
       assert(inputDelay >= 0, 'a negative delay would apply input early'),
       assert(maxRollbackFrames > 0, 'a window of nought corrects nothing') {
    wire.listen(receive);
  }

  final PartyWire wire;

  /// How many slots the party has, this machine's among them.
  final int players;

  /// This machine's hands for the step about to be captured.
  final Map<String, Object?> Function() captureLocalFrame;

  /// Writes every slot's frame into the game and runs one fixed step;
  /// called again for a step being corrected.
  final void Function(Map<int, Map<String, Object?>> frames) applyAndStep;

  final S Function() save;
  final void Function(S state) restore;

  final int inputDelay;
  final int maxRollbackFrames;
  final int redundancy;

  final void Function(int step, S after, Map<int, Map<String, Object?>> frames)?
  onSettled;

  /// Told of every message on the wire that is not a player's frames — a
  /// spectator saying it is there, a game's own — since a wire has one
  /// listener and this is it.
  final void Function(int from, Map<String, Object?> message)? onMessage;

  int _step = 0;

  /// The step about to run.
  int get step => _step;

  /// Frames that came too late to correct anything.
  int droppedCorrections = 0;

  /// How many steps were run again, over every correction.
  int stepsRerun = 0;

  final Map<int, Map<String, Object?>> _pendingLocal =
      <int, Map<String, Object?>>{};
  final Map<int, Map<String, Object?>> _recentSent =
      <int, Map<String, Object?>>{};
  final Map<int, Map<int, Map<String, Object?>>> _early =
      <int, Map<int, Map<String, Object?>>>{};
  final Map<int, ({int step, Map<String, Object?> frame})> _lastConfirmed =
      <int, ({int step, Map<String, Object?> frame})>{};
  final Map<int, _PartyRan<S>> _history = <int, _PartyRan<S>>{};

  /// Captures this machine's hands, sends them, and runs one step.
  void advance() {
    final appliesAt = _step + inputDelay;
    final captured = captureLocalFrame();
    _pendingLocal[appliesAt] = captured;
    _recentSent[appliesAt] = captured;
    _recentSent.removeWhere((s, _) => s < appliesAt - redundancy);
    wire.send(<String, Object?>{
      'frames': <String, Object?>{
        for (final MapEntry(:key, :value) in _recentSent.entries) '$key': value,
      },
    }, reliable: false);

    final frames = <int, Map<String, Object?>>{};
    final guessed = <int>{};
    for (var slot = 0; slot < players; slot++) {
      if (slot == wire.slot) {
        frames[slot] = _pendingLocal.remove(_step) ?? const <String, Object?>{};
        continue;
      }
      final known = _early[slot]?.remove(_step);
      if (known != null) {
        frames[slot] = known;
        _confirm(slot, _step, known);
      } else {
        frames[slot] = _lastConfirmed[slot]?.frame ?? const <String, Object?>{};
        guessed.add(slot);
      }
    }
    _history[_step] = _PartyRan<S>(save(), frames, guessed);
    _forgetOutsideWindow();
    applyAndStep(frames);
    _step++;
  }

  /// A message from another machine: its frames, each named by its step.
  void receive(int from, Map<String, Object?> message) {
    final frames = message['frames'];
    if (frames is! Map || from == wire.slot || from >= players) {
      onMessage?.call(from, message);
      return;
    }
    final steps = <int, Map<String, Object?>>{
      for (final MapEntry(:key, :value) in frames.entries)
        if ((int.tryParse('$key'), value) case (final int at, final Map frame))
          at: frame.cast<String, Object?>(),
    };
    for (final at in steps.keys.toList()..sort()) {
      _receiveOne(from, at, steps[at]!);
    }
  }

  void _confirm(int slot, int at, Map<String, Object?> frame) {
    final last = _lastConfirmed[slot];
    if (last == null || at >= last.step) {
      _lastConfirmed[slot] = (step: at, frame: frame);
    }
  }

  void _receiveOne(int from, int at, Map<String, Object?> frame) {
    if (at >= _step) {
      (_early[from] ??= <int, Map<String, Object?>>{})[at] = frame;
      return;
    }
    final ran = _history[at];
    if (ran == null) {
      droppedCorrections++;
      return;
    }
    _confirm(from, at, frame);
    if (!ran.guessed.contains(from)) return;
    final right = _same(ran.frames[from]!, frame);
    final frames = <int, Map<String, Object?>>{...ran.frames, from: frame};
    final guessed = <int>{...ran.guessed}..remove(from);
    if (right) {
      _history[at] = _PartyRan<S>(ran.before, frames, guessed);
      return;
    }
    // Guessed wrong: back to before that step, and every step since again —
    // each on what it had on record, this one on the frame that came.
    restore(ran.before);
    for (var s = at; s < _step; s++) {
      final h = s == at
          ? _PartyRan<S>(ran.before, frames, guessed)
          : _history[s]!;
      final before = save();
      applyAndStep(h.frames);
      _history[s] = _PartyRan<S>(before, h.frames, h.guessed);
      stepsRerun++;
    }
  }

  void _forgetOutsideWindow() {
    final horizon = _step - maxRollbackFrames;
    final settled = onSettled;
    if (settled != null) {
      for (final s
          in _history.keys.where((s) => s < horizon).toList()..sort()) {
        final next = _history[s + 1];
        if (next != null) settled(s, next.before, _history[s]!.frames);
      }
    }
    _history.removeWhere((s, _) => s < horizon);
  }

  static bool _same(Map<String, Object?> a, Map<String, Object?> b) =>
      a.length == b.length &&
      a.entries.every((e) => b.containsKey(e.key) && b[e.key] == e.value);
}

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

  final PartyWire wire;

  /// A state as something a wire carries.
  final Object? Function(S state) encode;

  /// Which slot does the sending.
  final int host;

  ({int step, S after})? _last;
  bool _anybodyWatching = false;

  bool get _hosting => wire.slot == host;

  /// Hands a settled step on — wire this to [PartyRollback.onSettled].
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
    wire.listen(hear);
  }

  final PartyWire wire;
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
    wire.listen(receive);
  }

  final PartyWire wire;
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
    wire.listen(receive);
  }

  final PartyWire wire;
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
