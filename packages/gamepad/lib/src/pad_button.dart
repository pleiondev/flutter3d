/// Something on a gamepad that is either pressed or not.
///
/// ## The names are physical positions, and that is permanent
///
/// These strings are written into a player's configuration file and read back
/// years later, possibly on a different gamepad. Xbox calls the lower face
/// button `A`, PlayStation calls the same one Cross, and Nintendo swaps `A` and
/// `B` with respect to Xbox — so if the identifier were the printed label, a
/// file written on one pad would **mean something different** on another, and
/// plugging in a different controller would silently move every binding.
///
/// Position is the invariant the hardware actually has. It is also what both
/// Apple's `GCExtendedGamepad` and the browser's Standard Gamepad mapping
/// normalise to already, so no backend has to guess.
///
/// It is the same argument the engine's `InputSource.key` makes for storing a
/// key id rather than a debug name: what is written down must be stable and
/// self-describing.
///
/// Rules, and they are rules rather than style: lower case, dot separated, only
/// ever added to, never renamed. Printed labels are for showing a player and are
/// never saved.
///
/// ## A value class, not an enum
///
/// Equality is by [id], so the constants below are conveniences rather than a
/// closed set: a backend that finds a button nobody here has named can report it
/// without waiting for this file to change. The engine's `GameAction` is a value
/// class for the same reason.
final class PadButton {
  const PadButton(this.id);

  /// Stable, self-describing, and written to disk. See the class doc.
  final String id;

  // The four face buttons, by where the thumb finds them.
  static const PadButton faceSouth = PadButton('face.south');
  static const PadButton faceEast = PadButton('face.east');
  static const PadButton faceWest = PadButton('face.west');
  static const PadButton faceNorth = PadButton('face.north');

  static const PadButton dpadUp = PadButton('dpad.up');
  static const PadButton dpadDown = PadButton('dpad.down');
  static const PadButton dpadLeft = PadButton('dpad.left');
  static const PadButton dpadRight = PadButton('dpad.right');

  static const PadButton shoulderLeft = PadButton('shoulder.left');
  static const PadButton shoulderRight = PadButton('shoulder.right');

  /// The analogue triggers, which are buttons *and* axes.
  ///
  /// A game that wants a threshold reads them here; a game that wants a
  /// proportion reads [PadAxis.triggerLeft]. Racing needs the second and
  /// nothing else in this repository does, which is why both exist.
  static const PadButton triggerLeft = PadButton('trigger.left');
  static const PadButton triggerRight = PadButton('trigger.right');

  /// Pressing a stick down, which is a button and not an axis.
  static const PadButton stickLeftClick = PadButton('stick.left.click');
  static const PadButton stickRightClick = PadButton('stick.right.click');

  static const PadButton start = PadButton('start');
  static const PadButton back = PadButton('back');

  /// The middle button — Xbox's sphere, PlayStation's `PS`.
  ///
  /// Reported where a platform offers it and bound to nothing by default: on
  /// most systems it is the operating system's, and a game that steals it is a
  /// game that cannot be left.
  static const PadButton guide = PadButton('guide');

  /// Every button this file names, for a rebinding screen that wants to list
  /// them.
  ///
  /// Not a registry and not a closed set — see the class doc. A list nobody has
  /// to keep up to date cannot fall behind, so this one is allowed to be
  /// incomplete.
  static const List<PadButton> known = <PadButton>[
    faceSouth,
    faceEast,
    faceWest,
    faceNorth,
    dpadUp,
    dpadDown,
    dpadLeft,
    dpadRight,
    shoulderLeft,
    shoulderRight,
    triggerLeft,
    triggerRight,
    stickLeftClick,
    stickRightClick,
    start,
    back,
    guide,
  ];

  @override
  bool operator ==(Object other) => other is PadButton && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'PadButton($id)';
}

/// Something on a gamepad that has a magnitude.
///
/// Sticks are two axes each, in the range `[-1, 1]`, **with Y positive
/// downwards** — the convention both Apple and the browser report, and the one
/// this package passes on unchanged rather than flipping somewhere a reader
/// cannot see. Whoever routes a stick into a game's forward direction does the
/// flip, and says so.
///
/// Triggers are one axis each in `[0, 1]`.
enum PadAxis {
  leftStickX,
  leftStickY,
  rightStickX,
  rightStickY,
  triggerLeft,
  triggerRight,
}
