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
final class GameAction {
  const GameAction(this.name);

  /// What it is called, in a saved config and in a rebind screen.
  final String name;

  static const GameAction moveForward = GameAction('moveForward');
  static const GameAction moveBack = GameAction('moveBack');
  static const GameAction moveLeft = GameAction('moveLeft');
  static const GameAction moveRight = GameAction('moveRight');

  /// Held, not tapped: sprinting ends the moment the key comes up.
  static const GameAction sprint = GameAction('sprint');

  /// Buffered on press. A jump asked for a fraction of a second before landing
  /// should still happen, which is why the press is latched rather than sampled.
  static const GameAction jump = GameAction('jump');

  /// Buttons, levers, doors, and reading the notes on the walls.
  static const GameAction use = GameAction('use');

  /// The six every game in this repository has needed, for a rebind screen that
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
