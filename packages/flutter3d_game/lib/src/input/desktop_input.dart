import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:mouse_capture/mouse_capture.dart';
import 'package:vector_math/vector_math.dart';

import 'game_action.dart';
import 'input_state.dart';

/// Feeds an [InputState] from a keyboard and a captured mouse.
///
/// The only file in `lib/src/game/` that knows what a key is. Everything below
/// it sees [GameAction] and a movement axis, which is what makes the same
/// simulation run under touch controls without a branch.
final class DesktopInput {
  DesktopInput({
    required this.state,
    MouseCapture? capture,
    Map<LogicalKeyboardKey, GameAction>? bindings,
  })  : capture = capture ?? MouseCapture.instance,
        bindings = bindings ?? Map.of(defaultBindings) {
    _stateSubscription = this.capture.onStateChanged.listen(_onCaptureChanged);
  }

  /// WASD and the usual neighbours.
  ///
  /// Arrow keys are bound too — not for the player, who will use WASD, but
  /// because a laptop without a numeric keypad in the middle of a demo is a
  /// worse time to discover the gap.
  static final Map<LogicalKeyboardKey, GameAction> defaultBindings =
      <LogicalKeyboardKey, GameAction>{
    LogicalKeyboardKey.keyW: GameAction.moveForward,
    LogicalKeyboardKey.keyS: GameAction.moveBack,
    LogicalKeyboardKey.keyA: GameAction.moveLeft,
    LogicalKeyboardKey.keyD: GameAction.moveRight,
    LogicalKeyboardKey.arrowUp: GameAction.moveForward,
    LogicalKeyboardKey.arrowDown: GameAction.moveBack,
    LogicalKeyboardKey.arrowLeft: GameAction.moveLeft,
    LogicalKeyboardKey.arrowRight: GameAction.moveRight,
    LogicalKeyboardKey.space: GameAction.jump,
    LogicalKeyboardKey.shiftLeft: GameAction.sprint,
    LogicalKeyboardKey.shiftRight: GameAction.sprint,
    LogicalKeyboardKey.keyE: GameAction.use,
    LogicalKeyboardKey.keyF: GameAction.use,
  };

  static final Map<LogicalKeyboardKey, int> _weaponKeys =
      <LogicalKeyboardKey, int>{
    LogicalKeyboardKey.digit1: 0,
    LogicalKeyboardKey.digit2: 1,
    LogicalKeyboardKey.digit3: 2,
    LogicalKeyboardKey.digit4: 3,
  };

  final InputState state;
  final MouseCapture capture;
  final Map<LogicalKeyboardKey, GameAction> bindings;

  late final StreamSubscription<CaptureState> _stateSubscription;

  bool get isCaptured => capture.isCaptured;

  /// Handles a key event, returning whether it was consumed.
  ///
  /// Shaped for [Focus.onKeyEvent], which is the only way to see raw keys
  /// alongside the rest of a Flutter widget tree.
  KeyEventResult handleKeyEvent(KeyEvent event) {
    // Escape gives the pointer back. Handled here rather than in the plugin
    // because a key is an application concern, and a plugin that stole Escape
    // would be wrong for every caller that wanted it for something else.
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        capture.isCaptured) {
      release();
      return KeyEventResult.handled;
    }

    final weapon = _weaponKeys[event.logicalKey];
    if (weapon != null) {
      if (event is KeyDownEvent) state.requestWeapon(weapon);
      return KeyEventResult.handled;
    }

    final action = bindings[event.logicalKey];
    if (action == null) return KeyEventResult.ignored;

    if (event is KeyDownEvent) {
      state.press(action);
    } else if (event is KeyUpEvent) {
      state.release(action);
    }
    // A repeat is neither: the key is already down, and treating the repeat as
    // a fresh press would fire an automatic weapon at the keyboard's repeat
    // rate instead of the weapon's.
    return KeyEventResult.handled;
  }

  void pressPointer() => state.press(GameAction.fire);

  void releasePointer() => state.release(GameAction.fire);

  /// Takes the mouse motion accumulated since the last call.
  ///
  /// Matches the signature [GameLoop] wants, so the loop needs to know nothing
  /// about how the pointer is captured.
  void drainLook(Vector2 out) {
    final delta = capture.takeDelta();
    out.setValues(delta.dx, delta.dy);
  }

  Future<void> enterFirstPerson() => capture.capture();

  Future<void> release() => capture.release();

  void _onCaptureChanged(CaptureState captureState) {
    if (captureState == CaptureState.released) {
      // A key that was down when the window went away never sends its key-up,
      // so without this the player keeps walking forward after alt-tabbing.
      state.clear();
    }
  }

  Future<void> dispose() => _stateSubscription.cancel();
}
