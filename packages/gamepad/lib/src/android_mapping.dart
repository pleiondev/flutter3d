import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'pad_button.dart';
import 'pad_snapshot.dart';

/// The `MotionEvent` axis numbers this package reads.
///
/// Named rather than inlined because three of them are the whole difficulty of
/// Android: see [AndroidPadState] on the triggers and the hat.
abstract final class AndroidAxis {
  static const int x = 0;
  static const int y = 1;
  static const int z = 11;
  static const int rz = 14;
  static const int hatX = 15;
  static const int hatY = 16;
  static const int leftTrigger = 17;
  static const int rightTrigger = 18;
  static const int gas = 22;
  static const int brake = 23;

  /// Everything worth asking a device for, so the native side sends one list
  /// and never has to be edited again when a mapping changes.
  static const List<int> all = <int>[
    x,
    y,
    z,
    rz,
    hatX,
    hatY,
    leftTrigger,
    rightTrigger,
    gas,
    brake,
  ];
}

/// An Android gamepad's state, assembled from the two places Android puts it.
///
/// **Android has no way to ask a gamepad what it is doing.** There is no polling
/// API: input arrives as events aimed at whatever view has focus, and a backend's
/// job is to remember the last thing each control said. So this holds a mirror
/// and [fill] copies it — which keeps [GamepadPlatform.read] synchronous, as a
/// caller reading it inside a frame needs, while the freshness is the same one a
/// poll would have given.
///
/// ## Sticks come from native code and buttons come from Flutter
///
/// Not a compromise — it is where Android actually puts them.
///
/// **Buttons already arrive in Dart.** Android delivers a gamepad's buttons as
/// `KeyEvent`s, and Flutter's Android embedding maps their key codes to
/// `LogicalKeyboardKey.gameButtonA` and its neighbours before handing them to the
/// framework. Native code to re-catch what the framework already delivers would
/// be a second source of truth for the same event, and the two would disagree
/// the first time one of them was wrong.
///
/// **Axes do not.** Flutter's Android embedding turns pointer and scroll motion
/// into `PointerEvent`s and drops the rest, so a joystick's `MotionEvent` never
/// reaches Dart. That is the one thing the plugin exists for.
///
/// ## The two traps, both of which are a device disagreeing with another device
///
/// **A trigger is on one of two axes.** Some drivers report `AXIS_LTRIGGER` and
/// `AXIS_RTRIGGER`; others report `AXIS_BRAKE` and `AXIS_GAS` — the same physical
/// control under a steering wheel's name — and a few report neither, offering
/// only the digital `L2`/`R2` buttons. Guessing wrongly means a trigger that
/// never moves, so the axis is **chosen per device** from what it says it has.
///
/// **A d-pad is a hat or it is arrow keys.** Most report `AXIS_HAT_X`/`AXIS_HAT_Y`
/// at -1, 0 or 1. Those that do not send `KEYCODE_DPAD_*`, which Flutter maps to
/// the arrow keys — indistinguishable in Dart from a keyboard's arrows, because a
/// `KeyEvent` does not say which device it came from. So a hat is read as a d-pad
/// and arrow keys are deliberately **not**: on such a pad the d-pad works as
/// arrow keys, which every game here already binds to walking, and the honest
/// alternative — claiming `pad:dpad.up` for a key that might be a keyboard's —
/// would write a lie into the player's config file.
final class AndroidPadState {
  /// Which controls answer through Flutter's keyboard, by logical key id.
  ///
  /// `final` rather than `const` because a `LogicalKeyboardKey`'s id is not a
  /// constant expression. Positions, as everywhere in this package: Android's
  /// `BUTTON_A` is the lower face button, `BUTTON_B` the right one, and the
  /// names below are what the hardware is rather than what is printed on it.
  static final Map<int, PadButton> buttonsByKey = <int, PadButton>{
    LogicalKeyboardKey.gameButtonA.keyId: PadButton.faceSouth,
    LogicalKeyboardKey.gameButtonB.keyId: PadButton.faceEast,
    LogicalKeyboardKey.gameButtonX.keyId: PadButton.faceWest,
    LogicalKeyboardKey.gameButtonY.keyId: PadButton.faceNorth,
    LogicalKeyboardKey.gameButtonLeft1.keyId: PadButton.shoulderLeft,
    LogicalKeyboardKey.gameButtonRight1.keyId: PadButton.shoulderRight,
    LogicalKeyboardKey.gameButtonLeft2.keyId: PadButton.triggerLeft,
    LogicalKeyboardKey.gameButtonRight2.keyId: PadButton.triggerRight,
    LogicalKeyboardKey.gameButtonThumbLeft.keyId: PadButton.stickLeftClick,
    LogicalKeyboardKey.gameButtonThumbRight.keyId: PadButton.stickRightClick,
    LogicalKeyboardKey.gameButtonStart.keyId: PadButton.start,
    LogicalKeyboardKey.gameButtonSelect.keyId: PadButton.back,
    LogicalKeyboardKey.gameButtonMode.keyId: PadButton.guide,
  };

  int? _deviceId;
  int? _leftTriggerAxis;
  int? _rightTriggerAxis;

  final Map<int, double> _axes = <int, double>{};
  final Set<String> _keysDown = <String>{};

  bool get connected => _deviceId != null;

  /// The device this is mirroring, and which axes it admits to having.
  void connect({required int deviceId, required Iterable<int> axes}) {
    if (deviceId != _deviceId) {
      // A different pad: nothing carried over from the last one, whose stick may
      // have been half over when it was unplugged.
      _axes.clear();
      _keysDown.clear();
    }
    _deviceId = deviceId;
    final has = axes.toSet();
    // Preferred first, the wheel's names second. Absent both, the triggers are
    // whatever the digital buttons say and nothing else.
    _leftTriggerAxis = has.contains(AndroidAxis.leftTrigger)
        ? AndroidAxis.leftTrigger
        : (has.contains(AndroidAxis.brake) ? AndroidAxis.brake : null);
    _rightTriggerAxis = has.contains(AndroidAxis.rightTrigger)
        ? AndroidAxis.rightTrigger
        : (has.contains(AndroidAxis.gas) ? AndroidAxis.gas : null);
  }

  void disconnect() {
    _deviceId = null;
    _axes.clear();
    _keysDown.clear();
  }

  /// Everything the pad is holding, released without disconnecting it.
  ///
  /// For the application going to the background, which the native side reports:
  /// the controller is still there, the player is not, and a stick left half over
  /// would keep walking behind whatever is now on screen.
  void relax() {
    _axes.clear();
    _keysDown.clear();
  }

  /// Takes one `MotionEvent`, as `[deviceId, axis, value, axis, value, …]`.
  ///
  /// Self-describing so the native side never needs to know what this file maps:
  /// it sends every axis the device has and this decides which of them matter.
  void noteMotion(Float64List sample) {
    if (sample.isEmpty) return;
    final deviceId = sample[0].toInt();
    // A second pad moving its stick is not this pad's business. Reading it would
    // make two controllers fight over one snapshot, which is the bug the
    // "one pad at a time" decision exists to avoid rather than to hide.
    if (deviceId != _deviceId) return;
    for (var i = 1; i + 1 < sample.length; i += 2) {
      _axes[sample[i].toInt()] = sample[i + 1];
    }
  }

  /// Takes a key event, returning whether it belonged to a gamepad.
  ///
  /// False for everything else, so a handler wired into Flutter's keyboard can
  /// pass a keyboard's keys straight on to whatever wanted them.
  bool noteKey(KeyEvent event) {
    final button = buttonsByKey[event.logicalKey.keyId];
    if (button == null) return false;
    // A repeat is neither down nor up: the button is already held, and the state
    // it would set is the state it is in.
    if (event is KeyDownEvent) {
      _keysDown.add(button.id);
    } else if (event is KeyUpEvent) {
      _keysDown.remove(button.id);
    }
    return true;
  }

  /// Writes the mirror into [out].
  void fill(PadSnapshot out) {
    if (!connected) {
      out.disconnect();
      return;
    }
    out.clear();
    out.connected = true;

    out
      ..setAxis(PadAxis.leftStickX, _axes[AndroidAxis.x] ?? 0.0)
      ..setAxis(PadAxis.leftStickY, _axes[AndroidAxis.y] ?? 0.0)
      ..setAxis(PadAxis.rightStickX, _axes[AndroidAxis.z] ?? 0.0)
      ..setAxis(PadAxis.rightStickY, _axes[AndroidAxis.rz] ?? 0.0);

    for (final button in PadButton.known) {
      final down = _keysDown.contains(button.id);
      if (down) out.setDown(button, down: true);
    }

    _fillTrigger(out, PadButton.triggerLeft, PadAxis.triggerLeft,
        _leftTriggerAxis);
    _fillTrigger(out, PadButton.triggerRight, PadAxis.triggerRight,
        _rightTriggerAxis);

    _fillHat(out, AndroidAxis.hatX, PadButton.dpadLeft, PadButton.dpadRight);
    _fillHat(out, AndroidAxis.hatY, PadButton.dpadUp, PadButton.dpadDown);
  }

  void _fillTrigger(
    PadSnapshot out,
    PadButton button,
    PadAxis axis,
    int? androidAxis,
  ) {
    // No axis on this device: the button is all there is, so its bit becomes the
    // travel. A game reading the proportion gets nought or one, which is the
    // truth about what the hardware reported rather than a smoothed guess.
    final value = androidAxis == null
        ? (_keysDown.contains(button.id) ? 1.0 : 0.0)
        : (_axes[androidAxis] ?? 0.0);
    out
      ..setAxis(axis, value)
      ..setDown(button, down: _keysDown.contains(button.id), pressure: value);
  }

  /// Turns one hat axis into the two buttons it stands for.
  ///
  /// The threshold is a half rather than an exact ±1 because a few drivers report
  /// a hat as a continuous axis, and one that stopped at 0.9 would be a d-pad
  /// that does nothing on that hardware.
  void _fillHat(
    PadSnapshot out,
    int androidAxis,
    PadButton negative,
    PadButton positive,
  ) {
    final value = _axes[androidAxis];
    if (value == null) return;
    if (value <= -0.5) out.setDown(negative, down: true);
    if (value >= 0.5) out.setDown(positive, down: true);
  }
}
