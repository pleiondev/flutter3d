import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:mouse_capture/mouse_capture.dart';
import 'package:vector_math/vector_math.dart';

import 'game_action.dart';
import 'input_state.dart';

/// Feeds an [InputState] from a keyboard and a captured mouse.
///
/// The only file here that knows what a key is. Everything below it sees
/// [GameAction] and a movement axis, which is what makes the same simulation
/// run under touch controls without a branch.
///
/// What it does **not** know is what the game is. It used to: the pointer was
/// wired to `GameAction.fire`, the number row selected weapons, and capturing
/// the mouse was called `enterFirstPerson`. All three were true of the one game
/// that existed and false of the next one, so all three are arguments now.
final class DesktopInput {
  DesktopInput({
    required this.state,
    MouseCapture? capture,
    Map<LogicalKeyboardKey, GameAction>? bindings,
    Map<LogicalKeyboardKey, int>? slotKeys,
  })  : capture = capture ?? MouseCapture.instance,
        bindings = bindings ?? Map.of(defaultBindings),
        slotKeys = slotKeys ?? Map.of(defaultSlotKeys) {
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

  /// The number row, for whatever the game numbers.
  ///
  /// Weapons in a shooter, and this map was called `_weaponKeys` and was
  /// private, so a game with items instead of weapons could not have them.
  static final Map<LogicalKeyboardKey, int> defaultSlotKeys =
      <LogicalKeyboardKey, int>{
    LogicalKeyboardKey.digit1: 0,
    LogicalKeyboardKey.digit2: 1,
    LogicalKeyboardKey.digit3: 2,
    LogicalKeyboardKey.digit4: 3,
  };

  final InputState state;
  final MouseCapture capture;
  final Map<LogicalKeyboardKey, GameAction> bindings;
  final Map<LogicalKeyboardKey, int> slotKeys;

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

    final slot = slotKeys[event.logicalKey];
    if (slot != null) {
      if (event is KeyDownEvent) state.requestSlot(slot);
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

  /// Presses whatever the game has decided the pointer means.
  ///
  /// The action is an argument because it used to be `GameAction.fire`, written
  /// into the engine. A platformer's mouse button grabs a ledge, a strategy
  /// game's selects, and neither of them fires anything.
  void pressPointer(GameAction action) => state.press(action);

  void releasePointer(GameAction action) => state.release(action);

  /// Takes the mouse motion accumulated since the last call.
  ///
  /// Matches the signature [GameLoop] wants, so the loop needs to know nothing
  /// about how the pointer is captured.
  void drainLook(Vector2 out) {
    final delta = capture.takeDelta();
    out.setValues(delta.dx, delta.dy);
  }

  /// Takes the pointer, so the mouse reports motion instead of a cursor.
  ///
  /// Was `enterFirstPerson`, which a third-person platformer wanting exactly
  /// this behaviour would have had to call anyway, wondering what it had agreed
  /// to. What is being asked for is the capture, not a camera.
  Future<void> captureMouse() => capture.capture();

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
