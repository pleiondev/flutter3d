import 'package:vector_math/vector_math.dart';

/// What kind of value an [InputAction] carries.
///
/// The three a binding screen and a tape have to tell apart: a button is
/// down or up (with a magnitude where a trigger can say), an axis is one
/// number in `[-1, 1]`, and a dual axis is two of them.
///
/// A class with constants rather than an enum, so a value added in a minor
/// release does not break a `switch` written against it: [name] is what a
/// file or a snapshot writes, and [byName] reads it back.
final class ActionKind {
  const ActionKind._(this.name);

  /// A [GameAction]: held or not, pressed and released on edges.
  static const ActionKind button = ActionKind._('button');

  /// An [AxisAction]: one number in `[-1, 1]`, a throttle or a crane's lift.
  static const ActionKind axis = ActionKind._('axis');

  /// A [DualAxisAction]: two numbers, a direction to walk or a view to turn.
  static const ActionKind dualAxis = ActionKind._('dualAxis');

  /// Every value this version names, in declaration order. A later version
  /// appends; nothing is removed or renamed within a major.
  static const List<ActionKind> values = <ActionKind>[button, axis, dualAxis];

  /// The value called [name], or null for a name this version does not know,
  /// which is what a file written by a later version can carry.
  static ActionKind? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name: what a file, a report or a snapshot
  /// writes for this value. Never renamed within a major.
  final String name;

  @override
  String toString() => 'ActionKind.$name';
}

/// A named thing the player can ask for, with the type of its value.
///
/// **Three kinds, grown only here.** A game declares its own actions of each
/// kind, as it always declared its own [GameAction]s; what it cannot do is
/// invent a fourth kind, because a tape, a rebinding screen and a saved action
/// map all have to know how to write each kind down. A later release can add
/// one with its [ActionKind], so a `switch` over actions ends with a wildcard.
///
/// [T] is what [InputState.valueOf] answers for it: `bool` for a button,
/// `double` for an axis, [Vector2] for a dual axis.
///
/// Equality is by kind and name, so a declaration in a genre and a name read
/// back from a file are the same action without a registry between them.
abstract final class InputAction<T extends Object> {
  /// What it is called, in a tape, a saved action map and a rebind screen.
  String get name;

  /// Which of the three kinds of value it carries; fixed by the subclass.
  ActionKind get kind;
}

/// One number in `[-1, 1]` the player asks for: how hard to pull a crane's
/// rope up or let it down, how far to turn a wheel.
///
/// **Its own kind rather than two buttons**, which is what the games did
/// before there was one: `liftUp` and `liftDown`, and every reader writing
/// `held(up) - held(down)` itself. Two keys still drive it — see the
/// composite bindings in `flutter3d_game` — and so does a stick's one axis
/// or a band under a thumb, and the simulation reads one number either way.
final class AxisAction implements InputAction<double> {
  /// A one-number action called [name]; two with one name are one action.
  const AxisAction(this.name);

  @override
  final String name;

  @override
  ActionKind get kind => ActionKind.axis;

  @override
  bool operator ==(Object other) => other is AxisAction && other.name == name;

  @override
  int get hashCode => Object.hash(ActionKind.axis, name);

  @override
  String toString() => 'AxisAction($name)';
}

/// Two numbers the player asks for together: a direction to walk, a view to
/// turn.
///
/// [move] and [look] are the two every game with a body has, and they are
/// what [InputState.moveAxis] and [InputState.lookDelta] already were — those
/// stay, and answer for these.
final class DualAxisAction implements InputAction<Vector2> {
  /// A two-number action called [name], a position unless [isDelta].
  const DualAxisAction(this.name, {this.isDelta = false});

  @override
  final String name;

  /// Whether the value is movement since the last step rather than a
  /// position: a mouse's motion, summed until a step takes it and zeroed by
  /// [InputState.endStep]. A stick is not a delta; it says where it is.
  final bool isDelta;

  @override
  ActionKind get kind => ActionKind.dualAxis;

  /// Walking: `x` strafes right, `y` goes forward, never longer than one.
  /// [InputState.moveAxis].
  static const DualAxisAction move = DualAxisAction('move');

  /// Turning the view, as a delta. [InputState.lookDelta].
  static const DualAxisAction look = DualAxisAction('look', isDelta: true);

  @override
  bool operator ==(Object other) =>
      other is DualAxisAction && other.name == name;

  @override
  int get hashCode => Object.hash(ActionKind.dualAxis, name);

  @override
  String toString() => 'DualAxisAction($name)';
}

/// Something the player can ask for, named by intent rather than by device.
///
/// The simulation never learns whether an action came from a key, a mouse
/// button or a thumb on a virtual stick. That is the whole point of the split:
/// the touch build and the desktop build run the same game code, and a rebind
/// screen changes a table rather than a call site.
///
/// ## Open, and why it stopped being an enum
///
/// This was an enum, and one of its members was `fire`. That is a shooter's
/// word, and it sat in the engine: a platformer that wanted `dash` had the
/// choice of abusing `fire` or editing this file, and a racing game with
/// `handbrake` had the same choice. Neither is a choice an engine should be
/// handing out.
///
/// So it is a value class, open the same way `LightingModel` in the renderer is
/// open: the constants below are the ones every game has, and a genre declares
/// its own beside them.
///
/// ```dart
/// abstract final class PlatformerActions {
///   static const GameAction dash = GameAction('dash');
/// }
/// ```
///
/// Equality is by [name], so an action declared in two places is one action —
/// which is what lets a rebinding table be saved as text and read back without
/// a registry to resolve against.
///
/// It is the button kind of [InputAction]; [AxisAction] and [DualAxisAction]
/// are the other two.
final class GameAction implements InputAction<bool> {
  /// A button action called [name]; two with one name are one action.
  const GameAction(this.name);

  /// What it is called, in a saved config and in a rebind screen.
  @override
  final String name;

  @override
  ActionKind get kind => ActionKind.button;

  /// While held, adds one to the `y` of [InputState.moveAxis].
  static const GameAction moveForward = GameAction('moveForward');

  /// While held, takes one from the `y` of [InputState.moveAxis].
  static const GameAction moveBack = GameAction('moveBack');

  /// While held, takes one from the `x` of [InputState.moveAxis].
  static const GameAction moveLeft = GameAction('moveLeft');

  /// While held, adds one to the `x` of [InputState.moveAxis].
  static const GameAction moveRight = GameAction('moveRight');

  /// Held, not tapped: sprinting ends the moment the key comes up.
  static const GameAction sprint = GameAction('sprint');

  /// Buffered on press. A jump asked for a fraction of a second before landing
  /// should still happen, which is why the press is latched rather than sampled.
  static const GameAction jump = GameAction('jump');

  /// Buttons, levers, doors, and reading the notes on the walls.
  static const GameAction use = GameAction('use');

  /// The seven every game in this repository has needed, for a rebind screen that
  /// wants to list them. A genre adds its own; there is no registry, and that is
  /// deliberate — a list nobody has to keep up to date cannot fall behind.
  static const List<GameAction> common = <GameAction>[
    moveForward,
    moveBack,
    moveLeft,
    moveRight,
    sprint,
    jump,
    use,
  ];

  @override
  bool operator ==(Object other) => other is GameAction && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'GameAction($name)';
}
