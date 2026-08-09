/// Everything the player can ask for, named by intent rather than by device.
///
/// The simulation never learns whether an action came from a key, a mouse
/// button or a thumb on a virtual stick. That is the whole point of the split:
/// the touch build and the desktop build run the same game code, and a rebind
/// screen changes a table rather than a call site.
enum GameAction {
  moveForward,
  moveBack,
  moveLeft,
  moveRight,

  /// Held, not tapped: sprinting ends the moment the key comes up.
  sprint,

  /// Buffered on press. A jump asked for a fraction of a second before landing
  /// should still happen, which is why the press is latched rather than sampled.
  jump,

  /// Held for automatic weapons, and its press edge drives the semi-automatic
  /// ones.
  fire,

  /// Buttons, levers, doors, and reading the notes on the walls.
  use,
}
