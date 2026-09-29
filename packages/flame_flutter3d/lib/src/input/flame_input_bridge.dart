import 'dart:async' show scheduleMicrotask;

import 'package:flame/components.dart'
    show Component, JoystickComponent, PositionComponent, Vector2;
import 'package:flame/events.dart';
import 'package:flame/input.dart' show ButtonComponent;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart'
    show
        AppLifecycleListener,
        AppLifecycleState,
        KeyEventResult,
        WidgetsBinding;
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import '../host/bridge_priority.dart';
import '../host/has_fixed_step.dart';

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

  /// [onKeyEvent] for a game rather than a component: the same translation,
  /// answered in the [KeyEventResult] that `KeyboardEvents.onKeyEvent` on a
  /// `FlameGame` returns.
  ///
  /// The two Flame hooks ask the same question with opposite answers: a
  /// component's `true` means "keep propagating", a game's
  /// [KeyEventResult.handled] means "stop". Every game that forwarded to
  /// [onKeyEvent] wrote the flip itself, and getting it backwards swallows
  /// every key the bridge has nothing bound to.
  KeyEventResult onGameKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) => onKeyEvent(event, keysPressed)
      ? KeyEventResult.ignored
      : KeyEventResult.handled;

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

  /// A component that writes [stick]'s deflection into [inputState] every
  /// frame, through [InputState.setStickAxis], the call a gamepad's stick
  /// goes through: [InputState.moveAxis] then adds it to whatever keys are
  /// held, and nothing reading the axis learns where it came from. Add it
  /// to the game beside the stick.
  ///
  /// **Screen-down becomes backwards.** Flame's stick reports down the
  /// screen as positive `y`; the move axis calls forward positive, as a key
  /// bound to [GameAction.moveForward] does. Every bridged game with a stick
  /// wrote the same negation by hand.
  ///
  /// **At rest it says nothing.** A deflection inside [deadZone], a
  /// fraction of the knob's reach, counts as the stick at rest, and a stick
  /// at rest writes its zero once, when it comes back, rather than every
  /// frame: a pad's stick run beside it, as the class doc suggests, was
  /// written over with zero every frame the touch stick was not held.
  Component followJoystick(JoystickComponent stick, {double deadZone = 0.0}) =>
      _JoystickFeed(stick, inputState, deadZone);

  /// A component that closes [inputState]'s step after everything that reads
  /// it: what a game called by hand as the last line of its `update`, and a
  /// game that forgot to call saw a key it pressed once reported as pressed
  /// on every frame after. Add it once.
  ///
  /// In a `HasFixedStep` game the step it closes is the fixed step, after
  /// each; otherwise the frame. A game without `HasFixedStep` whose
  /// `ActorSystemComponent` counts its own steps reads input by the frame.
  Component stepEnd() => _InputStepEnd(inputState);

  /// A layer over the canvas that follows the pointer and turns a tap into
  /// [press]: [PointerTrack.aim] is where the pointer is, in logical pixels,
  /// while it is over the game, and a tap holds [press] down for as long as
  /// the finger or the button is. Taps go on to whatever else in Flame is
  /// under them. For aiming a turret or a crosshair; put the aim through a
  /// `BridgeProjector` to find it on the plane.
  PointerTrack pointer({GameAction? press}) =>
      PointerTrack._(inputState, press);

  /// A layer over the canvas that turns a swipe into a single press of the
  /// action for its direction: longer across than [minDistance] logical
  /// pixels, and mostly one way. For a frog that hops.
  SwipeInput swipes({
    GameAction? up,
    GameAction? down,
    GameAction? left,
    GameAction? right,
    double minDistance = 40.0,
  }) => SwipeInput._(inputState, up, down, left, right, minDistance);

  /// Holds [action] pressed while [button] is, released when it is let go
  /// or the touch is cancelled: an on-screen button for what a key or a pad
  /// button does. Replaces whatever the button's own callbacks were.
  void bindButton(ButtonComponent button, GameAction action) {
    // Three statements, not a cascade: `..onPressed = () => a()..onReleased`
    // parses the second assignment into the first closure's body.
    button.onPressed = () => inputState.press(action);
    button.onReleased = () => inputState.release(action);
    button.onCancelled = () => inputState.release(action);
  }
}

/// Updated first among the game's children, before the camera whose
/// viewport holds the stick: it reads the deflection the stick settled on
/// last frame rather than racing the stick's own update to it.
final class _JoystickFeed extends Component {
  _JoystickFeed(this.stick, this.inputState, this.deadZone)
    : super(priority: BridgePriority.input);

  final JoystickComponent stick;
  final InputState inputState;
  final double deadZone;
  bool _moved = false;
  HasFixedStep? _stepped;

  /// In a game of fixed steps the stick is read before the steps, not in
  /// this component's update, which runs after them.
  @override
  void onMount() {
    super.onMount();
    final game = findGame();
    if (game is HasFixedStep) _stepped = game..beforeSteps(_read);
  }

  @override
  void onRemove() {
    _stepped?.removeBeforeSteps(_read);
    _stepped = null;
    super.onRemove();
  }

  @override
  void update(double dt) {
    if (_stepped == null) _read();
  }

  void _read() {
    final deflection = stick.relativeDelta;
    if (deflection.length > deadZone) {
      _moved = true;
      inputState.setStickAxis(deflection.x, -deflection.y);
    } else if (_moved) {
      _moved = false;
      inputState.setStickAxis(0.0, 0.0);
    }
  }
}

final class _InputStepEnd extends Component {
  _InputStepEnd(this.inputState) : super(priority: BridgePriority.inputEnd);

  final InputState inputState;
  HasFixedStep? _stepped;
  AppLifecycleListener? _lifecycle;

  /// In a game of fixed steps the input step is a fixed step: closed after
  /// each, so a press is seen by one step, and left open through a frame
  /// with none, so a press made in it is not lost.
  ///
  /// **A window that loses focus lets go of every key.** The key-up of a
  /// key held while the player switched away never arrives, and the jet
  /// flew on turning after an alt-tab.
  @override
  void onMount() {
    super.onMount();
    final game = findGame();
    if (game is HasFixedStep) {
      _stepped = game..afterEachStep(inputState.endStep);
    }
    _lifecycle = _listen();
  }

  /// Null where there is no app to lose focus: a game stepped in a plain
  /// Dart test, with no widgets binding.
  AppLifecycleListener? _listen() {
    final WidgetsBinding binding;
    try {
      binding = WidgetsBinding.instance;
    } on Object {
      return null;
    }
    return AppLifecycleListener(
      binding: binding,
      onStateChange: (AppLifecycleState state) {
        if (state != AppLifecycleState.resumed) inputState.clear();
      },
    );
  }

  @override
  void onRemove() {
    _stepped?.removeAfterEachStep(inputState.endStep);
    _stepped = null;
    _lifecycle?.dispose();
    _lifecycle = null;
    super.onRemove();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_stepped == null) inputState.endStep();
  }
}

/// Where the pointer is over a Flame game, and a tap as an action; made by
/// [FlameInputBridge.pointer].
final class PointerTrack extends PositionComponent
    with PointerMoveCallbacks, TapCallbacks, DragCallbacks {
  PointerTrack._(this._input, this._press);

  final InputState _input;
  final GameAction? _press;

  /// Where the pointer last was over the game, in logical pixels from the
  /// canvas's top left; null before it has been over it.
  Vector2? get aim => _aim;
  Vector2? _aim;

  @override
  bool containsLocalPoint(Vector2 point) => true;

  @override
  void onPointerMove(PointerMoveEvent event) {
    _aim = event.canvasPosition.clone();
  }

  /// The pointers down on the game: [_press] is held while there is one.
  final Set<int> _down = <int>{};
  final Set<int> _dragging = <int>{};

  @override
  void onTapDown(TapDownEvent event) {
    _aim = event.canvasPosition.clone();
    _hold(event.pointerId);
    event.continuePropagation = true;
  }

  @override
  void onTapUp(TapUpEvent event) => _lift(event.pointerId);

  /// **A finger that moves is still down.** Flutter gives up on a tap once
  /// the finger slides past a few pixels, and the press was let go with
  /// it: firing while dragging to aim stopped the moment the aim moved.
  /// A tap given up on for a drag of the same pointer is not let go of;
  /// the drag's end is.
  @override
  void onTapCancel(TapCancelEvent event) {
    final pointer = event.pointerId;
    scheduleMicrotask(() {
      if (!_dragging.contains(pointer)) _lift(pointer);
    });
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    _dragging.add(event.pointerId);
    _hold(event.pointerId);
    event.continuePropagation = true;
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    super.onDragUpdate(event);
    _aim = event.canvasEndPosition.clone();
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    _dragging.remove(event.pointerId);
    _lift(event.pointerId);
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    _dragging.remove(event.pointerId);
    _lift(event.pointerId);
  }

  void _hold(int pointer) {
    final action = _press;
    if (_down.add(pointer) && _down.length == 1 && action != null) {
      _input.press(action);
    }
  }

  void _lift(int pointer) {
    final action = _press;
    if (_down.remove(pointer) && _down.isEmpty && action != null) {
      _input.release(action);
    }
  }
}

/// Swipes over a Flame game as presses; made by [FlameInputBridge.swipes].
final class SwipeInput extends PositionComponent with DragCallbacks {
  SwipeInput._(
    this._input,
    this._up,
    this._down,
    this._left,
    this._right,
    this._minDistance,
  );

  final InputState _input;
  final GameAction? _up;
  final GameAction? _down;
  final GameAction? _left;
  final GameAction? _right;
  final double _minDistance;
  final Vector2 _travel = Vector2.zero();

  @override
  bool containsLocalPoint(Vector2 point) => true;

  /// The drag goes on to what is under it too, a stick say: a layer over
  /// the whole canvas that kept it took every drag in the game.
  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    _travel.setZero();
    event.continuePropagation = true;
  }

  @override
  void onDragUpdate(DragUpdateEvent event) => _travel.add(event.canvasDelta);

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (_travel.length < _minDistance) return;
    final across = _travel.x.abs() > _travel.y.abs();
    final action = across
        ? (_travel.x > 0.0 ? _right : _left)
        : (_travel.y > 0.0 ? _down : _up);
    if (action == null) return;
    // Pressed and let go in one step: the state reports it pressed this
    // step, and held never.
    _input
      ..press(action)
      ..release(action);
  }
}
