import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show
        ExternalStateInput,
        FormatDocument,
        FormatSpec,
        Flutter3dFormatException,
        SimulationVersion;

import '../save/demo.dart' show Demo;
import '../save/simulation_version.dart' show ReplayException;

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
    this.dualAxes = const <String, DualAxisValue>{},
    this.external = const <ExternalStateInput>[],
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
    dualAxes: <String, DualAxisValue>{
      for (final entry
          in (json['dual'] as Map<Object?, Object?>? ??
                  const <Object?, Object?>{})
              .entries)
        entry.key! as String: switch (entry.value) {
          [final num x, final num y] => DualAxisValue(
            x: x.toDouble(),
            y: y.toDouble(),
          ),
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

  /// Analogue readings this step, by action name — a trigger's squeeze, a
  /// throttle. By name, as [tunes] and [axes] are, so an action a data plugin
  /// declares reaches the tape with no Dart type behind it.
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
  ///
  /// **A map of names to numbers, kept as one**: it is the tape's, an
  /// inspector's and a data plugin's form, and none of them names a Dart
  /// type. Code reads a tunable typed through `Tunable`.
  final Map<String, double> tunes;

  /// Each [AxisAction] with a value this step, by name; an axis absent here
  /// read nought. Written from [InputTape.version] 2.
  ///
  /// By name for the same reason [tunes] is: an action a data plugin
  /// declares has no Dart type, and the tape must carry it all the same.
  final Map<String, double> axes;

  /// Each [DualAxisAction] with a value this step, by name, other than
  /// [DualAxisAction.move] and [DualAxisAction.look] — [stickX]/[stickY] and
  /// [lookX]/[lookY] are those two. Written from [InputTape.version] 2.
  final Map<String, DualAxisValue> dualAxes;

  /// State that arrived from outside the simulation for this step, in the
  /// order it was fed (`InputState.feedExternal`): the step's own kind of
  /// input for a twin, a laboratory fed by an instrument or a headset.
  ///
  /// **Not in the frame's own document.** A tape writes the step's external
  /// inputs beside its frames, under `externalInputs` with the step each was
  /// fed at ([InputTape.toJson]), and a run lifts that list to its top
  /// level, where `.f3drun` 5 reserved it; [toJson] here leaves it out.
  final List<ExternalStateInput> external;

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
    external: external,
  );

  /// This frame with [external] in place of its own.
  InputFrame withExternal(List<ExternalStateInput> external) => InputFrame(
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
    external: List<ExternalStateInput>.unmodifiable(external),
  );

  /// Whether this step is worth writing down at all.
  bool get isIdle =>
      external.isEmpty &&
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
        for (final MapEntry(key: name, value: DualAxisValue(:x, :y))
            in dualAxes.entries)
          name: <double>[x, y],
      },
  };
}

/// A [DualAxisAction]'s pair in one [InputFrame], as [InputFrame.dualAxes]
/// holds it.
final class DualAxisValue {
  const DualAxisValue({required this.x, required this.y});

  /// The first number: a unitless fraction of full deflection for a stick,
  /// the device's own units for a delta.
  final double x;

  /// The second number: a unitless fraction of full deflection for a
  /// stick, the device's own units for a delta.
  final double y;

  @override
  bool operator ==(Object other) =>
      other is DualAxisValue && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'DualAxisValue($x, $y)';
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

  /// Reads what [toJson] wrote, at any version up to [formatVersion].
  ///
  /// A tape with no version was written before tapes had one, and is 1.
  factory InputTape.fromJson(Map<String, Object?> json) {
    final version = switch (json['version']) {
      null => 1,
      final Object said when (FormatSpec.wholeNumber(said) ?? 0) >= 1 =>
        FormatSpec.wholeNumber(said)!,
      final other => throw InputTapeFormatException(
        'the tape names version $other',
      ),
    };
    // A newer tape, another format's document or a `requires` this build does
    // not know is refused here, with the reason.
    final lifted = format.open(json, refuse: InputTapeFormatException.new);
    final frames = <InputFrame>[
      for (final frame in json['frames'] as List<Object?>? ?? const <Object?>[])
        InputFrame.fromJson(
          (frame! as Map<Object?, Object?>).cast<String, Object?>(),
        ),
    ];
    for (final MapEntry(key: step, value: inputs) in readExternalInputs(
      json['externalInputs'],
      steps: frames.length,
    ).entries) {
      frames[step] = frames[step].withExternal(inputs);
    }
    return InputTape(
      unknown: FormatDocument.unknownIn(lifted, known: _known),
      seed: (json['seed'] as num?)?.toInt() ?? 0,
      version: version,
      frames: frames,
    );
  }

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
    understands: <String>{externalInputsRequirement},
  );

  /// What a tape holding [InputFrame.external] says it `requires`: a build
  /// that would replay the tape without them, into another run, refuses it
  /// by this name instead.
  static const String externalInputsRequirement = 'externalInputs';

  static const Set<String> _known = <String>{
    'seed',
    'frames',
    'externalInputs',
  };

  /// The newest tape version this build reads and writes.
  static const int formatVersion = 2;

  /// The version this tape was read at — [formatVersion] for one recorded
  /// by this build. Below 2 it may need `ActionSet.upgradeTape`.
  final int version;

  /// The generator state the run started from.
  ///
  /// Without it the tape is a recording of a different run: the same inputs
  /// against different dice go somewhere else, and the divergence looks like the
  /// replay being broken rather than like a missing number.
  final int seed;

  /// One entry per fixed step, in order. Index is the step number.
  final List<InputFrame> frames;

  @override
  FormatSpec get spec => format;

  @override
  List<String> get requires => <String>[
    if (frames.any((frame) => frame.external.isNotEmpty))
      externalInputsRequirement,
  ];

  /// [frames]' external inputs as a tape writes them: one entry per input,
  /// each with the `step` it was fed at, in step order and, within a step,
  /// in the order it was fed. Empty for a tape with none.
  List<Map<String, Object?>> externalInputsJson() => <Map<String, Object?>>[
    for (var step = 0; step < frames.length; step++)
      for (final input in frames[step].external)
        <String, Object?>{'step': step, ...input.toJson()},
  ];

  /// Reads a list [externalInputsJson] wrote into the inputs of each step,
  /// by step. Throws an [InputTapeFormatException] for an entry that is not
  /// one, or a step outside the tape's [steps] frames or out of order.
  static Map<int, List<ExternalStateInput>> readExternalInputs(
    Object? json, {
    required int steps,
  }) {
    if (json == null) return const <int, List<ExternalStateInput>>{};
    if (json is! List) {
      throw const InputTapeFormatException(
        'the external inputs are not a list',
      );
    }
    final read = <int, List<ExternalStateInput>>{};
    var last = 0;
    for (final entry in json) {
      final step = switch (entry) {
        {'step': final int step} when step >= last && step < steps => step,
        _ => throw InputTapeFormatException(
          'an external input names no step from $last to ${steps - 1} '
          '(entries are in step order, one frame each): $entry',
        ),
      };
      try {
        (read[step] ??= <ExternalStateInput>[]).add(
          ExternalStateInput.fromJson(entry),
        );
      } on Flutter3dFormatException catch (error, stackTrace) {
        Error.throwWithStackTrace(
          InputTapeFormatException(
            'the external input at step $step: ${error.message}',
          ),
          stackTrace,
        );
      }
      last = step;
    }
    return read;
  }

  /// The version [toJson] writes: the lowest that says what the frames hold.
  int get writtenVersion => frames.any((frame) => frame.needsVersion2) ? 2 : 1;

  int get steps => frames.length;

  Map<String, Object?> toJson() => <String, Object?>{
    ...format.envelope(version: writtenVersion, requires: requires),
    'seed': seed,
    'frames': <Map<String, Object?>>[
      for (final frame in frames) frame.toJson(),
    ],
    if (frames.any((frame) => frame.external.isNotEmpty))
      'externalInputs': externalInputsJson(),
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

  /// Forgets every entry from step [steps] on, keeping the first [steps].
  ///
  /// For a run rewound and gone on from an earlier step — a timeline's
  /// branch: the entries after it describe a future that is not going to
  /// happen, and the next [record] writes the step the run takes instead.
  /// Truncating to nothing makes the next entry a first one again, carrying
  /// what is held as presses. Asking to keep more than the tape has keeps it
  /// whole.
  void truncate(int steps) {
    RangeError.checkNotNegative(steps, 'steps');
    final frames = tape.frames;
    if (steps < frames.length) frames.removeRange(steps, frames.length);
  }

  /// Writes the step about to run: what [input] holds now, its presses and
  /// releases since the last step, and every axis that is not at rest.
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
        stickX: input.dualAxis(DualAxisAction.move).x,
        stickY: input.dualAxis(DualAxisAction.move).y,
        lookX: input.dualAxis(DualAxisAction.look).x,
        lookY: input.dualAxis(DualAxisAction.look).y,
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
        dualAxes: <String, DualAxisValue>{
          for (final MapEntry(key: axis, :value)
              in input.dualAxisValues.entries)
            if (value.x != 0.0 || value.y != 0.0)
              axis.name: DualAxisValue(x: value.x, y: value.y),
        },
        external: input.externalThisStep,
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
///
/// **A recorded run is played through the unnamed constructor, which checks
/// it first.** A `.f3drun` names the simulation it was recorded on
/// ([Demo.simulation]), and the same input played on another one goes
/// somewhere else: the playback refuses it with [ReplayException], carrying
/// the run's pose record, before a step is played, so no caller can forget
/// to ask. [InputTapePlayback.tape] plays a tape as it is, for a tape this
/// run recorded itself (a rewind point's) and for tests.
final class InputTapePlayback {
  /// [demo]'s tape, refused with [ReplayException] unless [simulation] —
  /// what this build runs, `EngineLoop.simulationVersion` — is the one the
  /// run was recorded on ([Demo.checkSimulation]).
  factory InputTapePlayback(
    Demo demo, {
    required SimulationVersion simulation,
    ActionSet? actions,
  }) {
    demo.checkSimulation(simulation);
    return InputTapePlayback.tape(demo.tape, actions: actions);
  }

  /// [tape] played as it is, with no simulation to check it against: a
  /// tape this run recorded itself, such as a rewind point's, and a test's.
  /// A recorded run goes through the unnamed constructor.
  InputTapePlayback.tape(InputTape tape, {ActionSet? actions})
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
    for (final MapEntry(key: name, value: DualAxisValue(:x, :y))
        in frame.dualAxes.entries) {
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
    for (final external in frame.external) {
      input.feedExternal(external);
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
