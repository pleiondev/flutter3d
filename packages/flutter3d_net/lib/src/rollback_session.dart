/// Rollback for two machines or a party of them: input frames per step, a
/// delay, a guess of the others' hands, and a rollback when a guess was
/// wrong.
library;

import 'dart:typed_data';

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show Registration;
import 'package:flutter3d_sim/flutter3d_sim.dart' show firstDifferingPath;

import 'peer_wire.dart';
import 'rollback_clock.dart';

/// What one step ran on: the state before it, every slot's frame, and which
/// of them were guesses.
final class _Ran<S> {
  const _Ran(this.before, this.frames, this.guessed);

  final S before;
  final Map<int, Map<String, Object?>> frames;
  final Set<int> guessed;
}

/// The first settled step a [RollbackSession] found an ending in, and the
/// state it left: what [RollbackSession.agreedEnd] answers, the same on
/// every machine.
final class AgreedEnding<S> {
  const AgreedEnding({required this.step, required this.after});

  /// The step the ending came on, in the session's own counting.
  final int step;

  /// The state that step left.
  final S after;

  /// Two endings are the same when their steps are and their states compare
  /// equal value by value, so a JSON-shaped state settled on two machines is
  /// the same ending.
  @override
  bool operator ==(Object other) =>
      other is AgreedEnding<S> &&
      other.step == step &&
      firstDifferingPath(other.after, after) == null;

  @override
  int get hashCode => Object.hash(step, switch (after) {
    final Map<Object?, Object?> map => map.length,
    final List<Object?> list => list.length,
    final value => value.hashCode,
  });

  @override
  String toString() => 'AgreedEnding(step $step)';
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
/// needs. A step that leaves the window still running on a guess about a
/// slot is counted in [RollbackStats.settledOnGuess]; when that slot's frame
/// comes later and says something else than the guess, it is too late to
/// use, and [droppedCorrections] counts it rather than pretend the guess was
/// right. The answer to seeing it move is a longer delay or a longer window.
/// A late copy of a frame already had, which [redundancy] sends on purpose,
/// is not a correction and is not counted.
///
/// ## What it costs
///
/// [stats] reads the counters at once, with the time each step run again
/// took (its median, its 99th percentile and its worst), read off [elapsed]:
/// a game that rolls back eight steps on a frame spends eight of these in
/// that frame.
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
    Duration Function()? elapsed,
  }) : localSlot = localSlot ?? wire.slot,
       elapsed = elapsed ?? rollbackClock,
       assert(players >= 2 && players <= 32, 'two to thirty-two machines'),
       assert(inputDelay >= 0, 'a negative delay would apply input early'),
       assert(maxRollbackFrames > 0, 'a window of nought corrects nothing'),
       assert(redundancy >= 0, 'a negative redundancy resends nothing'),
       assert(maxStepsAhead > 0, 'a peer is always a little ahead') {
    assert(
      this.localSlot >= 0 && this.localSlot < players,
      'this machine\'s slot is one of the $players',
    );
    _hearing = wire.listenFrom((heard) => receive(heard.from, heard.message));
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
  /// called again for a step being corrected. Handed a [RollbackStep]: the
  /// step's number, every slot's frame by slot (an empty frame is a player
  /// not heard from yet), each slot's [InputStatus] — heard, guessed, or
  /// behind a closed wire — and whether the step is being run again, so a
  /// game can freeze a player who left, hold back the sound of a predicted
  /// hit, and show who it is waiting for.
  final void Function(RollbackStep step) applyAndStep;

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
  final void Function(SettledStep<S> settled)? onSettled;

  /// Told of every message on the wire that is not a rollback's frames — a
  /// spectator saying it is there, a game's own. A convenience: the game may
  /// as well listen to the wire itself, which hears every message too.
  final void Function(PeerMessage message)? onMessage;

  /// The clock [stats] times a step run again by: a monotonic stopwatch
  /// started with the first session unless the session is handed another,
  /// as a test hands one that moves by known amounts.
  final Duration Function() elapsed;

  /// Stops hearing the wire. The session sends nothing more once nobody
  /// calls [advance]; the wire stays open for whoever else listens.
  void dispose() => _hearing.cancel();

  int _step = 0;

  /// The step about to run.
  int get step => _step;

  /// Frames that came after their step left the window and said something
  /// else than the guess it settled on: corrections too late to make.
  int droppedCorrections = 0;

  /// Frames that came for a step more than [maxStepsAhead] ahead.
  int droppedEarly = 0;

  /// How many steps were run again, over every correction.
  int stepsRerun = 0;

  /// Whether the steps running now are being run again after a correction.
  bool get isResimulating => _resimulating;
  bool _resimulating = false;

  int _rollbacks = 0;
  int _settledOnGuess = 0;
  final _ResimulationTimes _times = _ResimulationTimes();

  /// The guesses steps left the window on, by slot and then by step, kept
  /// so a frame that comes later is held to what was guessed; forgotten
  /// [maxStepsAhead] steps on, when no peer still sends them.
  final Map<int, Map<int, Map<String, Object?>>> _settledGuesses =
      <int, Map<int, Map<String, Object?>>>{};

  /// The counters and the time steps run again took, read now.
  RollbackStats get stats => RollbackStats(
    steps: _step,
    rollbacks: _rollbacks,
    stepsRerun: stepsRerun,
    settledOnGuess: _settledOnGuess,
    droppedCorrections: droppedCorrections,
    droppedEarly: droppedEarly,
    resimulationP50: _times.percentile(50),
    resimulationP99: _times.percentile(99),
    resimulationMax: _times.max,
  );

  /// Whether every other machine's hands have arrived at least once.
  bool get isConnected => _lastConfirmed.length >= players - 1;

  /// The first settled ending and the step it came on; null until there is
  /// one.
  AgreedEnding<S>? get agreedEnd => _agreedEnd;
  AgreedEnding<S>? _agreedEnd;

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
    wire.send(
      PeerSend(
        message: <String, Object?>{
          PeerWire.engineKey: messageKind,
          'frames': <String, Object?>{
            for (final MapEntry(:key, :value) in _recentSent.entries)
              '$key': value,
          },
        },
        reliable: false,
      ),
    );

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
    applyAndStep(_stepOf(_step, frames, guessed, resimulated: false));
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
      onMessage?.call(PeerMessage(from: sender, message: message));
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

  /// What [applyAndStep] is handed for step [at]: a slot still on a guess
  /// is predicted, or disconnected once the wire to it is closed.
  RollbackStep _stepOf(
    int at,
    Map<int, Map<String, Object?>> frames,
    Set<int> guessed, {
    required bool resimulated,
  }) {
    final gone = wire.state == WireState.closed;
    return RollbackStep(
      step: at,
      frames: frames,
      predicted: gone ? const <int>{} : guessed,
      disconnected: gone ? guessed : const <int>{},
      resimulated: resimulated,
    );
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
      // Past the window. Only a frame the step settled on a guess for, and
      // a different one, is a correction lost; a repeat of a frame already
      // had, or one the guess got right, changes nothing. Either way it is
      // the latest word from that slot, which the next guess is made of.
      _confirm(from, at, frame);
      final guess = _settledGuesses[from]?.remove(at);
      if (guess != null && !_same(guess, frame)) droppedCorrections++;
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
    // Each step run again is timed from the end of the one before, so the
    // restore counts against the first of them: what the frame pays.
    var start = elapsed();
    restore(ran.before);
    _resimulating = true;
    _rollbacks++;
    try {
      for (var s = at; s < _step; s++) {
        final h = s == at ? _Ran<S>(ran.before, frames, guessed) : _history[s]!;
        final before = save();
        applyAndStep(_stepOf(s, h.frames, h.guessed, resimulated: true));
        _history[s] = _Ran<S>(before, h.frames, h.guessed);
        stepsRerun++;
        final to = elapsed();
        _times.add(to - start);
        start = to;
      }
    } finally {
      _resimulating = false;
    }
  }

  void _forgetOutsideWindow() {
    final horizon = _step - maxRollbackFrames;
    final leaving = _history.keys.where((s) => s < horizon).toList()..sort();
    for (final s in leaving) {
      for (final slot in _history[s]!.guessed) {
        _settledOnGuess++;
        (_settledGuesses[slot] ??= <int, Map<String, Object?>>{})[s] =
            _history[s]!.frames[slot]!;
      }
      // The state a step leaving ended in is the one the next began in.
      final next = _history[s + 1];
      if (next == null) continue;
      onSettled?.call(
        SettledStep<S>(
          step: s,
          after: next.before,
          frames: _history[s]!.frames,
        ),
      );
      final ends = endsAt;
      if (_agreedEnd == null && ends != null && ends(next.before)) {
        _agreedEnd = AgreedEnding<S>(step: s, after: next.before);
      }
    }
    _history.removeWhere((s, _) => s < horizon);
    final forgotten = _step - maxStepsAhead;
    for (final guesses in _settledGuesses.values) {
      guesses.removeWhere((s, _) => s < forgotten);
    }
  }

  static bool _same(Map<String, Object?> a, Map<String, Object?> b) =>
      a.length == b.length &&
      a.entries.every((e) => b.containsKey(e.key) && b[e.key] == e.value);
}

/// Where a slot's frame for a step came from: heard from its machine,
/// guessed from the last one heard, or from a machine gone.
///
/// **An open class with constants, not an enum**: a later minor may add a
/// status (a spectator's seat, a frame replayed from a tape), and a
/// `switch` written against three would stop compiling. A `switch` over
/// this ends with a default.
final class InputStatus {
  const InputStatus._(this.name);

  /// Heard from the machine that drives the slot, or this machine's own:
  /// the step will not be run again for this slot.
  static const InputStatus confirmed = InputStatus._('confirmed');

  /// Not heard yet: the slot's last heard frame, repeated. The step may be
  /// run again when the true one comes, so what it starts (a sound, a hit
  /// marker) may be taken back.
  static const InputStatus predicted = InputStatus._('predicted');

  /// From a machine whose wire is closed: the last heard frame, repeated
  /// with nobody left to correct it. A game freezes or hands over that
  /// player rather than let them run on.
  static const InputStatus disconnected = InputStatus._('disconnected');

  /// Every status this build knows.
  static const List<InputStatus> values = <InputStatus>[
    confirmed,
    predicted,
    disconnected,
  ];

  /// The status written as [name]; null for a word this build does not
  /// know.
  static InputStatus? byName(String name) {
    for (final status in values) {
      if (status.name == name) return status;
    }
    return null;
  }

  /// Its word in a report or a message.
  final String name;

  @override
  String toString() => 'InputStatus.$name';
}

/// What [RollbackSession.applyAndStep] is handed for one step: its number,
/// every slot's frame, where each came from, and whether it is a step run
/// again.
///
/// **One object, so a minor can say more** (the step's input delay, a
/// desync it was checked against) without breaking a step function written
/// against 1.0.
final class RollbackStep {
  /// Step [step], run on [frames]; the slots in [predicted] on a guess,
  /// those in [disconnected] behind a closed wire, the rest heard.
  const RollbackStep({
    required this.step,
    required this.frames,
    this._predicted = const <int>{},
    this._disconnected = const <int>{},
    required this.resimulated,
  });

  /// The step's number, the same on every machine.
  final int step;

  /// Every slot's frame the step runs on, by slot: the same slot the same
  /// player on every machine. An empty frame is a player not heard from yet.
  final Map<int, Map<String, Object?>> frames;

  final Set<int> _predicted;
  final Set<int> _disconnected;

  /// Whether the step is being run again after a correction: what it
  /// started the first time was shown already, so a sound or an effect is
  /// reconciled rather than played twice.
  final bool resimulated;

  /// Where [slot]'s frame came from. Throws a [RangeError] for a slot the
  /// game does not have.
  InputStatus statusOf(int slot) {
    if (!frames.containsKey(slot)) {
      throw RangeError.value(slot, 'slot', 'not one of ${frames.keys}');
    }
    if (_disconnected.contains(slot)) return InputStatus.disconnected;
    if (_predicted.contains(slot)) return InputStatus.predicted;
    return InputStatus.confirmed;
  }

  @override
  String toString() =>
      'RollbackStep($step${resimulated ? ', again' : ''}: '
      '${[for (final slot in frames.keys) '$slot ${statusOf(slot).name}'].join(', ')})';
}

/// What [RollbackSession.onSettled] is told of a step as it leaves the
/// window: its number, the state it ended in and the frames it ran on.
///
/// **One object, so a minor can say more** (how many times the step was run
/// again, whether a slot's frame was a guess) without breaking a listener
/// written against 1.0.
final class SettledStep<S> {
  /// [step], ending in [after], run on [frames].
  const SettledStep({
    required this.step,
    required this.after,
    required this.frames,
  });

  /// The step's number.
  final int step;

  /// The state the step ended in: the one the next began in.
  final S after;

  /// Every slot's frame the step ran on, by slot.
  final Map<int, Map<String, Object?>> frames;
}

/// What a [RollbackSession] has done, read at one moment: how many steps it
/// ran, how many it ran again and what each of those took, and the
/// corrections it could not make.
///
/// The times are per step run again, the restore counted against the first
/// step of each rollback: the median, the 99th percentile (the least time
/// that 99 in 100 of them took no more than) and the worst. They are exact
/// to the microsecond up to [RollbackStats.histogramLimit]; a percentile
/// beyond it reads as the worst. All three are zero before the first
/// rollback.
///
/// [toJson] is one machine's line of a party's report, and [fromJson] reads
/// it back, so the report of a party of phones is put together from what
/// each phone wrote.
final class RollbackStats {
  const RollbackStats({
    required this.steps,
    required this.rollbacks,
    required this.stepsRerun,
    required this.settledOnGuess,
    required this.droppedCorrections,
    required this.droppedEarly,
    required this.resimulationP50,
    required this.resimulationP99,
    required this.resimulationMax,
  });

  /// Reads what [toJson] wrote; a missing count is nought.
  factory RollbackStats.fromJson(Map<String, Object?> json) {
    int count(String key) => (json[key] as num?)?.toInt() ?? 0;
    Duration time(String key) => Duration(microseconds: count(key));
    return RollbackStats(
      steps: count('steps'),
      rollbacks: count('rollbacks'),
      stepsRerun: count('stepsRerun'),
      settledOnGuess: count('settledOnGuess'),
      droppedCorrections: count('droppedCorrections'),
      droppedEarly: count('droppedEarly'),
      resimulationP50: time('resimulationP50Us'),
      resimulationP99: time('resimulationP99Us'),
      resimulationMax: time('resimulationMaxUs'),
    );
  }

  /// How long a step run again may take and still be timed exactly: fifty
  /// milliseconds, three frames at sixty steps a second.
  static const Duration histogramLimit = Duration(milliseconds: 50);

  /// Steps run, each once; the step about to run.
  final int steps;

  /// Corrections that took the game back and ran it forward again.
  final int rollbacks;

  /// Steps run again, over every rollback.
  final int stepsRerun;

  /// A step and a slot whose frame had not come when the step left the
  /// window: settled on a guess, right or wrong. Counted once per slot.
  final int settledOnGuess;

  /// Frames that came after their step settled and differ from the guess
  /// it settled on: the corrections lost.
  final int droppedCorrections;

  /// Frames that came for a step too far ahead to keep.
  final int droppedEarly;

  /// The median time of a step run again.
  final Duration resimulationP50;

  /// The 99th percentile of the time of a step run again.
  final Duration resimulationP99;

  /// The longest a step run again took.
  final Duration resimulationMax;

  /// [droppedCorrections] over [steps]; nought before the first step.
  double get droppedCorrectionShare =>
      steps == 0 ? 0.0 : droppedCorrections / steps;

  Map<String, Object?> toJson() => <String, Object?>{
    'steps': steps,
    'rollbacks': rollbacks,
    'stepsRerun': stepsRerun,
    'settledOnGuess': settledOnGuess,
    'droppedCorrections': droppedCorrections,
    'droppedEarly': droppedEarly,
    'resimulationP50Us': resimulationP50.inMicroseconds,
    'resimulationP99Us': resimulationP99.inMicroseconds,
    'resimulationMaxUs': resimulationMax.inMicroseconds,
  };

  @override
  String toString() =>
      'RollbackStats(steps: $steps, rollbacks: $rollbacks, stepsRerun: '
      '$stepsRerun, settledOnGuess: $settledOnGuess, droppedCorrections: '
      '$droppedCorrections, droppedEarly: $droppedEarly, resimulation p50 '
      '${resimulationP50.inMicroseconds} µs, p99 '
      '${resimulationP99.inMicroseconds} µs, max '
      '${resimulationMax.inMicroseconds} µs)';
}

/// The times of steps run again, as a count per microsecond up to
/// [RollbackStats.histogramLimit] and one count past it: bounded however
/// long a session runs, exact where the thresholds are. Allocated on the
/// first rollback, so a session that never rolls back holds none of it.
final class _ResimulationTimes {
  Uint32List? _counts;
  int _count = 0;
  Duration max = Duration.zero;

  static final int _buckets = RollbackStats.histogramLimit.inMicroseconds;

  void add(Duration time) {
    final us = time.inMicroseconds < 0 ? 0 : time.inMicroseconds;
    // Past the limit only the count and the worst are kept.
    if (us < _buckets) (_counts ??= Uint32List(_buckets))[us]++;
    _count++;
    if (time > max) max = time;
  }

  /// The least time that [percent] in a hundred of the steps took no more
  /// than, by nearest rank.
  Duration percentile(int percent) {
    final counts = _counts;
    if (_count == 0) return Duration.zero;
    final rank = (percent * _count + 99) ~/ 100;
    var seen = 0;
    if (counts != null) {
      for (var us = 0; us < _buckets; us++) {
        seen += counts[us];
        if (seen >= rank) return Duration(microseconds: us);
      }
    }
    return max;
  }
}
