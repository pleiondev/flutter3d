import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show FormatDocument, FormatSpec, Flutter3dFormatException;

import 'action_set.dart';
import 'game_action.dart';
import 'input_state.dart';

/// One fixed step's worth of intent.
///
/// **Transitions, not the held set.** What became held and what let go, rather
/// than everything held — because held follows from the transitions before it,
/// and a tape recording the full set is proportional to how long somebody played
/// where this is proportional to what they did. A player holding one key for a
/// minute costs two entries.
///
/// The axes and the analogue readings are the exception and have to be written
/// every step: a stick at three quarters is neither a press nor a release, and a
/// tape that recorded only transitions would replay the run with the accelerator
/// off.
///
/// ## Action values, not keys
///
/// Everything here is named by action — a [GameAction] pressed, an
/// [AxisAction]'s number in [axes], a [DualAxisAction]'s pair in [dualAxes],
/// and the two every game has, [DualAxisAction.move] and
/// [DualAxisAction.look], in [stickX]/[stickY] and [lookX]/[lookY]. No key, no
/// pad button and no finger is ever written down, so a tape plays back the
/// same whatever the player who watches it has bound — and whatever the
/// player who recorded it had.
final class InputFrame {
  const InputFrame({
    this.pressed = const <String>[],
    this.released = const <String>[],
    this.stickX = 0.0,
    this.stickY = 0.0,
    this.lookX = 0.0,
    this.lookY = 0.0,
    this.values = const <String, double>{},
    this.slot,
    this.tunes = const <String, double>{},
    this.axes = const <String, double>{},
    this.dualAxes = const <String, ({double x, double y})>{},
  });

  factory InputFrame.fromJson(Map<String, Object?> json) => InputFrame(
    pressed: <String>[
      for (final name in json['pressed'] as List<Object?>? ?? const <Object?>[])
        name! as String,
    ],
    released: <String>[
      for (final name
          in json['released'] as List<Object?>? ?? const <Object?>[])
        name! as String,
    ],
    stickX: (json['sx'] as num?)?.toDouble() ?? 0.0,
    stickY: (json['sy'] as num?)?.toDouble() ?? 0.0,
    lookX: (json['lx'] as num?)?.toDouble() ?? 0.0,
    lookY: (json['ly'] as num?)?.toDouble() ?? 0.0,
    values: <String, double>{
      for (final entry
          in (json['values'] as Map<Object?, Object?>? ??
                  const <Object?, Object?>{})
              .entries)
        entry.key! as String: (entry.value! as num).toDouble(),
    },
    slot: (json['slot'] as num?)?.toInt(),
    tunes: <String, double>{
      for (final entry
          in (json['tunes'] as Map<Object?, Object?>? ??
                  const <Object?, Object?>{})
              .entries)
        entry.key! as String: (entry.value! as num).toDouble(),
    },
    axes: <String, double>{
      for (final entry
          in (json['axes'] as Map<Object?, Object?>? ??
                  const <Object?, Object?>{})
              .entries)
        entry.key! as String: (entry.value! as num).toDouble(),
    },
    dualAxes: <String, ({double x, double y})>{
      for (final entry
          in (json['dual'] as Map<Object?, Object?>? ??
                  const <Object?, Object?>{})
              .entries)
        entry.key! as String: switch (entry.value) {
          [final num x, final num y] => (x: x.toDouble(), y: y.toDouble()),
          final other => throw InputTapeFormatException(
            'the dual axis ${entry.key} is $other, not a pair of numbers',
          ),
        },
    },
  );

  /// Action names rather than the actions themselves.
  ///
  /// [GameAction] wraps a string precisely so a genre can invent its own, and a
  /// tape that stored indices into a list this package knows about could not
  /// carry a shooter's `reload`.
  final List<String> pressed;
  final List<String> released;

  /// [InputState.moveAxis]'s `x`, strafing right: a unitless fraction of
  /// full deflection, the pair never longer than 1.
  final double stickX;

  /// [InputState.moveAxis]'s `y`, forward: a unitless fraction of full
  /// deflection, as [stickX].
  final double stickY;

  /// [InputState.lookDelta]'s `x` this step, in the units the device
  /// reports; the camera applies sensitivity.
  final double lookX;

  /// [InputState.lookDelta]'s `y` this step, in the device's units, as
  /// [lookX].
  final double lookY;
  final Map<String, double> values;

  /// The numbered slot asked for this step, if any.
  ///
  /// **Found missing by playing the crypt.** A tape without this replayed six
  /// hundred steps of the shipped game to the same positions, the same dice
  /// and the same dead monster, and arrived holding the pistol where the
  /// player had switched to the shotgun — with the shotgun's shells unspent
  /// and the pistol's bullets gone. A slot request is neither a press nor a
  /// release, so a tape of transitions had nowhere to put it.
  final int? slot;

  /// Tunables set by this step, by name — `InputState.tune`.
  final Map<String, double> tunes;

  /// Each [AxisAction] with a value this step, by name; an axis absent here
  /// read nought. Written from [InputTape.version] 2.
  final Map<String, double> axes;

  /// Each [DualAxisAction] with a value this step, by name, other than
  /// [DualAxisAction.move] and [DualAxisAction.look] — [stickX]/[stickY] and
  /// [lookX]/[lookY] are those two. Written from [InputTape.version] 2.
  final Map<String, ({double x, double y})> dualAxes;

  /// Whether this frame says anything a version-1 reader would drop.
  bool get needsVersion2 => axes.isNotEmpty || dualAxes.isNotEmpty;

  /// This frame with [axes] in place of its own.
  InputFrame withAxes(Map<String, double> axes) => InputFrame(
    pressed: pressed,
    released: released,
    stickX: stickX,
    stickY: stickY,
    lookX: lookX,
    lookY: lookY,
    values: values,
    slot: slot,
    tunes: tunes,
    axes: axes,
    dualAxes: dualAxes,
  );

  /// Whether this step is worth writing down at all.
  bool get isIdle =>
      pressed.isEmpty &&
      released.isEmpty &&
      values.isEmpty &&
      slot == null &&
      tunes.isEmpty &&
      axes.isEmpty &&
      dualAxes.isEmpty &&
      stickX == 0.0 &&
      stickY == 0.0 &&
      lookX == 0.0 &&
      lookY == 0.0;

  Map<String, Object?> toJson() => <String, Object?>{
    if (pressed.isNotEmpty) 'pressed': pressed,
    if (released.isNotEmpty) 'released': released,
    if (stickX != 0.0) 'sx': stickX,
    if (stickY != 0.0) 'sy': stickY,
    if (lookX != 0.0) 'lx': lookX,
    if (lookY != 0.0) 'ly': lookY,
    if (values.isNotEmpty) 'values': values,
    if (slot != null) 'slot': slot,
    if (tunes.isNotEmpty) 'tunes': tunes,
    if (axes.isNotEmpty) 'axes': axes,
    if (dualAxes.isNotEmpty)
      'dual': <String, List<double>>{
        for (final MapEntry(key: name, value: (:x, :y)) in dualAxes.entries)
          name: <double>[x, y],
      },
  };
}

/// A run, as the inputs that produced it.
///
/// **This is what a deterministic simulation is worth.** A step here reaches for
/// no clock and no loose dice — a scan in `tool/structure.dart` says so — and
/// its randomness is a [GameRandom] whose state is readable and restorable. So
/// the same starting state, fed the same intents in the same order, produces the
/// same run: not approximately, exactly.
///
/// What that buys is not one feature but several, and all of them off one tape:
///
/// * a replay, at a few bytes a second rather than a pose per body per step;
/// * a bug that happens once in a thousand steps, reproduced from the file
///   somebody attached to the report;
/// * a test that plays a whole level and asserts where it ended.
///
/// **It is a tape of intents, not of positions.** The racing game's ghost is the
/// other kind and is right to be: it replays one car's path for a player to race
/// against, and it survives the simulation changing underneath it. This does
/// not, and must not — a tape that still produced the old ending after the
/// physics changed would be a recording of nothing.
///
/// ## Versions
///
/// 1 recorded buttons, the move and look actions, button magnitudes, slots
/// and tunables. 2 adds [InputFrame.axes] and [InputFrame.dualAxes]: a
/// version-1 reader would drop them and replay a crane with its neck still,
/// so a tape that has them says 2 and a `.f3drun` holding it is written at a
/// version the old reader refuses. A tape without them is still written as 1.
///
/// A version-1 tape of a game whose axes used to be button pairs is
/// upgraded by `ActionSet.upgradeTape`, which [InputTapePlayback] calls
/// when it is given the game's set.
final class InputTape extends FormatDocument {
  InputTape({
    required this.seed,
    List<InputFrame>? frames,
    this.version = formatVersion,
    super.unknown,
  }) : frames = frames ?? <InputFrame>[];

  /// The input tape in the registry: `f3d.inputTape`, also what a `.f3drun`
  /// holds under `tape`.
  ///
  /// **The envelope is additive, and the version is now always written.** A
  /// version-1 tape used to leave it out; a build from before reads a
  /// missing version and a `1` the same, and ignores the other three keys.
  ///
  /// `f3d.input-tape`, the id a tape was written under before the ids took
  /// one style (dotted lowerCamel), is read as this one.
  static const FormatSpec format = FormatSpec(
    id: 'f3d.inputTape',
    aliases: <String>['f3d.input-tape'],
    version: formatVersion,
    suffixes: <String>['.tape.json'],
    fixture: 'test/fixtures/v<N>/input.tape.json',
  );

  @override
  FormatSpec get spec => format;

  static const Set<String> _known = <String>{'seed', 'frames'};

  /// Reads what [toJson] wrote, at any version up to [formatVersion].
  ///
  /// A tape with no version was written before tapes had one, and is 1.
  factory InputTape.fromJson(Map<String, Object?> json) {
    final version = switch (json['version']) {
      null => 1,
      final num number when number == number.truncate() && number >= 1 =>
        number.toInt(),
      final other => throw InputTapeFormatException(
        'the tape names version $other',
      ),
    };
    // A newer tape, another format's document or a `requires` this build does
    // not know is refused here, with the reason.
    final lifted = format.open(json, refuse: InputTapeFormatException.new);
    return InputTape(
      unknown: FormatDocument.unknownIn(lifted, known: _known),
      seed: (json['seed'] as num?)?.toInt() ?? 0,
      version: version,
      frames: <InputFrame>[
        for (final frame
            in json['frames'] as List<Object?>? ?? const <Object?>[])
          InputFrame.fromJson(
            (frame! as Map<Object?, Object?>).cast<String, Object?>(),
          ),
      ],
    );
  }

  /// The newest tape version this build reads and writes.
  static const int formatVersion = 2;

  /// The version this tape was read at — [formatVersion] for one recorded
  /// by this build. Below 2 it may need `ActionSet.upgradeTape`.
  final int version;

  /// The version [toJson] writes: the lowest that says what the frames hold.
  int get writtenVersion => frames.any((frame) => frame.needsVersion2) ? 2 : 1;

  /// The generator state the run started from.
  ///
  /// Without it the tape is a recording of a different run: the same inputs
  /// against different dice go somewhere else, and the divergence looks like the
  /// replay being broken rather than like a missing number.
  final int seed;

  /// One entry per fixed step, in order. Index is the step number.
  final List<InputFrame> frames;

  int get steps => frames.length;

  Map<String, Object?> toJson() => <String, Object?>{
    ...format.envelope(version: writtenVersion, requires: requires),
    'seed': seed,
    'frames': <Map<String, Object?>>[
      for (final frame in frames) frame.toJson(),
    ],
    for (final MapEntry(:key, :value) in unknown.entries)
      if (!_known.contains(key)) key: value,
  };
}

/// Writes down what a player did, one entry per step.
///
/// Call [record] once per fixed step, **after** the input has been filled for
/// that step and **before** the step runs. Recording afterwards records the
/// latches the step has already cleared, which is a tape of nothing happening.
final class InputTapeRecorder {
  InputTapeRecorder({required int seed}) : tape = InputTape(seed: seed);

  final InputTape tape;

  void record(InputState input) {
    // The first entry carries what was already held, as presses. A recording
    // that begins while the player is walking forward begins after the press
    // that started the walk, and a replay that never pressed it stands still
    // where the player moved. Once only: from the second entry on, held state
    // follows from the transitions the tape already has.
    final pressed = <String>[
      if (tape.frames.isEmpty)
        for (final action in input.heldNow)
          if (!input.pressed(action)) action.name,
      for (final action in input.pressedThisStep) action.name,
    ];
    tape.frames.add(
      InputFrame(
        pressed: pressed,
        released: <String>[
          for (final action in input.releasedThisStep) action.name,
        ],
        stickX: input.moveAxis.x,
        stickY: input.moveAxis.y,
        lookX: input.lookDelta.x,
        lookY: input.lookDelta.y,
        values: <String, double>{
          for (final entry in input.analogValues.entries)
            entry.key.name: entry.value,
        },
        slot: input.slotRequest,
        tunes: input.tunesThisStep,
        // Nought is not written: an axis absent reads nought, and a tape of a
        // game with an axis nobody touched stays a version-1 tape.
        axes: <String, double>{
          for (final MapEntry(key: axis, :value) in input.axisValues.entries)
            if (value != 0.0) axis.name: value,
        },
        dualAxes: <String, ({double x, double y})>{
          for (final MapEntry(key: axis, :value)
              in input.dualAxisValues.entries)
            if (value.x != 0.0 || value.y != 0.0)
              axis.name: (x: value.x, y: value.y),
        },
      ),
    );
  }
}

/// Plays a tape back into an [InputState], one step at a time.
///
/// Call [applyTo] once per fixed step, in place of reading a keyboard. The run
/// then steps exactly as it did when it was recorded, provided the simulation
/// was started from the tape's [InputTape.seed].
///
/// **Runs out rather than looping or holding.** A tape shorter than the run
/// being played leaves the input untouched from [isFinished] onwards, so a
/// player who takes over from a replay finds the controls in the state the
/// recording left them rather than jammed on the last frame's keys.
///
/// Given the game's [ActionSet], a version-1 tape is upgraded first — see
/// `ActionSet.upgradeTape` — so a simulation that reads an axis where it once
/// read two buttons replays an old run as it was played.
final class InputTapePlayback {
  InputTapePlayback(InputTape tape, {ActionSet? actions})
    : tape = actions == null ? tape : actions.upgradeTape(tape);

  final InputTape tape;

  int _step = 0;

  /// The axes the last frame gave a value to, so the next can let go of the
  /// ones it is silent about.
  final Set<String> _axesSpoken = <String>{};
  final Set<String> _dualAxesSpoken = <String>{};
  int get step => _step;
  bool get isFinished => _step >= tape.frames.length;

  void applyTo(InputState input) {
    if (isFinished) return;
    final frame = tape.frames[_step++];
    // The tape is the one device allowed through a mute — see
    // [InputState.muted] — so the mute is lifted for exactly these writes and
    // put back as it was found.
    final muted = input.muted;
    input.muted = false;
    try {
      _apply(frame, input);
    } finally {
      input.muted = muted;
    }
  }

  void _apply(InputFrame frame, InputState input) {
    for (final name in frame.pressed) {
      input.press(GameAction(name));
    }
    for (final name in frame.released) {
      input.release(GameAction(name));
    }
    input.setStickAxis(frame.stickX, frame.stickY);
    // The stick part, and then the answer: the tape holds what the step read
    // as the move action, which the stick and the directions pressed above
    // would otherwise be summed into again. See [InputState.replayMoveAxis].
    input.replayMoveAxis(frame.stickX, frame.stickY);
    // Added rather than set, because that is the only way in and because a look
    // delta is a delta: the recording holds what the mouse moved that step.
    input.addLook(frame.lookX, frame.lookY);
    for (final entry in frame.values.entries) {
      input.setActionValue(GameAction(entry.key), entry.value);
    }
    // Every axis is written every step, nought where the frame is silent:
    // the recorder leaves nought out, and an axis the tape let go of must
    // not go on reading the last number it had.
    for (final axis in _axesSpoken) {
      if (!frame.axes.containsKey(axis)) input.clearAxis(AxisAction(axis));
    }
    for (final MapEntry(key: name, :value) in frame.axes.entries) {
      input.setAxis(AxisAction(name), value);
    }
    _axesSpoken
      ..clear()
      ..addAll(frame.axes.keys);
    for (final axis in _dualAxesSpoken) {
      if (!frame.dualAxes.containsKey(axis)) {
        input.clearDualAxis(DualAxisAction(axis));
      }
    }
    for (final MapEntry(key: name, value: (:x, :y)) in frame.dualAxes.entries) {
      // Cleared and added, as a delta: the action's own kind is not on the
      // tape, and adding to nothing writes the recorded pair exactly, where
      // setting would clamp a delta that was larger than one. The entry goes
      // at [InputState.endStep] and the next frame writes it again.
      final action = DualAxisAction(name, isDelta: true);
      input
        ..clearDualAxis(action)
        ..setDualAxis(action, x, y);
    }
    _dualAxesSpoken
      ..clear()
      ..addAll(frame.dualAxes.keys);
    final slot = frame.slot;
    if (slot != null) input.requestSlot(slot);
    for (final MapEntry(key: name, :value) in frame.tunes.entries) {
      input.tune(name, value);
    }
  }
}

/// Thrown when an input tape cannot be read.
final class InputTapeFormatException extends Flutter3dFormatException {
  const InputTapeFormatException(this.message);

  @override
  final String message;

  @override
  String toString() => 'InputTapeFormatException: $message';
}
