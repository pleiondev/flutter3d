import 'package:flutter/services.dart';
import 'package:flutter3d_camera/flutter3d_camera.dart' show PhotoCamera;
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

/// How a game's own controls fly the photo camera while the run is stopped.
///
/// **Read, never stepped.** Photo mode holds the loop, so nothing drains the
/// game's `InputState` and no step sees a key. A control reads what is held
/// this frame and moves [PhotoCamera] by it, and nothing of it reaches the
/// run: a picture taken mid-fight is the fight, held.
///
/// Two ship here: [ActionPhotoControls], for a game whose walking keys are
/// actions and whose mouse turns the head, and [KeyPhotoControls], for one
/// that reads the keyboard directly. A game with a third way extends this.
///
/// `base`, so a member added later arrives with a default.
abstract base class PhotoControls {
  const PhotoControls();

  /// One frame: turns and flies [camera] by what is held now. [input] and
  /// [look] are what the game hands `PhotoMode.fly`; a control that needs
  /// neither ignores them.
  void steer(PhotoCamera camera, double dt, {InputState? input, Vector2? look});

  /// How much faster the camera flies while the "faster" control is held,
  /// as a walk is faster under sprint. A unitless multiplier on the speed.
  static const double fastFactor = 3.0;
}

/// The game's own actions fly the camera, and the mouse turns it.
///
/// The walking actions move it along its view and across it; [up] and
/// [down] take it up and down; [fast] makes it [PhotoControls.fastFactor]
/// times faster. The look, in pixels, turns it by [sensitivity] radians a
/// pixel, the game's own, so the view turns at the rate the hand knows.
final class ActionPhotoControls extends PhotoControls {
  const ActionPhotoControls({
    required this.up,
    required this.down,
    required this.sensitivity,
    this.forward = GameAction.moveForward,
    this.back = GameAction.moveBack,
    this.left = GameAction.moveLeft,
    this.right = GameAction.moveRight,
    this.fast = GameAction.sprint,
  });

  final GameAction up;
  final GameAction down;
  final GameAction forward;
  final GameAction back;
  final GameAction left;
  final GameAction right;
  final GameAction fast;

  /// Radians the camera turns for a pixel of [look].
  final double sensitivity;

  @override
  void steer(
    PhotoCamera camera,
    double dt, {
    InputState? input,
    Vector2? look,
  }) {
    if (look != null) {
      camera.look(-look.x * sensitivity, -look.y * sensitivity);
    }
    if (input == null) return;
    double axis(GameAction plus, GameAction minus) =>
        (input.held(plus) ? 1.0 : 0.0) - (input.held(minus) ? 1.0 : 0.0);
    final intent = Vector3(
      axis(right, left),
      axis(up, down),
      axis(forward, back),
    );
    camera.fly(
      input.held(fast) ? intent * PhotoControls.fastFactor : intent,
      dt,
    );
  }
}

/// The keyboard, read as held each frame: WASD fly, [up] and [down] take the
/// camera up and down, Shift is faster, and — when [turnRate] is given — the
/// arrows turn it at that many radians a second.
///
/// For a game that never takes the pointer, or one whose loop is paused so
/// its `InputState` is not stepped.
final class KeyPhotoControls extends PhotoControls {
  const KeyPhotoControls({required this.up, required this.down, this.turnRate});

  final LogicalKeyboardKey up;
  final LogicalKeyboardKey down;

  /// Radians a second the arrows turn the camera, or null when they do not
  /// — a drag turns it instead, through `PhotoMode.turn`.
  final double? turnRate;

  @override
  void steer(
    PhotoCamera camera,
    double dt, {
    InputState? input,
    Vector2? look,
  }) {
    final held = HardwareKeyboard.instance.logicalKeysPressed;
    double axis(LogicalKeyboardKey plus, LogicalKeyboardKey minus) =>
        (held.contains(plus) ? 1.0 : 0.0) - (held.contains(minus) ? 1.0 : 0.0);
    if (turnRate case final rate?) {
      camera.look(
        axis(LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowRight) *
            rate *
            dt,
        axis(LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowDown) *
            rate *
            dt,
      );
    }
    final intent = Vector3(
      axis(LogicalKeyboardKey.keyD, LogicalKeyboardKey.keyA),
      axis(up, down),
      axis(LogicalKeyboardKey.keyW, LogicalKeyboardKey.keyS),
    );
    final fast =
        held.contains(LogicalKeyboardKey.shiftLeft) ||
        held.contains(LogicalKeyboardKey.shiftRight);
    camera.fly(fast ? intent * PhotoControls.fastFactor : intent, dt);
  }
}
