/// A gamepad in the game layer's own words: its buttons, its axes, what it
/// reads at one moment, and where that reading comes from.
///
/// **Why the game has its own words for a pad.** The device itself is
/// `pad_input`, a package on its own version line below 1.0 that may change
/// its API in any minor. A 1.x package that named `PadButton` or `Gamepad` in
/// its own signatures would pass every such change on to its users without a
/// major of its own. So this library names the pad in types the game owns,
/// and [PadDevice.platform] is the one place the plugin is reached: a change
/// to it is a change here, in a release of this package, and never in a
/// game's code.
library;

import 'package:pad_input/pad_input.dart';

/// One button on a pad, by the stable id a binding file writes.
///
/// **A value class, not an enum, and not a closed set**, for the reason the
/// device's own button type gives: a pad that reports a button this list does
/// not name still has a button, and a binding to it still round-trips. Two
/// buttons are equal by [id].
final class GamePadButton {
  /// The button called [id], the word an `InputSource.pad` source carries.
  const GamePadButton(this.id);

  /// Stable, self-describing, and written to disk in a player's bindings.
  final String id;

  static const GamePadButton faceSouth = GamePadButton('face.south');
  static const GamePadButton faceEast = GamePadButton('face.east');
  static const GamePadButton faceWest = GamePadButton('face.west');
  static const GamePadButton faceNorth = GamePadButton('face.north');

  static const GamePadButton dpadUp = GamePadButton('dpad.up');
  static const GamePadButton dpadDown = GamePadButton('dpad.down');
  static const GamePadButton dpadLeft = GamePadButton('dpad.left');
  static const GamePadButton dpadRight = GamePadButton('dpad.right');

  static const GamePadButton shoulderLeft = GamePadButton('shoulder.left');
  static const GamePadButton shoulderRight = GamePadButton('shoulder.right');

  /// The triggers as buttons. Their travel is [GamePadAxis.triggerLeft] and
  /// [GamePadAxis.triggerRight]; whether that counts as pressed is a
  /// threshold, and `PadInput` keeps its own.
  static const GamePadButton triggerLeft = GamePadButton('trigger.left');
  static const GamePadButton triggerRight = GamePadButton('trigger.right');

  static const GamePadButton stickLeftClick = GamePadButton('stick.left.click');
  static const GamePadButton stickRightClick = GamePadButton(
    'stick.right.click',
  );

  static const GamePadButton start = GamePadButton('start');
  static const GamePadButton back = GamePadButton('back');
  static const GamePadButton guide = GamePadButton('guide');

  /// Every button this version names, for a rebinding screen that lists
  /// them. A later version appends; a pad may still hold one it does not
  /// name.
  static const List<GamePadButton> known = <GamePadButton>[
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
  bool operator ==(Object other) => other is GamePadButton && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'GamePadButton($id)';
}

/// Something on a pad that has a magnitude: a stick's two axes in `[-1, 1]`,
/// Y positive downwards as a screen counts, and a trigger in `[0, 1]`.
///
/// A class with constants rather than an enum, so an axis a later minor adds
/// (a gyro, a touchpad) does not break a `switch` written against it: [name]
/// is what an `InputSource.padAxis` source writes, and [byName] reads it back.
final class GamePadAxis {
  const GamePadAxis._(this.name);

  static const GamePadAxis leftStickX = GamePadAxis._('leftStickX');
  static const GamePadAxis leftStickY = GamePadAxis._('leftStickY');
  static const GamePadAxis rightStickX = GamePadAxis._('rightStickX');
  static const GamePadAxis rightStickY = GamePadAxis._('rightStickY');
  static const GamePadAxis triggerLeft = GamePadAxis._('triggerLeft');
  static const GamePadAxis triggerRight = GamePadAxis._('triggerRight');

  /// Every axis this version names, in declaration order. A later version
  /// appends; nothing is removed or renamed within a major.
  static const List<GamePadAxis> values = <GamePadAxis>[
    leftStickX,
    leftStickY,
    rightStickX,
    rightStickY,
    triggerLeft,
    triggerRight,
  ];

  /// The axis called [name], or null for a name this version does not know.
  static GamePadAxis? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name a binding file writes. Never
  /// renamed within a major.
  final String name;

  @override
  String toString() => 'GamePadAxis.$name';
}

/// What a pad is doing at one moment.
///
/// Mutable and reused, as the device's own snapshot is: a pad is read once a
/// frame, and a reading allocated per frame is garbage per frame.
final class PadReading {
  /// Whether a pad answered. When it did not, nothing else here is said.
  bool isConnected = false;

  final Set<GamePadButton> _down = <GamePadButton>{};
  final Map<GamePadAxis, double> _axes = <GamePadAxis, double>{};

  /// How far [axis] is from rest: `[-1, 1]` for a stick, `[0, 1]` for a
  /// trigger, and 0 for an axis the pad did not report.
  double axis(GamePadAxis axis) => _axes[axis] ?? 0.0;

  /// Whether [button] is held.
  bool down(GamePadButton button) => _down.contains(button);

  /// Every button held, including ones [GamePadButton.known] does not name.
  Iterable<GamePadButton> get held => _down;

  /// Says [axis] reads [value].
  void setAxis(GamePadAxis axis, double value) => _axes[axis] = value;

  /// Says [button] is held, or is not.
  void setDown(GamePadButton button, {required bool down}) =>
      down ? _down.add(button) : _down.remove(button);

  /// Makes this reading say what [other] says.
  void copyFrom(PadReading other) {
    clear();
    isConnected = other.isConnected;
    _down.addAll(other._down);
    _axes.addAll(other._axes);
  }

  /// Every button up and every axis at rest, connected or not as it was.
  void clear() {
    _down.clear();
    _axes.clear();
  }

  /// Back to no pad at all: [clear], and not connected.
  void disconnect() {
    clear();
    isConnected = false;
  }
}

/// Where a `PadInput` reads a pad from.
///
/// **An `abstract base class` a test or a host extends**: a pad that does
/// what a test says, a pad a remote player's packets drive, a recorded pad.
/// [PadDevice.platform] is the controller the platform reports.
abstract base class PadDevice {
  /// A device a subclass describes.
  const PadDevice();

  /// The controller in [slot] (0 is the first) as the platform reports it,
  /// with its dead zones applied.
  ///
  /// Slot 0 is one device for the whole process, as the platform's own first
  /// pad is: two readers of it read the same controller.
  factory PadDevice.platform({int slot = 0}) =>
      _PlatformPad(slot == 0 ? Gamepad.instance : Gamepad(index: slot));

  /// Whether this build can read a pad at all. A build that cannot reads as
  /// a pad that is never connected.
  bool get isSupported => true;

  /// The fraction of a stick's travel that reads as centred. A device that
  /// applies no dead zone answers 0.
  double get stickDeadZone => 0.0;

  /// The fraction of a trigger's travel that reads as at rest.
  double get triggerDeadZone => 0.0;

  /// Sets the dead zones a player chose. A device that applies none, such as
  /// one a test drives, keeps nothing.
  void setDeadZones({required double stick, required double trigger}) {}

  /// Writes what the pad is doing now into [out].
  void read(PadReading out);
}

/// The platform's pad, through `pad_input`, said in the game's words.
final class _PlatformPad extends PadDevice {
  _PlatformPad(this._pad);

  final Gamepad _pad;
  final PadSnapshot _snapshot = PadSnapshot();

  static const List<(GamePadAxis, PadAxis)> _axes = <(GamePadAxis, PadAxis)>[
    (GamePadAxis.leftStickX, PadAxis.leftStickX),
    (GamePadAxis.leftStickY, PadAxis.leftStickY),
    (GamePadAxis.rightStickX, PadAxis.rightStickX),
    (GamePadAxis.rightStickY, PadAxis.rightStickY),
    (GamePadAxis.triggerLeft, PadAxis.triggerLeft),
    (GamePadAxis.triggerRight, PadAxis.triggerRight),
  ];

  @override
  bool get isSupported => _pad.isSupported;

  /// The plugin's own, a fraction of a stick's travel.
  @override
  double get stickDeadZone => _pad.deadzone.stick;

  /// The plugin's own, a fraction of a trigger's travel.
  @override
  double get triggerDeadZone => _pad.deadzone.trigger;

  @override
  void setDeadZones({required double stick, required double trigger}) =>
      _pad.deadzone = Deadzone(stick: stick, trigger: trigger);

  @override
  void read(PadReading out) {
    _pad.read(_snapshot);
    out
      ..clear()
      ..isConnected = _snapshot.isConnected;
    if (!_snapshot.isConnected) return;
    for (final (ours, theirs) in _axes) {
      out.setAxis(ours, _snapshot.axis(theirs));
    }
    for (final button in _snapshot.held) {
      out.setDown(GamePadButton(button.id), down: true);
    }
  }
}
