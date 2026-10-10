/// Rollback for two machines or a party of them: input frames per step, a
/// delay, a guess of the others' hands, and a rollback when a guess was
/// wrong.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show Registration;

import 'peer_wire.dart';

/// What one step ran on: the state before it, every slot's frame, and which
/// of them were guesses.
final class _Ran<S> {
  const _Ran(this.before, this.frames, this.guessed);

  final S before;
  final Map<int, Map<String, Object?>> frames;
  final Set<int> guessed;
}

/// A fixed-step game kept in step on [players] machines over a [PeerWire],
/// each sending its own player's hands: **the one rollback**, for two
/// machines and for a party alike.
///
/// **It does not know the game.** [captureLocalFrame] reads this machine's
/// hands out of whatever input the game has; [applyAndStep] writes every
/// slot's hands back — by slot, the same slot the same player on every
/// machine — and runs one step; [save] and [restore] take the whole game to
/// a state of type [S] and back: a map, a snapshot, an `EngineLoop`'s
/// capture ([EngineRollback] hands it one).
///
/// ## Input delay
///
/// Hands captured on [advance] are not applied here until [inputDelay] steps
/// later, which gives them that long, and the wire's time, to reach the
/// other machines before they need them. High enough for the connection and
/// a correction rarely reaches far back; nought and every unconfirmed step
/// runs on a guess.
///
/// ## The guess, and the rollback
///
/// A step whose frame from a slot has not arrived runs on the last one that
/// did. When the true one comes, it either matches the guess and nothing is
/// done, or it does not: [restore] puts the game back to the moment before
/// that step, and [applyAndStep] runs it and every step since again — each
/// on what it had on record, that one on the frame that came. A wrong guess
/// about one machine rolls back to the step it was made on; a later guess
/// about another stays a guess until its own frame comes. [isResimulating] is
/// true while steps run again.
///
/// ## The window
///
/// Only the last [maxRollbackFrames] steps keep the state a correction
/// needs. A frame for a step older than that is too late to use, and
/// [droppedCorrections] counts it rather than pretend the guess was right;
/// the answer to seeing it move is a longer delay or a longer window.
///
/// ## Redundancy
///
/// Frames go as unreliable messages, each carrying the last [redundancy]
/// steps' frames as well as its own, so a lost one costs nothing as long as
/// one of the next few arrives.
///
/// ## Its messages and the game's
///
/// A rollback's message is the engine's: `{"f3d": "rollback", "frames":
/// …}`, under the wire's reserved [PeerWire.engineKey]. Only those are taken
/// as frames, so a game's own message on the same wire — a spectator's
/// tape, a chat line that happens to have a `frames` field — is never
/// mistaken for one. The session is one listener of the wire among any
/// others; [dispose] takes it away.
///
/// ## An ending all agree on
///
/// A step that has run may still rest on a guess and be taken back; a game
/// over on a guess is a game over one machine then takes back. [endsAt]
/// names what an ending looks like in a settled state, and [agreedEnd] is
/// the first settled step that shows one, with the state it left — the same
/// step on every machine. **Keep advancing after the end** for a while: the
/// others may still be waiting for this one's last frames.
final class RollbackSession<S> {
  RollbackSession({
    required this.wire,
    required this.captureLocalFrame,
    required this.applyAndStep,
    required this.save,
    required this.restore,
    int? localSlot,
    this.players = 2,
    this.inputDelay = 2,
    this.maxRollbackFrames = 8,
    this.redundancy = 8,
    this.maxStepsAhead = 600,
    this.endsAt,
    this.onSettled,
    this.onMessage,
  }) : localSlot = localSlot ?? wire.slot,
       assert(players >= 2 && players <= 32, 'two to thirty-two machines'),
       assert(inputDelay >= 0, 'a negative delay would apply input early'),
       assert(maxRollbackFrames > 0, 'a window of nought corrects nothing'),
       assert(redundancy >= 0, 'a negative redundancy resends nothing'),
       assert(maxStepsAhead > 0, 'a peer is always a little ahead') {
    assert(
      this.localSlot >= 0 && this.localSlot < players,
      'this machine\'s slot is one of the $players',
    );
    _hearing = wire.listenFrom(receive);
  }

  /// What a rollback's message names under [PeerWire.engineKey].
  static const String messageKind = 'rollback';

  late final Registration _hearing;

  final PeerWire wire;

  /// Which player this machine drives: the wire's [PeerWire.slot] unless
  /// told otherwise — a room hands it out.
  final int localSlot;

  /// How many slots the game has, this machine's among them.
  final int players;

  /// This machine's hands for the step about to be captured. What goes in
  /// is compared by equality and applied on every machine, so it wants whole
  /// numbers rather than doubles read off a stick.
  final Map<String, Object?> Function() captureLocalFrame;

  /// Writes every slot's frame into the game and runs one fixed step;
  /// called again for a step being corrected. An empty frame is a player not
  /// heard from yet.
  final void Function(Map<int, Map<String, Object?>> frames) applyAndStep;

  final S Function() save;
  final void Function(S state) restore;

  final int inputDelay;
  final int maxRollbackFrames;
  final int redundancy;

  /// How far past the step about to run a peer's frame is kept for later:
  /// ten seconds at sixty steps by default. A frame further ahead is
  /// dropped and counted in [droppedEarly] — a peer that far ahead is not
  /// one this machine will catch up with, and a peer that says so on
  /// purpose would otherwise have this one keep every step number it names.
  final int maxStepsAhead;

  /// Whether a settled state is an ending; null for a game with none.
  final bool Function(S after)? endsAt;

  /// Told of a step as it leaves the window — the first moment no later
  /// correction can touch it — with the state it ended in and the frames it
  /// ran on: what machines are compared by, and what a spectator is fed
  /// (see `flame_multiplayer`'s `PartyTape`).
  final void Function(int step, S after, Map<int, Map<String, Object?>> frames)?
  onSettled;

  /// Told of every message on the wire that is not a rollback's frames — a
  /// spectator saying it is there, a game's own. A convenience: the game may
  /// as well listen to the wire itself, which hears every message too.
  final void Function(int from, Map<String, Object?> message)? onMessage;

  /// Stops hearing the wire. The session sends nothing more once nobody
  /// calls [advance]; the wire stays open for whoever else listens.
  void dispose() => _hearing.cancel();

  int _step = 0;

  /// The step about to run.
  int get step => _step;

  /// Frames that came too late to correct anything.
  int droppedCorrections = 0;

  /// Frames that came for a step more than [maxStepsAhead] ahead.
  int droppedEarly = 0;

  /// How many steps were run again, over every correction.
  int stepsRerun = 0;

  /// Whether the steps running now are being run again after a correction.
  bool get isResimulating => _resimulating;
  bool _resimulating = false;

  /// Whether every other machine's hands have arrived at least once.
  bool get isConnected => _lastConfirmed.length >= players - 1;

  /// The first settled ending and the step it came on; null until there is
  /// one.
  ({int step, S after})? get agreedEnd => _agreedEnd;
  ({int step, S after})? _agreedEnd;

  final Map<int, Map<String, Object?>> _pendingLocal =
      <int, Map<String, Object?>>{};
  final Map<int, Map<String, Object?>> _recentSent =
      <int, Map<String, Object?>>{};
  final Map<int, Map<int, Map<String, Object?>>> _early =
      <int, Map<int, Map<String, Object?>>>{};
  final Map<int, ({int step, Map<String, Object?> frame})> _lastConfirmed =
      <int, ({int step, Map<String, Object?> frame})>{};
  final Map<int, _Ran<S>> _history = <int, _Ran<S>>{};

  /// Captures this machine's hands, sends them, and runs one step. Once a
  /// fixed step.
  void advance() {
    final appliesAt = _step + inputDelay;
    final captured = captureLocalFrame();
    _pendingLocal[appliesAt] = captured;
    _recentSent[appliesAt] = captured;
    _recentSent.removeWhere((s, _) => s < appliesAt - redundancy);
    wire.send(<String, Object?>{
      PeerWire.engineKey: messageKind,
      'frames': <String, Object?>{
        for (final MapEntry(:key, :value) in _recentSent.entries) '$key': value,
      },
    }, reliable: false);

    final frames = <int, Map<String, Object?>>{};
    final guessed = <int>{};
    for (var slot = 0; slot < players; slot++) {
      if (slot == localSlot) {
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
    _history[_step] = _Ran<S>(save(), frames, guessed);
    _forgetOutsideWindow();
    applyAndStep(frames);
    _step++;
  }

  /// A message from machine [from]: a rollback's frames, each named by its
  /// step, some of them repeats of ones already had — or a message that is
  /// not the rollback's, handed to [onMessage].
  void receive(int from, Map<String, Object?> message) {
    // A wire between two machines names the sender as the other of its own
    // slot, and a room's transport does not know which slot the room gave
    // this machine (a WebSocket to `/room/<code>` is slot nought on both
    // ends). So a session told another slot than its wire's hears the
    // sender as the other of its own: otherwise the joining machine, told
    // slot one, takes every frame from slot nought for its own and drops it.
    final sender = players == 2 && localSlot != wire.slot ? 1 - from : from;
    if (message[PeerWire.engineKey] != messageKind) {
      onMessage?.call(sender, message);
      return;
    }
    final frames = message['frames'];
    if (frames is! Map ||
        sender == localSlot ||
        sender < 0 ||
        sender >= players) {
      return;
    }
    final steps = <int, Map<String, Object?>>{
      for (final MapEntry(:key, :value) in frames.entries)
        if ((int.tryParse('$key'), value) case (final int at, final Map frame))
          at: frame.cast<String, Object?>(),
    };
    for (final at in steps.keys.toList()..sort()) {
      _receiveOne(sender, at, steps[at]!);
    }
  }

  void _confirm(int slot, int at, Map<String, Object?> frame) {
    final last = _lastConfirmed[slot];
    if (last == null || at >= last.step) {
      _lastConfirmed[slot] = (step: at, frame: frame);
    }
  }

  void _receiveOne(int from, int at, Map<String, Object?> frame) {
    if (at >= _step + maxStepsAhead) {
      droppedEarly++;
      return;
    }
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
      _history[at] = _Ran<S>(ran.before, frames, guessed);
      return;
    }
    // Guessed wrong: back to before that step, and every step since again —
    // each on what it had on record, this one on the frame that came.
    restore(ran.before);
    _resimulating = true;
    try {
      for (var s = at; s < _step; s++) {
        final h = s == at ? _Ran<S>(ran.before, frames, guessed) : _history[s]!;
        final before = save();
        applyAndStep(h.frames);
        _history[s] = _Ran<S>(before, h.frames, h.guessed);
        stepsRerun++;
      }
    } finally {
      _resimulating = false;
    }
  }

  void _forgetOutsideWindow() {
    final horizon = _step - maxRollbackFrames;
    final leaving = _history.keys.where((s) => s < horizon).toList()..sort();
    for (final s in leaving) {
      // The state a step leaving ended in is the one the next began in.
      final next = _history[s + 1];
      if (next == null) continue;
      onSettled?.call(s, next.before, _history[s]!.frames);
      final ends = endsAt;
      if (_agreedEnd == null && ends != null && ends(next.before)) {
        _agreedEnd = (step: s, after: next.before);
      }
    }
    _history.removeWhere((s, _) => s < horizon);
  }

  static bool _same(Map<String, Object?> a, Map<String, Object?> b) =>
      a.length == b.length &&
      a.entries.every((e) => b.containsKey(e.key) && b[e.key] == e.value);
}
