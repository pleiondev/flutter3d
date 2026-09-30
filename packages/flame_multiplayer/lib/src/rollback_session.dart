/// Rollback between two machines: input frames per step, a delay, a guess of
/// the far side's hands, and a rollback when the guess was wrong.
library;

import 'peer_wire.dart';

/// One step this session already ran, kept so a truer remote frame can be
/// put in its place and the step run again.
final class _Ran<S> {
  const _Ran({
    required this.before,
    required this.local,
    required this.remote,
    required this.predicted,
  });

  /// The state the moment before this step ran: what a correction restores.
  final S before;

  /// This side's own hands that step. Never revised: a correction is always
  /// about what the other side did.
  final Map<String, Object?> local;

  /// What the other side's hands were taken to be: the frame that had
  /// arrived by then, or a repeat of the last one that had.
  final Map<String, Object?> remote;

  final bool predicted;

  _Ran<S> copyWith({
    S? before,
    Map<String, Object?>? remote,
    bool? predicted,
  }) => _Ran<S>(
    before: before ?? this.before,
    local: local,
    remote: remote ?? this.remote,
    predicted: predicted ?? this.predicted,
  );
}

/// A fixed-step game kept in step on two machines over a [PeerWire], each
/// sending its own player's hands.
///
/// **It does not know the game.** [captureLocalFrame] reads this machine's
/// hands out of whatever input the game has; [applyAndStep] writes both
/// back and runs one step; [save] and [restore] take the whole game to a
/// state of type [S] and back — a map, a snapshot, a copy of a struct.
///
/// ## Input delay
///
/// Hands captured on [advance] are not applied here until [inputDelay] steps
/// later, which gives them that long, and the wire's time, to reach the
/// other machine before it needs them. High enough for the connection and a
/// correction rarely reaches far back; nought and every unconfirmed step
/// runs on a guess.
///
/// ## The guess, and the rollback
///
/// A step whose remote frame has not arrived runs on the last one that did.
/// When the true one comes, it either matches the guess and nothing is done,
/// or it does not: [restore] puts the game back to the moment before that
/// step, and [applyAndStep] runs it and every step since again with the
/// true hands in place.
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
/// one of the next few arrives. A wire that loses nothing just carries a few
/// numbers twice.
final class RollbackSession<S> {
  RollbackSession({
    required this.wire,
    required this.captureLocalFrame,
    required this.applyAndStep,
    required this.save,
    required this.restore,
    this.inputDelay = 2,
    this.maxRollbackFrames = 8,
    this.redundancy = 8,
    this.onSettled,
  }) : assert(inputDelay >= 0, 'a negative delay would apply input early'),
       assert(maxRollbackFrames > 0, 'a window of nought corrects nothing'),
       assert(redundancy >= 0, 'a negative redundancy resends nothing') {
    wire.listen(receive);
  }

  final PeerWire wire;

  /// This machine's hands for the step about to be captured.
  final Map<String, Object?> Function() captureLocalFrame;

  /// Writes [local] and [remote] into the game and runs one fixed step;
  /// called again for a step being corrected.
  final void Function(Map<String, Object?> local, Map<String, Object?> remote)
  applyAndStep;

  final S Function() save;
  final void Function(S state) restore;

  final int inputDelay;
  final int maxRollbackFrames;
  final int redundancy;

  /// Told of a step as it leaves the window — the first moment no later
  /// correction can touch it — with the state it ended in. Two machines'
  /// settled steps are what to compare them by; a step just run may still
  /// rest on a guess.
  final void Function(int step, S after)? onSettled;

  int _step = 0;

  /// The step about to run.
  int get step => _step;

  /// Frames that came too late to correct anything.
  int droppedCorrections = 0;

  final Map<int, Map<String, Object?>> _pendingLocal =
      <int, Map<String, Object?>>{};
  final Map<int, Map<String, Object?>> _recentSent =
      <int, Map<String, Object?>>{};
  final Map<int, Map<String, Object?>> _earlyRemote =
      <int, Map<String, Object?>>{};
  final Map<int, _Ran<S>> _history = <int, _Ran<S>>{};

  Map<String, Object?> _lastConfirmedRemote = const <String, Object?>{};

  /// Captures this machine's hands, sends them, and runs one step. Once a
  /// fixed step.
  void advance() {
    final captured = captureLocalFrame();
    final appliesAt = _step + inputDelay;
    _pendingLocal[appliesAt] = captured;

    _recentSent[appliesAt] = captured;
    _recentSent.removeWhere((s, _) => s < appliesAt - redundancy);
    wire.send(<String, Object?>{
      'frames': <String, Object?>{
        for (final MapEntry(:key, :value) in _recentSent.entries) '$key': value,
      },
    }, reliable: false);

    final local = _pendingLocal.remove(_step) ?? const <String, Object?>{};
    final early = _earlyRemote.remove(_step);
    final remote = early ?? _lastConfirmedRemote;
    if (early != null) _lastConfirmedRemote = early;

    _history[_step] = _Ran<S>(
      before: save(),
      local: local,
      remote: remote,
      predicted: early == null,
    );
    _forgetOutsideWindow();

    applyAndStep(local, remote);
    _step++;
  }

  /// A message from the other machine: frames, each named by its step,
  /// some of them repeats of ones already had.
  void receive(Map<String, Object?> message) {
    final frames = message['frames'];
    if (frames is! Map) return;
    for (final MapEntry(:key, :value) in frames.entries) {
      final at = int.tryParse('$key');
      if (at == null || value is! Map) continue;
      _receiveOne(at, value.cast<String, Object?>());
    }
  }

  void _receiveOne(int atStep, Map<String, Object?> frame) {
    if (atStep >= _step) {
      // Not run yet: [advance] finds it waiting.
      _earlyRemote[atStep] = frame;
      return;
    }

    final ran = _history[atStep];
    if (ran == null) {
      droppedCorrections++;
      return;
    }
    _lastConfirmedRemote = frame;
    if (!ran.predicted || _sameFrame(ran.remote, frame)) {
      _history[atStep] = ran.copyWith(remote: frame, predicted: false);
      return;
    }

    // Guessed wrong: back to the moment before, and every step since again.
    // Each keeps its own hands, and whatever remote frame it had on record
    // but this one — a step still on its own guess corrects on its own
    // frame, as this one just did.
    restore(ran.before);
    for (var s = atStep; s < _step; s++) {
      final h = _history[s]!;
      final remoteForStep = s == atStep ? frame : h.remote;
      final before = save();
      applyAndStep(h.local, remoteForStep);
      _history[s] = h.copyWith(
        before: before,
        remote: remoteForStep,
        predicted: s == atStep ? false : h.predicted,
      );
    }
  }

  void _forgetOutsideWindow() {
    final horizon = _step - maxRollbackFrames;
    final settled = onSettled;
    if (settled != null) {
      // The state a step leaving ended in is the one the next began in.
      for (final s
          in _history.keys.where((s) => s < horizon).toList()..sort()) {
        final next = _history[s + 1];
        if (next != null) settled(s, next.before);
      }
    }
    _history.removeWhere((s, _) => s < horizon);
  }

  static bool _sameFrame(Map<String, Object?> a, Map<String, Object?> b) {
    if (a.length != b.length) return false;
    for (final MapEntry(:key, :value) in a.entries) {
      if (!b.containsKey(key) || b[key] != value) return false;
    }
    return true;
  }
}
