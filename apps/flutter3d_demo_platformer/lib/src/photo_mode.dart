import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

import 'lens.dart';

/// This game's photo mode — `N8`: the world stopped, a camera to fly, a
/// filter to pick and a picture larger than the window.
///
/// The parts are the engine's: [PhotoCamera] keeps the camera in the level,
/// [PhotoFilter] is a change to the composite's look, and `takePhoto` draws,
/// encodes and saves. What is here is only what is this game's: which keys
/// do what, and how the camera meets this game's lens.
///
/// **The world's own input, read rather than stepped.** The loop is paused,
/// so nothing drains [InputState]; the keys the player already has for
/// running fly the camera instead, read as held each frame, and the jump and
/// the drop take it up and down.
final class PhotoMode {
  PhotoCamera? _camera;
  int _filter = 0;

  /// Whether the world is stopped for a picture.
  bool get active => _camera != null;

  /// Whether a picture is being drawn; the keys wait for it, and the game
  /// stops redrawing its surface — see `capturePhoto`.
  bool busy = false;

  /// The last thing a picture had to say: where it went, or why not.
  String? said;

  PhotoFilter get filter => PhotoFilter.all[_filter];

  /// Stops the world and takes the camera from where the game had it.
  void enter({
    required CollisionWorld world,
    required Vector3 eye,
    required Vector3 target,
    required Vector3 anchor,
    required double fieldOfView,
  }) {
    _camera = PhotoCamera(world: world)
      ..begin(
        eye: eye,
        target: target,
        anchor: anchor,
        fieldOfView: fieldOfView,
      );
    said = null;
  }

  void leave() => _camera = null;

  /// One frame of flying.
  void fly(InputState input, Vector2 look, double dt) {
    final camera = _camera;
    if (camera == null || busy) return;
    camera.look(-look.x * _sensitivity, -look.y * _sensitivity);
    double axis(GameAction plus, GameAction minus) =>
        (input.held(plus) ? 1.0 : 0.0) - (input.held(minus) ? 1.0 : 0.0);
    final intent = Vector3(
      axis(GameAction.moveRight, GameAction.moveLeft),
      axis(GameAction.jump, PlatformerActions.dropThrough),
      axis(GameAction.moveForward, GameAction.moveBack),
    );
    // Sprint is a faster camera, as it is a faster runner.
    camera.fly(input.held(GameAction.sprint) ? intent * 3.0 : intent, dt);
  }

  /// The follow camera's own mouse sensitivity, so the view turns at the
  /// rate the player's hand already knows.
  static const double _sensitivity = 0.0035;

  /// Puts the photo camera on the scene's [node].
  void applyTo(CameraNode node) {
    final camera = _camera;
    if (camera == null) return;
    node
      ..setPositionFrom(camera.eye)
      ..lookAt(camera.target, up: camera.up)
      ..projection = Lens.base.copyWith(fovYRadians: camera.fieldOfView);
  }

  /// The game's look with the chosen filter on it.
  LookSettings look(LookSettings game) => filter.applyTo(game);

  /// The keys photo mode owns while it is open, or null for one it does not.
  ///
  /// [onCapture] is asked for a picture at a multiple of the window's size.
  KeyEventResult? key(KeyEvent event, {required void Function(int) onCapture}) {
    final camera = _camera;
    if (camera == null || event is KeyUpEvent) return null;
    if (busy) return KeyEventResult.handled;
    final repeatable = event is KeyDownEvent || event is KeyRepeatEvent;
    switch (event.logicalKey) {
      // Brackets rather than the arrows, which already fly the camera.
      case LogicalKeyboardKey.bracketRight when event is KeyDownEvent:
        _filter = (_filter + 1) % PhotoFilter.all.length;
      case LogicalKeyboardKey.bracketLeft when event is KeyDownEvent:
        _filter = (_filter - 1) % PhotoFilter.all.length;
      case LogicalKeyboardKey.comma when repeatable:
        camera.tilt(-0.05);
      case LogicalKeyboardKey.period when repeatable:
        camera.tilt(0.05);
      case LogicalKeyboardKey.equal when repeatable:
        camera.zoom(1.1);
      case LogicalKeyboardKey.minus when repeatable:
        camera.zoom(1.0 / 1.1);
      case LogicalKeyboardKey.enter when event is KeyDownEvent:
        onCapture(HardwareKeyboard.instance.isShiftPressed ? 4 : 2);
      default:
        return null;
    }
    return KeyEventResult.handled;
  }
}

/// The strip along the bottom of the screen in photo mode: the filter, the
/// keys, and the last picture's sentence.
class PhotoBar extends StatelessWidget {
  const PhotoBar({required this.mode, super.key});

  final PhotoMode mode;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white, fontSize: 14),
          textAlign: TextAlign.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                mode.busy
                    ? 'Taking the picture…'
                    : 'Photo mode · filter: ${mode.filter.name}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const Text(
                'WASD fly · Space/C up and down · Shift faster · [ ] filter · '
                ', . tilt · − = zoom · Enter 2× · Shift+Enter 4× · P back',
              ),
              if (mode.said case final said?) Text(said),
            ],
          ),
        ),
      ),
    ),
  );
}
