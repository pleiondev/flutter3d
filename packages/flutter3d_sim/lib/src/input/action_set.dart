import 'game_action.dart';
import 'input_state.dart';
import 'input_tape.dart';

/// Two buttons an older tape recorded an axis as: the axis is the positive
/// one's value less the negative one's.
typedef ButtonPair = ({GameAction negative, GameAction positive});

/// One action a game declares, with what a player is shown for it.
final class ActionDeclaration {
  const ActionDeclaration(
    this.action, {
    this.label,
    this.rebindable = true,
    this.fromButtons,
  }) : assert(
         fromButtons == null || action is AxisAction,
         'only an axis was ever recorded as two buttons',
       );

  final InputAction<Object> action;

  /// What a rebinding screen calls it. Null shows [InputAction.name].
  final String? label;

  /// Whether a rebinding screen offers it. False for an action the game
  /// binds itself and would break if moved — a fire button a pad trigger
  /// reads as an analogue value, say.
  final bool rebindable;

  /// For an [AxisAction] that an older build read as two [GameAction]s: the
  /// pair a tape recorded before this axis existed.
  ///
  /// **What lets a tape outlive the move to an axis.** A run recorded when
  /// the crane's neck was `liftUp` and `liftDown` holds presses of those two,
  /// and a simulation that now reads `lift` would replay it with the neck
  /// still. [ActionSet.upgradeTape] reads the pair off such a tape and writes
  /// the axis beside it — the same arithmetic the game did itself before.
  final ButtonPair? fromButtons;

  /// [label], or the action's own name.
  String get displayName => label ?? action.name;
}

/// The actions a game or a genre declares: what a player can ask for, of
/// which kind, in the order a rebinding screen lists them.
///
/// **Data, and device-free.** What a key or a stick does is an action map,
/// which is `flutter3d_game`'s and holds device ids; this holds names and
/// kinds only, so a genre package that steps a simulation with no Flutter in
/// it can declare its actions and a tape can be upgraded against them on a
/// server.
final class ActionSet {
  const ActionSet(this.name, this.declarations);

  /// The set's name, written into a saved action map so a file from one game
  /// is not read as another's.
  final String name;

  final List<ActionDeclaration> declarations;

  /// What every game with a body declares: walking and looking, and the
  /// [GameAction.common] buttons — the four directions among them, which
  /// [InputState.moveAxis] adds to the stick.
  static const ActionSet common = ActionSet('common', <ActionDeclaration>[
    ActionDeclaration(DualAxisAction.move, rebindable: false),
    ActionDeclaration(DualAxisAction.look),
    ActionDeclaration(GameAction.moveForward, label: 'forward'),
    ActionDeclaration(GameAction.moveBack, label: 'back'),
    ActionDeclaration(GameAction.moveLeft, label: 'left'),
    ActionDeclaration(GameAction.moveRight, label: 'right'),
    ActionDeclaration(GameAction.jump),
    ActionDeclaration(GameAction.sprint),
    ActionDeclaration(GameAction.use),
  ]);

  /// Every action, in declaration order.
  Iterable<InputAction<Object>> get actions =>
      declarations.map((declaration) => declaration.action);

  /// The declarations a rebinding screen lists.
  Iterable<ActionDeclaration> get rebindable =>
      declarations.where((declaration) => declaration.rebindable);

  /// How [action] was declared here, or null when it was not.
  ActionDeclaration? declarationOf(InputAction<Object> action) {
    for (final declaration in declarations) {
      if (declaration.action == action) return declaration;
    }
    return null;
  }

  bool contains(InputAction<Object> action) => declarationOf(action) != null;

  /// The action called [name] of [kind] — for a saved file, which names
  /// actions as text. Null when this set declares no such action (absent,
  /// not an error: a binding file from another game names actions this one
  /// does not have).
  InputAction<Object>? find(String name, ActionKind kind) {
    for (final action in actions) {
      if (action.name == name && action.kind == kind) return action;
    }
    return null;
  }

  /// This set with [more] after it, under [name] (this one's by default).
  ///
  /// An action declared in both is kept once, as this set declared it — a
  /// genre adding its own verbs to [common] does not get two `jump` rows.
  ActionSet plus(List<ActionDeclaration> more, {String? name}) => ActionSet(
    name ?? this.name,
    List<ActionDeclaration>.unmodifiable(<ActionDeclaration>[
      ...declarations,
      for (final declaration in more)
        if (!contains(declaration.action)) declaration,
    ]),
  );

  /// The axes declared with [ActionDeclaration.fromButtons].
  Iterable<(AxisAction, ButtonPair)> get _legacyAxes sync* {
    for (final declaration in declarations) {
      final pair = declaration.fromButtons;
      if (pair != null) yield (declaration.action as AxisAction, pair);
    }
  }

  /// [tape] with this set's axes written in, where it was recorded before
  /// they existed.
  ///
  /// **The migration from a tape of buttons to a tape of actions.** A tape
  /// at [InputTape.version] 1 records presses and releases of buttons and
  /// nothing for an [AxisAction]. For each axis declared with
  /// [ActionDeclaration.fromButtons], the tape is played into a scratch
  /// [InputState] and the axis is written as `value(positive) -
  /// value(negative)` at every step — the reading the game itself made
  /// before it had the axis. The presses stay, so a reader still asking for
  /// the buttons is answered too.
  ///
  /// A tape at version 2 or later recorded the axes themselves and comes
  /// back as it is, as does any tape when this set declares no such axis.
  InputTape upgradeTape(InputTape tape) {
    final legacy = _legacyAxes.toList();
    if (tape.version >= 2 || legacy.isEmpty) return tape;
    final scratch = InputState();
    final playback = InputTapePlayback(tape);
    final frames = <InputFrame>[];
    for (final frame in tape.frames) {
      playback.applyTo(scratch);
      final axes = <String, double>{
        ...frame.axes,
        for (final (axis, pair) in legacy)
          if (scratch.value(pair.positive) - scratch.value(pair.negative)
              case final value when value != 0.0)
            axis.name: value,
      };
      frames.add(frame.withAxes(axes));
      scratch.endStep();
    }
    return InputTape(
      seed: tape.seed,
      frames: frames,
      version: InputTape.formatVersion,
    );
  }
}
