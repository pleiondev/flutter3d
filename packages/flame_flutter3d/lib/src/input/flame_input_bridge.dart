import 'package:flame/events.dart';
import 'package:flutter/services.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

/// Feeds Flame's own keyboard and drag callbacks into the same
/// [Bindings]/[InputState] pair `flutter3d_game`'s [DesktopInput] and
/// [PadInput] already write into.
///
/// **Reuses their translation rather than inventing a second one.** A
/// rebind screen, a saved binding file and an [InputState] a `flutter3d_sim`
/// `Actor`'s movement reads all assume there is exactly one of each — that a
/// key means one thing regardless of which widget happened to see it first.
/// If this bridge kept its own key-to-action map, a player who rebinds jump
/// in a native `flutter3d_game` menu would find it unchanged the next time
/// they launched the Flame-hosted build of the same game, because two maps
/// disagreeing is indistinguishable from a rebind that silently failed. So
/// this class owns no mapping of its own: it looks a source up in the very
/// same [Bindings] table [DesktopInput] does, and calls the very same
/// [InputState.press]/[InputState.release] it does, for a source Flame
/// happened to notice instead of a raw [Focus] widget.
///
/// **A plain Dart class, not a [Component].** Nothing here draws, ticks, or
/// belongs to a scene graph — it is a pair of callbacks a host component
/// forwards its own Flame events to, the same way [DesktopInput] is a plain
/// class a host `Focus.onKeyEvent` forwards to rather than a widget in its
/// own right.
///
/// ## What this does not do
///
/// **It does not poll a gamepad.** [PadInput] already reads a pad every
/// tick and writes into this same [InputState] through this same
/// [Bindings] table; a Flame-specific pad translator would be a second
/// implementation of exactly that, drifting from the first the moment
/// either one gains a feature the other doesn't. A Flame game that wants
/// pad support constructs a [PadInput] directly, beside this bridge, both
/// pointed at the shared [inputState].
final class FlameInputBridge {
  FlameInputBridge({required this.bindings, required this.inputState});

  /// What each key or pointer button does. The same table a rebinding
  /// screen edits and [DesktopInput]/[PadInput] read, if the host shares
  /// one — see the class doc.
  final Bindings bindings;

  /// The shared state a `flutter3d_sim` `Actor`'s movement, and this
  /// bridge, both read and write.
  final InputState inputState;

  /// Translates a Flame keyboard event into a press or release on
  /// [inputState], matching [DesktopInput.handleKeyEvent]'s own logic.
  ///
  /// Shaped for [KeyboardHandler.onKeyEvent] (`package:flame`), which
  /// returns a `bool` rather than Flutter's [KeyEventResult]: `true` means
  /// "not mine, keep propagating to the next component or the game itself",
  /// `false` means "consumed, stop here" — the opposite polarity of
  /// [KeyEventResult.ignored]/[KeyEventResult.handled], but the same
  /// question. A source this bridge has nothing bound to is left alone so
  /// a Flame game can still use [KeyboardHandler] for its own, unrelated
  /// keys.
  ///
  /// A repeat event is neither a [KeyDownEvent] nor a [KeyUpEvent], so it
  /// falls through both branches below and does nothing — exactly what
  /// [DesktopInput.handleKeyEvent] does, and for the same reason: treating
  /// a repeat as a fresh press would fire an automatic weapon at the
  /// keyboard's repeat rate instead of the weapon's.
  bool onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    final action = bindings[InputSource.key(event.logicalKey.keyId)];
    if (action == null) return true;

    if (event is KeyDownEvent) {
      inputState.press(action);
    } else if (event is KeyUpEvent) {
      inputState.release(action);
    }
    return false;
  }

  /// Adds a Flame drag's movement to [inputState]'s accumulated look delta.
  ///
  /// Reads [DragUpdateEvent.deviceDelta] rather than
  /// [DragUpdateEvent.localDelta]: the local variant is only meaningful
  /// once Flame has delivered the event to a mounted component through its
  /// own hit-testing pipeline, while the device variant is the raw
  /// movement the platform reported and is always safe to read — the same
  /// unscaled, uncaptured number [DesktopInput.drainLook] takes from a
  /// locked pointer. A caller that wants canvas-space movement instead
  /// (rare — view-turning cares about raw motion, not where it happened to
  /// land on screen) can read the event itself and call [InputState.addLook]
  /// directly.
  ///
  /// [InputState.addLook] accumulates rather than assigns, so this can be
  /// called once per drag-update callback exactly as it arrives; whatever
  /// step next calls [InputState.endStep] drains the total and starts the
  /// next one at zero.
  void onDragUpdate(DragUpdateEvent event) {
    final delta = event.deviceDelta;
    inputState.addLook(delta.x, delta.y);
  }
}
