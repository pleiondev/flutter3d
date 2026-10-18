/// More than two machines: a spectator played the tape the party settled,
/// and the other model — one machine the authority, the rest predicting.
///
/// The wire is the one [PeerWire] (`PeerWire.party` over a relay's party
/// room, [LoopbackParty] in a test), and the rollback the one
/// [RollbackSession], with `players` above two.
///
/// **The party's messages are the engine's.** Each is `{"f3d": "party",
/// "event": …, …}`, under the wire's reserved key, so a game's own message
/// with a `tape`, `frames` or `inputs` field is never taken for one, and a
/// party message is never handed to the game.
///
/// **Nothing passes before the hello.** A machine that joins the party —
/// a spectator asking for the tape, a machine sending its hands to the
/// authority — says the [WireHello] it was built with, and the machine it
/// asks says its own back. Each reads the other's as `PeerRoom` does: a
/// machine on another protocol major or another simulation is refused, its
/// `refusal` a sentence naming what to update, and nothing it sends is
/// acted on. A message from a machine that has said no hello is not acted
/// on either.
library;

import 'package:flutter3d_net/flutter3d_net.dart'
    show
        LoopbackParty,
        PeerMessage,
        PeerSend,
        PeerWire,
        RollbackSession,
        SettledStep,
        WireHello;

/// What the party's messages name under [PeerWire.engineKey].
const String _party = 'party';

/// The key a party message names its event under.
const String _event = 'event';

/// A settled step, for the spectators.
const String _tape = 'tape';

/// A spectator asking for the tape, with its hello.
const String _watching = 'watching';

/// The host's answer to a spectator it accepted: the state to start from,
/// with the host's hello.
const String _start = 'start';

/// The host's answer to a spectator it refused, with the host's hello.
const String _refused = 'refused';

/// A machine's hands, for the authority.
const String _inputs = 'inputs';

/// The authority's state, with its hello.
const String _snapshot = 'snapshot';

/// Whether [message] is the party's own, of [event].
bool _is(Map<String, Object?> message, String event) =>
    message[PeerWire.engineKey] == _party && message[_event] == event;

/// The hello [message] carries, read as `PeerRoom` reads one; a message
/// without one reads as a machine from before versions, protocol 0.0.
WireHello _helloIn(Map<String, Object?> message) =>
    WireHello.read(switch (message['hello']) {
      final Map<Object?, Object?> said => said.cast<String, Object?>(),
      _ => const <String, Object?>{},
    });

/// The party's settled steps, sent to whoever only watches — a spectator
/// played the tape rather than taking part in the rollback.
///
/// **From one machine, the [host]**, since every machine settles the same
/// steps the same way and one copy is enough; reliable, since a spectator
/// cannot ask a lost step again. A spectator who arrives late says so
/// ([PartyTapeWatcher] does), with its hello, and is sent the state of the
/// last settled step, then every step after it. One whose hello this host
/// cannot play with is told so and sent nothing; [refusals] says why.
final class PartyTape<S> {
  /// A tape on [wire], sent by the machine in slot [host], slot nought by
  /// default, with states written by [encode].
  PartyTape({
    required this.wire,
    required this.encode,
    this.host = 0,
    this.hello = WireHello.engineOnly,
  });

  /// The party's wire: settled steps go out on it, reliably, and the
  /// spectators' requests come in on it.
  final PeerWire wire;

  /// A state as something a wire carries.
  final Object? Function(S state) encode;

  /// Which slot does the sending.
  final int host;

  /// The versions this machine says to a spectator, which the spectator's
  /// own have to agree with.
  final WireHello hello;

  ({int step, S after})? _last;
  final Set<int> _watchers = <int>{};
  final Map<int, String> _refusals = <int, String>{};

  /// Why each spectator this host refused cannot watch, by slot: a
  /// sentence naming the version to update to.
  Map<int, String> get refusals => Map<int, String>.unmodifiable(_refusals);

  bool get _hosting => wire.slot == host;

  /// Hands a settled step on — wire this to [RollbackSession.onSettled].
  void settled(SettledStep<S> settled) {
    final SettledStep<S>(:step, :after, :frames) = settled;
    _last = (step: step, after: after);
    if (!_hosting || _watchers.isEmpty) return;
    wire.send(
      PeerSend(
        message: <String, Object?>{
          PeerWire.engineKey: _party,
          _event: _tape,
          'step': step,
          'frames': <String, Object?>{
            for (final MapEntry(:key, :value) in frames.entries) '$key': value,
          },
        },
      ),
    );
  }

  /// A message that is a spectator saying it is there — the rollback's
  /// own messages pass through untouched; call this for every one (wire it
  /// to [RollbackSession.onMessage]).
  void hear(PeerMessage heard) {
    final PeerMessage(:from, :message) = heard;
    if (!_hosting || !_is(message, _watching)) return;
    final reason = hello.refusal(_helloIn(message));
    if (reason != null) {
      _refusals[from] = reason;
      wire.send(
        PeerSend(
          message: <String, Object?>{
            PeerWire.engineKey: _party,
            _event: _refused,
            'to': from,
            'hello': hello.toJson(),
          },
        ),
      );
      return;
    }
    _watchers.add(from);
    final last = _last;
    if (last == null) return;
    wire.send(
      PeerSend(
        message: <String, Object?>{
          PeerWire.engineKey: _party,
          _event: _start,
          'to': from,
          'step': last.step + 1,
          'state': encode(last.after),
          'hello': hello.toJson(),
        },
      ),
    );
  }
}

/// A spectator: says it is watching, with its hello, takes the state it is
/// sent and the settled steps after it, and plays them in order at its own
/// pace. A host it cannot play with — another protocol major, another
/// simulation — is not watched: [refusal] says why.
final class PartyTapeWatcher<S> {
  /// A spectator on [wire], hearing the host from now on. It asks for
  /// nothing until [ask] is called.
  PartyTapeWatcher({
    required this.wire,
    required this.decode,
    required this.restore,
    required this.applyAndStep,
    this.hello = WireHello.engineOnly,
  }) {
    wire.listenFrom((heard) => hear(heard.from, heard.message));
  }

  /// The party's wire, which the spectator asks on and hears the tape
  /// from.
  final PeerWire wire;

  /// Reads a state the host sent, as the host's `PartyTape.encode` wrote
  /// it.
  final S Function(Object? encoded) decode;

  /// Puts the spectator's game in the state the host sent, once, before
  /// the first step is played.
  final void Function(S state) restore;

  /// Runs one settled step on its frames, keyed by slot: what [advance]
  /// calls for each step in order.
  final void Function(Map<int, Map<String, Object?>> frames) applyAndStep;

  /// The versions this machine says when it asks for the tape.
  final WireHello hello;

  final Map<int, Map<int, Map<String, Object?>>> _steps =
      <int, Map<int, Map<String, Object?>>>{};
  int? _next;
  int? _host;

  /// The next step it will play, or null before the state has come.
  int? get next => _next;

  /// Why the host cannot be watched, a sentence naming the version to
  /// update to; null while it can, or has not answered.
  String? get refusal => _refusal;
  String? _refusal;

  /// How many settled steps have come and not been played.
  int get waiting =>
      _next == null ? 0 : _steps.keys.where((s) => s >= _next!).length;

  /// Says it is here, so the host starts sending. Again until the state
  /// comes, since the host may not have heard it the first time; never
  /// once a host has been refused.
  void ask() {
    if (_next != null || _refusal != null) return;
    wire.send(
      PeerSend(
        message: <String, Object?>{
          PeerWire.engineKey: _party,
          _event: _watching,
          'hello': hello.toJson(),
        },
      ),
    );
  }

  /// Takes a message from slot [from]: the host's start or refusal, or a
  /// settled step. Messages that are not the party's, steps from a machine
  /// other than the one that started the tape, and everything after a
  /// refusal are ignored. The constructor wires this to [wire].
  void hear(int from, Map<String, Object?> message) {
    if (message[PeerWire.engineKey] != _party || _refusal != null) return;
    final to = message['to'];
    if (to is int && to != wire.slot) return;
    switch (message[_event]) {
      case _refused:
        _refusal =
            hello.refusal(_helloIn(message)) ??
            'the host turned this machine away';
      case _start when _next == null:
        final reason = hello.refusal(_helloIn(message));
        if (reason != null) {
          _refusal = reason;
          return;
        }
        final step = message['step'];
        if (step is! int) return;
        restore(decode(message['state']));
        _host = from;
        _next = step;
      // Only from the host whose hello started the tape.
      case _tape when from == _host:
        final step = message['step'];
        final frames = message['frames'];
        if (step is! int || frames is! Map) return;
        _steps[step] = <int, Map<String, Object?>>{
          for (final MapEntry(:key, :value) in frames.entries)
            int.parse('$key'): (value as Map).cast<String, Object?>(),
        };
      default:
        break;
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
///
/// **Only the hands of a machine whose hello it accepted.** A
/// [PredictingClient] says its hello with its hands until the authority
/// has run one of them; hands from a machine that said none, or one this
/// authority cannot play with, are never run, and [refusals] says why for
/// the second. The state goes out with the authority's own hello, so each
/// client judges it the same way.
final class AuthorityServer<S> {
  /// An authority on [wire] for [players] slots, hearing clients' hands
  /// from now on and sending its state every [snapshotEvery] steps.
  AuthorityServer({
    required this.wire,
    required this.players,
    required this.applyAndStep,
    required this.save,
    required this.encode,
    this.snapshotEvery = 3,
    this.hello = WireHello.engineOnly,
  }) {
    wire.listenFrom((heard) => receive(heard.from, heard.message));
  }

  /// The party's wire: hands come in on it, and the state goes out on it
  /// unreliably.
  final PeerWire wire;

  /// How many slots the party has, a count including the authority's own,
  /// which sends no hands and is left out of the frames.
  final int players;

  /// Runs one step of the game on every other slot's frame, keyed by slot;
  /// a slot whose next hand has not come gets its last one again, or an
  /// empty frame before its first.
  final void Function(Map<int, Map<String, Object?>> frames) applyAndStep;

  /// Takes the game's state as it stands, for a snapshot.
  final S Function() save;

  /// Writes a state as something the wire carries.
  final Object? Function(S state) encode;

  /// How many steps pass between snapshots, a count; three by default.
  final int snapshotEvery;

  /// The versions this machine runs the party on, which every client's
  /// have to agree with.
  final WireHello hello;

  int _step = 0;

  /// How many steps [advance] has run, a count from nought.
  int get step => _step;

  final Map<int, Map<int, Map<String, Object?>>> _queued =
      <int, Map<int, Map<String, Object?>>>{};
  final Map<int, int> _ran = <int, int>{};
  final Map<int, Map<String, Object?>> _held = <int, Map<String, Object?>>{};
  final Set<int> _met = <int>{};
  final Map<int, String> _refusals = <int, String>{};

  /// Why each machine this authority refused cannot play, by slot: a
  /// sentence naming the version to update to.
  Map<int, String> get refusals => Map<int, String>.unmodifiable(_refusals);

  /// Takes a client's hands from slot [from] and queues the ones not yet
  /// run. The first must carry a hello this authority accepts: without one
  /// it is dropped, and with one it refuses it lands in [refusals]. The
  /// constructor wires this to [wire].
  void receive(int from, Map<String, Object?> message) {
    if (!_is(message, _inputs)) return;
    if (!_met.contains(from)) {
      // No hello yet: nothing to judge it by, so nothing is run.
      if (message['hello'] is! Map) return;
      final reason = hello.refusal(_helloIn(message));
      if (reason != null) {
        _refusals[from] = reason;
        return;
      }
      _refusals.remove(from);
      _met.add(from);
    }
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
      wire.send(
        PeerSend(
          message: <String, Object?>{
            PeerWire.engineKey: _party,
            _event: _snapshot,
            'step': _step,
            'state': encode(save()),
            'ran': <String, Object?>{
              for (final MapEntry(:key, :value) in _ran.entries) '$key': value,
            },
            'hello': hello.toJson(),
          },
          reliable: false,
        ),
      );
    }
  }
}

/// A machine under an [AuthorityServer]: sends its hands, numbered, and
/// runs them at once on its own copy so the player sees them now; when the
/// authority's state arrives, takes it, and runs again on top of it the
/// hands the authority had not got to yet.
///
/// Its hands carry its hello until the authority has run one of them. An
/// authority it cannot play with is not followed: [refusal] says why, and
/// its states are not taken.
final class PredictingClient<S> {
  /// A client on [wire], hearing the authority's states from now on and
  /// sending each hand along with the [redundancy] before it.
  PredictingClient({
    required this.wire,
    required this.captureLocalFrame,
    required this.predict,
    required this.restore,
    required this.decode,
    this.redundancy = 8,
    this.hello = WireHello.engineOnly,
  }) {
    wire.listenFrom((heard) => receive(heard.from, heard.message));
  }

  /// The party's wire: hands go out on it unreliably, and the authority's
  /// states come in on it.
  final PeerWire wire;

  /// Reads this machine's hands for the step: what [advance] sends and
  /// predicts with.
  final Map<String, Object?> Function() captureLocalFrame;

  /// Runs one step of this machine's copy on its own [frame] alone — the
  /// others as the last state the authority sent left them.
  final void Function(Map<String, Object?> frame) predict;

  /// Puts this machine's copy in a state the authority sent, before the
  /// hands it has not run are predicted again on top.
  final void Function(S state) restore;

  /// Reads a state the authority sent, as its `AuthorityServer.encode`
  /// wrote it.
  final S Function(Object? encoded) decode;

  /// How many of the latest unacknowledged hands each message carries, a
  /// count; eight by default, so a lost message is made up by the next.
  final int redundancy;

  /// The versions this machine says to the authority.
  final WireHello hello;

  int _sequence = -1;
  int _lastSnapshot = -1;
  bool _acknowledged = false;
  final Map<int, Map<String, Object?>> _unacknowledged =
      <int, Map<String, Object?>>{};

  /// Hands sent and not yet run by the authority — what a game shows as
  /// how far behind the authority this machine is running, and what a test
  /// of the connection reads.
  int get unacknowledged => _unacknowledged.length;

  /// Why the authority cannot be followed, a sentence naming the version
  /// to update to; null while it can, or has not been heard.
  String? get refusal => _refusal;
  String? _refusal;

  /// How many steps were run again on top of a state from the authority.
  int replayed = 0;

  /// One step of this machine: reads its hands, sends them numbered with
  /// the unacknowledged ones before them, and predicts the step at once.
  void advance() {
    final frame = captureLocalFrame();
    _unacknowledged[++_sequence] = frame;
    wire.send(
      PeerSend(
        message: <String, Object?>{
          PeerWire.engineKey: _party,
          _event: _inputs,
          'inputs': <String, Object?>{
            for (final s in _unacknowledged.keys.where(
              (s) => s > _sequence - redundancy,
            ))
              '$s': _unacknowledged[s],
          },
          // Said again with every hand until one has been run, since the
          // hands are unreliable and the first may be lost.
          if (!_acknowledged) 'hello': hello.toJson(),
        },
        reliable: false,
      ),
    );
    predict(frame);
  }

  /// Takes the authority's state from slot [from]: restores it, drops the
  /// hands it says it ran and predicts the rest again. A state older than
  /// the last one taken is ignored; one whose hello this machine refuses
  /// sets [refusal], and nothing is taken after that. The constructor
  /// wires this to [wire].
  void receive(int from, Map<String, Object?> message) {
    if (!_is(message, _snapshot) || _refusal != null) return;
    final reason = hello.refusal(_helloIn(message));
    if (reason != null) {
      _refusal = reason;
      return;
    }
    final at = message['step'];
    if (at is! int || at <= _lastSnapshot) return;
    _lastSnapshot = at;
    final ran = (message['ran'] as Map?)?['${wire.slot}'];
    restore(decode(message['state']));
    if (ran is int) {
      _acknowledged = true;
      _unacknowledged.removeWhere((s, _) => s <= ran);
    }
    for (final s in _unacknowledged.keys.toList()..sort()) {
      predict(_unacknowledged[s]!);
      replayed++;
    }
  }
}
