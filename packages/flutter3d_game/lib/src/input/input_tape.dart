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
final class InputFrame {
  const InputFrame({
    this.pressed = const <String>[],
    this.released = const <String>[],
    this.stickX = 0.0,
    this.stickY = 0.0,
    this.lookX = 0.0,
    this.lookY = 0.0,
    this.values = const <String, double>{},
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
  );

  /// Action names rather than the actions themselves.
  ///
  /// [GameAction] wraps a string precisely so a genre can invent its own, and a
  /// tape that stored indices into a list this package knows about could not
  /// carry a shooter's `reload`.
  final List<String> pressed;
  final List<String> released;

  final double stickX;
  final double stickY;
  final double lookX;
  final double lookY;
  final Map<String, double> values;

  /// Whether this step is worth writing down at all.
  bool get isIdle =>
      pressed.isEmpty &&
      released.isEmpty &&
      values.isEmpty &&
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
final class InputTape {
  InputTape({required this.seed, List<InputFrame>? frames})
    : frames = frames ?? <InputFrame>[];

  factory InputTape.fromJson(Map<String, Object?> json) => InputTape(
    seed: (json['seed'] as num?)?.toInt() ?? 0,
    frames: <InputFrame>[
      for (final frame in json['frames'] as List<Object?>? ?? const <Object?>[])
        InputFrame.fromJson(
          (frame! as Map<Object?, Object?>).cast<String, Object?>(),
        ),
    ],
  );

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
    'seed': seed,
    'frames': <Map<String, Object?>>[
      for (final frame in frames) frame.toJson(),
    ],
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
    tape.frames.add(
      InputFrame(
        pressed: <String>[
          for (final action in input.pressedThisStep) action.name,
        ],
        released: <String>[
          for (final action in input.releasedThisStep) action.name,
        ],
        stickX: input.moveAxis.x,
        stickY: input.moveAxis.y,
        lookX: input.lookDelta.x,
        lookY: input.lookDelta.y,
        values: <String, double>{
          for (final entry in input.analogueValues.entries)
            entry.key.name: entry.value,
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
final class InputTapePlayback {
  InputTapePlayback(this.tape);

  final InputTape tape;

  int _step = 0;
  int get step => _step;
  bool get isFinished => _step >= tape.frames.length;

  void applyTo(InputState input) {
    if (isFinished) return;
    final frame = tape.frames[_step++];

    for (final name in frame.pressed) {
      input.press(GameAction(name));
    }
    for (final name in frame.released) {
      input.release(GameAction(name));
    }
    input.setStickAxis(frame.stickX, frame.stickY);
    // Added rather than set, because that is the only way in and because a look
    // delta is a delta: the recording holds what the mouse moved that step.
    input.addLook(frame.lookX, frame.lookY);
    for (final entry in frame.values.entries) {
      input.setActionValue(GameAction(entry.key), entry.value);
    }
  }
}
