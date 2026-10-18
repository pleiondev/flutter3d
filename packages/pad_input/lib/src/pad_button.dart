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
  /// A button known by [id], which may be one no constant below names.
  const PadButton(this.id);

  /// Stable, self-describing, and written to disk. See the class doc.
  final String id;

  // The four face buttons, by where the thumb finds them.

  /// The lower face button: Xbox `A`, PlayStation Cross, Nintendo `B`.
  static const PadButton faceSouth = PadButton('face.south');

  /// The right face button: Xbox `B`, PlayStation Circle, Nintendo `A`.
  static const PadButton faceEast = PadButton('face.east');

  /// The left face button: Xbox `X`, PlayStation Square, Nintendo `Y`.
  static const PadButton faceWest = PadButton('face.west');

  /// The upper face button: Xbox `Y`, PlayStation Triangle, Nintendo `X`.
  static const PadButton faceNorth = PadButton('face.north');

  /// Up on the d-pad, whether the pad reports a hat or a key.
  static const PadButton dpadUp = PadButton('dpad.up');

  /// Down on the d-pad, whether the pad reports a hat or a key.
  static const PadButton dpadDown = PadButton('dpad.down');

  /// Left on the d-pad, whether the pad reports a hat or a key.
  static const PadButton dpadLeft = PadButton('dpad.left');

  /// Right on the d-pad, whether the pad reports a hat or a key.
  static const PadButton dpadRight = PadButton('dpad.right');

  /// The left bumper above the trigger: Xbox `LB`, PlayStation `L1`.
  static const PadButton shoulderLeft = PadButton('shoulder.left');

  /// The right bumper above the trigger: Xbox `RB`, PlayStation `R1`.
  static const PadButton shoulderRight = PadButton('shoulder.right');

  /// The analogue triggers, which are buttons *and* axes.
  ///
  /// A game that wants a threshold reads them here; a game that wants a
  /// proportion reads [PadAxis.triggerLeft]. Racing needs the second and
  /// nothing else in this repository does, which is why both exist.
  static const PadButton triggerLeft = PadButton('trigger.left');

  /// The right analogue trigger read as a button; its proportion is
  /// [PadAxis.triggerRight].
  static const PadButton triggerRight = PadButton('trigger.right');

  /// Pressing a stick down, which is a button and not an axis.
  static const PadButton stickLeftClick = PadButton('stick.left.click');

  /// Pressing the right stick down: Xbox `RS`, PlayStation `R3`.
  static const PadButton stickRightClick = PadButton('stick.right.click');

  /// The right-hand menu button: Xbox Menu, PlayStation Options, Nintendo
  /// `+`.
  static const PadButton start = PadButton('start');

  /// The left-hand menu button: Xbox View, PlayStation Share or Create,
  /// Nintendo `-`.
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
///
/// A class with constants rather than an enum, so a value added in a minor
/// release does not break a `switch` written against it: [name] is what a
/// file or a snapshot writes, and [byName] reads it back.
final class PadAxis {
  const PadAxis._(this.name);

  /// The left stick's horizontal position, from -1 (left) to 1 (right).
  static const PadAxis leftStickX = PadAxis._('leftStickX');

  /// The left stick's vertical position, from -1 (up) to 1 (down).
  static const PadAxis leftStickY = PadAxis._('leftStickY');

  /// The right stick's horizontal position, from -1 (left) to 1 (right).
  static const PadAxis rightStickX = PadAxis._('rightStickX');

  /// The right stick's vertical position, from -1 (up) to 1 (down).
  static const PadAxis rightStickY = PadAxis._('rightStickY');

  /// How far the left trigger is pulled, from nought (rest) to one.
  static const PadAxis triggerLeft = PadAxis._('triggerLeft');

  /// How far the right trigger is pulled, from nought (rest) to one.
  static const PadAxis triggerRight = PadAxis._('triggerRight');

  /// Every value this version names, in declaration order. A later version
  /// appends; nothing is removed or renamed within a major.
  static const List<PadAxis> values = <PadAxis>[
    leftStickX,
    leftStickY,
    rightStickX,
    rightStickY,
    triggerLeft,
    triggerRight,
  ];

  /// The value called [name], or null for a name this version does not know,
  /// which is what a file written by a later version can carry.
  static PadAxis? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name: what a file, a report or a snapshot
  /// writes for this value. Never renamed within a major.
  final String name;

  @override
  String toString() => 'PadAxis.$name';
}
