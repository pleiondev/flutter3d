import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:pointer_lock/pointer_lock.dart';
import 'package:vector_math/vector_math.dart';

import 'action_input.dart';
import 'action_map.dart';
import 'bindings.dart' show InputSource, SlotActions;
import 'pad_actions.dart';

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
  /// A keyboard reading [actions]: its buttons, its composites on keys, and
  /// the `pointer:motion` look binding that shapes [drainLook]. Without one,
  /// a map holding only the keyboard's defaults — see [addDefaultsTo].
  DesktopInput({required this.state, PointerLock? capture, ActionMap? actions})
    : capture = capture ?? PointerLock.instance,
      actions = actions ?? addDefaultsTo(ActionMap(actions: ActionSet.common)) {
    _actionInput = ActionInput(state: state, map: this.actions);
    _stateSubscription = this.capture.onStateChanged.listen(_onCaptureChanged);
  }

  /// WASD and the rest as an [ActionMap] over [set] — the keyboard's
  /// defaults ([addDefaultsTo]) and the pad's, with the mouse's motion bound
  /// to looking so a settings screen has a sensitivity and an invert to turn.
  ///
  /// [set] is [ActionSet.common] for a game with nothing of its own, or a
  /// genre's set; its own actions are the caller's to bind.
  static ActionMap defaultActionMap([ActionSet set = ActionSet.common]) =>
      PadInput.addDefaultsTo(
        addDefaultsTo(
          ActionMap(
            actions: set,
            axes: const <ActionBinding>[
              DualAxisBinding(DualAxisAction.look, InputSource.pointerMotion),
            ],
          ),
        ),
      );

  /// Adds WASD and the usual neighbours to [map]'s buttons and returns it.
  ///
  /// Arrow keys are bound too — not for the player, who will use WASD, but
  /// because a laptop without a numeric keypad in the middle of a demo is a
  /// worse time to discover the gap.
  ///
  /// Added to a map the caller made rather than kept in a constant, because
  /// the table is mutable and is what a rebinding screen edits: handing every
  /// caller the same object means the first player to rebind anything rebinds
  /// it for the menu, the second window and the next level too.
  static ActionMap addDefaultsTo(ActionMap map) {
    map.buttons
      ..bind(
        InputSource.key(LogicalKeyboardKey.keyW.keyId),
        GameAction.moveForward,
      )
      ..bind(
        InputSource.key(LogicalKeyboardKey.keyS.keyId),
        GameAction.moveBack,
      )
      ..bind(
        InputSource.key(LogicalKeyboardKey.keyA.keyId),
        GameAction.moveLeft,
      )
      ..bind(
        InputSource.key(LogicalKeyboardKey.keyD.keyId),
        GameAction.moveRight,
      )
      ..bind(
        InputSource.key(LogicalKeyboardKey.arrowUp.keyId),
        GameAction.moveForward,
      )
      ..bind(
        InputSource.key(LogicalKeyboardKey.arrowDown.keyId),
        GameAction.moveBack,
      )
      ..bind(
        InputSource.key(LogicalKeyboardKey.arrowLeft.keyId),
        GameAction.moveLeft,
      )
      ..bind(
        InputSource.key(LogicalKeyboardKey.arrowRight.keyId),
        GameAction.moveRight,
      )
      ..bind(InputSource.key(LogicalKeyboardKey.space.keyId), GameAction.jump)
      ..bind(
        InputSource.key(LogicalKeyboardKey.shiftLeft.keyId),
        GameAction.sprint,
      )
      ..bind(
        InputSource.key(LogicalKeyboardKey.shiftRight.keyId),
        GameAction.sprint,
      )
      ..bind(InputSource.key(LogicalKeyboardKey.keyE.keyId), GameAction.use)
      ..bind(InputSource.key(LogicalKeyboardKey.keyF.keyId), GameAction.use);
    // The number row picks whatever the game numbers — weapons in a shooter,
    // blocks in a hotbar — as plain actions a player can move.
    addSlotsTo(map, const <LogicalKeyboardKey>[
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
    ]);
    return map;
  }

  /// Binds each of [keys] to the slot of its place in the list — the first
  /// to slot nought — and returns [map]. See [SlotActions].
  static ActionMap addSlotsTo(ActionMap map, List<LogicalKeyboardKey> keys) {
    for (final (index, key) in keys.indexed) {
      map.buttons.bind(InputSource.key(key.keyId), SlotActions.of(index));
    }
    return map;
  }

  final InputState state;
  final PointerLock capture;

  /// The action map this keyboard reads. Mutable, and saved by the
  /// application: see [ActionMap.toJson]. The same object the pad and the
  /// settings screen hold, so a rebinding takes effect on the next key press.
  final ActionMap actions;

  late final ActionInput _actionInput;

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
      releaseMouse();
      return KeyEventResult.handled;
    }

    final source = InputSource.key(event.logicalKey.keyId);
    final routed = _route(source, event);
    final action = actions.buttons[source];
    if (action == null) {
      return routed ? KeyEventResult.handled : KeyEventResult.ignored;
    }

    // A slot is picked on the press and never held.
    if (SlotActions.indexOf(action) case final int slot) {
      if (event is KeyDownEvent) state.requestSlot(slot);
      return KeyEventResult.handled;
    }

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

  /// Mouse [button] went down, read through the bindings: what
  /// `pointer:<button>` is bound to is pressed, and a composite that uses it
  /// hears it. Returns whether anything was bound to it.
  ///
  /// The rebindable way in, beside [pressPointer], which takes the action
  /// itself and so cannot be moved by a player.
  bool pointerDown(int button) => _pointer(button, down: true);

  bool pointerUp(int button) => _pointer(button, down: false);

  bool _pointer(int button, {required bool down}) {
    final source = InputSource.pointer(button);
    final input = _actionInput;
    final routed = input.routes(source);
    if (routed) down ? input.sourceDown(source) : input.sourceUp(source);
    final action = actions.buttons[source];
    if (action == null) return routed;
    down ? state.press(action) : state.release(action);
    return true;
  }

  /// Hands a key's edge to the action map's composites, if any uses it.
  bool _route(InputSource source, KeyEvent event) {
    final input = _actionInput;
    if (!input.routes(source)) return false;
    if (event is KeyDownEvent) input.sourceDown(source);
    if (event is KeyUpEvent) input.sourceUp(source);
    return true;
  }

  /// Takes the mouse motion accumulated since the last call.
  ///
  /// Matches the signature [EngineLoop] wants, so the loop needs to know nothing
  /// about how the pointer is captured.
  ///
  /// **Assigns**, where [PadInput.drainLook] adds. `EngineLoop` takes one
  /// callback, so a game with both devices calls this one first and lets the pad
  /// add its share on top.
  void drainLook(Vector2 out) {
    final delta = capture.drainDelta();
    final (x, y) = _actionInput.shapeDelta(
      DualAxisAction.look,
      InputSource.pointerMotion,
      delta.dx,
      delta.dy,
    );
    out.setValues(x, y);
  }

  /// Takes the pointer, so the mouse reports motion instead of a cursor.
  ///
  /// Was `enterFirstPerson`, which a third-person platformer wanting exactly
  /// this behaviour would have had to call anyway, wondering what it had agreed
  /// to. What is being asked for is the capture, not a camera.
  Future<void> captureMouse() => capture.capture();

  Future<void> releaseMouse() => capture.release();

  void _onCaptureChanged(CaptureState captureState) {
    if (captureState == CaptureState.released) {
      // A key that was down when the window went away never sends its key-up,
      // so without this the player keeps walking forward after alt-tabbing.
      state.clear();
      _actionInput.letGo();
    }
  }

  Future<void> dispose() => _stateSubscription.cancel();
}
