import 'package:gamepad/gamepad.dart';
import 'package:vector_math/vector_math.dart';

import '../config/game_config.dart';
import 'bindings.dart';
import 'game_action.dart';
import 'input_state.dart';

/// What a stick's two axes are for.
enum PadStickUse {
  /// Nothing. A racing game's left stick steers through [PadAxisPair] instead,
  /// and its right stick does not exist.
  ignored,

  /// Movement, through [InputState.setStickAxis].
  move,

  /// Turning the view, integrated over time — see [PadRoutes.lookRate].
  look,
}

/// A signed axis routed to two actions, one per direction.
///
/// For a control that is an axis on a pad and a pair of keys on a keyboard:
/// steering is `steerLeft`/`steerRight` at the keyboard and one stick axis on a
/// pad, and the simulation should not be able to tell which it got. Each side
/// gets a magnitude as well as a press, so a stick half over asks for half the
/// steering.
///
/// **Not a [Bindings] entry**, and that is the important part: binding half an
/// axis as an [InputSource] would run it through `press`/`held` and make every
/// stick digital, which is exactly what `flutter3d_shooter`'s "half a deflection
/// is half a wish" test forbids.
final class PadAxisPair {
  const PadAxisPair({required this.negative, required this.positive});

  /// What a negative reading asks for. Left, or up on a stick.
  final GameAction negative;

  /// What a positive reading asks for. Right, or down on a stick.
  final GameAction positive;
}

/// Where each of a pad's analogue controls goes, for one kind of game.
///
/// Buttons are bound, in the table the player can edit and the game saves.
/// Axes are **routed**, here, in code — because what a stick is *for* is a
/// property of the genre rather than a preference: a racing game's left stick
/// steers and there is no version of that game where it walks.
final class PadRoutes {
  const PadRoutes({
    this.leftStick = PadStickUse.move,
    this.rightStick = PadStickUse.look,
    this.axisActions = const <PadAxis, PadAxisPair>{},
    this.lookRate = defaultLookRate,
  });

  /// A stick that walks and a stick that looks: a platformer, a shooter, and
  /// almost everything else.
  static const PadRoutes walking = PadRoutes();

  /// One stick that steers, and no stick that looks.
  ///
  /// The pedals are not here: a trigger is a button as well as an axis, so it is
  /// bound like one and a player can move it. Which way the stick turns the car
  /// is not something a player rebinds.
  static PadRoutes driving({
    required GameAction steerLeft,
    required GameAction steerRight,
  }) =>
      PadRoutes(
        leftStick: PadStickUse.ignored,
        rightStick: PadStickUse.ignored,
        axisActions: <PadAxis, PadAxisPair>{
          PadAxis.leftStickX:
              PadAxisPair(negative: steerLeft, positive: steerRight),
        },
      );

  /// How far the view turns per second at full deflection, **in the mouse's
  /// units**.
  ///
  /// Odd-looking, and deliberately so. [InputState.lookDelta] is in whatever the
  /// device reports and the camera applies one sensitivity to all of it, so a
  /// stick that arrives in a currency of its own would be a second sensitivity
  /// nobody can see. `flutter3d_shooter`'s player turns 0.0022 radians per unit,
  /// which puts this default at about 2.4 radians per second — a brisk but
  /// controllable turn.
  ///
  /// It is a number that can only be settled with a controller in hand, like a
  /// dead zone, and so is a slider: `pad.look` in [GameConfig.settings], applied
  /// by [PadInput.applySettings].
  ///
  /// Deliberately **linear**. A response curve is the other thing everybody
  /// tunes here and the other thing nobody can tune without a device; adding one
  /// blind would be inventing a shape and calling it a decision.
  static const double defaultLookRate = 1100.0;

  final PadStickUse leftStick;
  final PadStickUse rightStick;

  /// Axes that mean a pair of actions rather than movement or a view.
  final Map<PadAxis, PadAxisPair> axisActions;

  final double lookRate;

  PadRoutes copyWith({double? lookRate}) => PadRoutes(
        leftStick: leftStick,
        rightStick: rightStick,
        axisActions: axisActions,
        lookRate: lookRate ?? this.lookRate,
      );
}

/// Feeds an [InputState] from a gamepad.
///
/// The keyboard's twin: [DesktopInput] is the only file that knows what a key
/// is, and this is the only one that knows what a thumb stick is. Below both,
/// the simulation sees actions and an axis — which is what lets the same game
/// run from either without a branch.
///
/// ## Polled, not subscribed
///
/// [tick] is called once per frame, before the loop advances, and everything
/// happens there: edges, magnitudes, the view, and letting go of a pad that has
/// been unplugged. Nothing is driven by a stream, even though the platform
/// offers one, because an event arriving between two steps would mutate the
/// player's intent halfway through a frame — and a fixed-step simulation whose
/// input changes mid-step is the kind of bug that only shows up on somebody
/// else's machine.
///
/// [Gamepad.connectionChanges] is still there for a menu that wants to say a
/// controller appeared; this class does not use it.
///
/// ## Two devices, one action, and who wins
///
/// A pad releases **only what the pad was holding** — never
/// [InputState.clear], which would drop keys the keyboard is genuinely still
/// holding. It presses and releases exactly once per control and keeps no count
/// of its own: [InputState.release] counts holds, so two buttons bound to one
/// action are already handled and a second opinion here would fight it. Where a key and a trigger share an action, a magnitude is
/// authoritative while the trigger is off its rest: a player feathering a
/// trigger and holding `W` gets the trigger's number, because the trigger is
/// what they are moving. A trigger fully at rest withdraws its number
/// ([InputState.clearActionValue]) and `W` means full again.
final class PadInput {
  PadInput({
    required this.state,
    Gamepad? pad,
    Bindings? bindings,
    this.routes = PadRoutes.walking,
    Map<PadButton, int>? slotButtons,
    this.pressAt = 0.5,
    this.releaseAt = 0.35,
  })  : pad = pad ?? Gamepad.instance,
        bindings = bindings ?? defaultBindings(),
        slotButtons = slotButtons ?? const <PadButton, int>{},
        assert(releaseAt < pressAt, 'a threshold without a gap chatters');

  /// The pad half of a binding table, as a fresh one each call.
  ///
  /// A function and not a constant for the reason [DesktopInput.defaultBindings]
  /// gives: a [Bindings] is mutable and a rebinding screen edits it, so handing
  /// every caller the same object means the first player to rebind anything
  /// rebinds it everywhere.
  ///
  /// Usually the game wants **one** table holding both halves, since that is
  /// what gets saved — see [addDefaultsTo].
  static Bindings defaultBindings() => addDefaultsTo(Bindings());

  /// Adds the pad's defaults to an existing table and returns it.
  ///
  /// ```dart
  /// final bindings = PadInput.addDefaultsTo(DesktopInput.defaultBindings());
  /// ```
  ///
  /// One table, because a player's bindings are one file: `key:` and `pad:` are
  /// prefixes in the same map, which [Bindings.toJson] already round-trips.
  static Bindings addDefaultsTo(Bindings bindings) {
    // The d-pad walks. Free, because `_recomputeMoveAxis` already sums held
    // directions with the stick and clamps the total — and useful, because a
    // menu driven by the same actions needs something discrete.
    bindings
      ..bind(InputSource.pad(PadButton.dpadUp.id), GameAction.moveForward)
      ..bind(InputSource.pad(PadButton.dpadDown.id), GameAction.moveBack)
      ..bind(InputSource.pad(PadButton.dpadLeft.id), GameAction.moveLeft)
      ..bind(InputSource.pad(PadButton.dpadRight.id), GameAction.moveRight)
      // Where a thumb finds them, not what is printed on them: on an Xbox pad
      // this is `A` and on a PlayStation pad it is Cross, and the file says
      // `pad:face.south` either way.
      ..bind(InputSource.pad(PadButton.faceSouth.id), GameAction.jump)
      ..bind(InputSource.pad(PadButton.faceWest.id), GameAction.use)
      // Clicking the stick you are already pushing, which is where every
      // console game of the last fifteen years has put running.
      ..bind(InputSource.pad(PadButton.stickLeftClick.id), GameAction.sprint);
    return bindings;
  }

  /// The d-pad, clockwise from the top.
  ///
  /// A d-pad has no numbers on it, so there is no right answer and this is the
  /// one a player can guess. Offered rather than default because a game that
  /// walks with the d-pad cannot also select with it — and the check happens
  /// before the bindings, exactly as [DesktopInput] resolves the number row
  /// before the letters.
  ///
  /// Not `const`: a [PadButton] is a value class with its own `==`, which Dart
  /// will not accept as a constant map's key. [DesktopInput.defaultSlotKeys] is
  /// `static final` for the same reason.
  static final Map<PadButton, int> dpadSlots = <PadButton, int>{
    PadButton.dpadUp: 0,
    PadButton.dpadRight: 1,
    PadButton.dpadDown: 2,
    PadButton.dpadLeft: 3,
  };

  final InputState state;
  final Gamepad pad;

  /// What each button does. The same object the keyboard uses, if the game
  /// passes it: see [addDefaultsTo].
  final Bindings bindings;

  /// Where the analogue controls go. Mutable, because a game that drives and
  /// walks changes it when the player gets out of the car.
  PadRoutes routes;

  final Map<PadButton, int> slotButtons;

  /// How far a trigger travels before it counts as pressed, and how far back
  /// before it counts as released.
  ///
  /// Two numbers rather than one, because one number chatters: a trigger resting
  /// against a threshold sends a stream of presses and releases, and a weapon
  /// bound to it fires as fast as the frame rate. The platform's own idea of
  /// "down" is deliberately ignored for the triggers — it is a threshold
  /// somebody else chose, and two platforms would choose differently.
  final double pressAt;
  final double releaseAt;

  final PadSnapshot _snapshot = PadSnapshot();

  /// What the pad is holding, and the only thing it is allowed to release.
  ///
  /// Keyed by button rather than a set of actions, so two buttons bound to one
  /// action release it once — when the second of them comes up, not the first.
  final Map<String, GameAction> _holding = <String, GameAction>{};

  /// Actions carrying a magnitude the pad supplied, so it can withdraw them.
  final Set<GameAction> _speaking = <GameAction>{};

  final Vector2 _look = Vector2.zero();

  bool _wasConnected = false;

  bool get isSupported => pad.isSupported;

  /// Whether a pad answered the last [tick].
  bool get isConnected => _snapshot.connected;

  /// Reads the pad and writes what it says into the state.
  ///
  /// [dt] is real seconds since the last call, and is needed for one thing: a
  /// stick reports a **rate** and [InputState.addLook] accumulates a
  /// **displacement**, so the integration has to happen somewhere and this is
  /// the only place that knows both numbers.
  void tick(double dt) {
    pad.read(_snapshot);

    if (!_snapshot.connected) {
      // A pad that was never there touches nothing. Zeroing the stick
      // unconditionally would fight a touch control for a device that does not
      // exist, on every frame of every build.
      if (_wasConnected) _letGo();
      _wasConnected = false;
      return;
    }
    _wasConnected = true;

    _routeStick(
      routes.leftStick,
      _snapshot.axis(PadAxis.leftStickX),
      _snapshot.axis(PadAxis.leftStickY),
      dt,
    );
    _routeStick(
      routes.rightStick,
      _snapshot.axis(PadAxis.rightStickX),
      _snapshot.axis(PadAxis.rightStickY),
      dt,
    );

    for (final entry in routes.axisActions.entries) {
      final value = _snapshot.axis(entry.key);
      _analogue(entry.value.positive, value > 0.0 ? value : 0.0);
      _analogue(entry.value.negative, value < 0.0 ? -value : 0.0);
    }

    for (final button in PadButton.known) {
      final slot = slotButtons[button];
      if (slot != null) {
        // On the edge, not while held: a slot held down would be re-selected
        // every frame, and the last request of a frame wins.
        if (_snapshot.down(button) && !_holding.containsKey(button.id)) {
          state.requestSlot(slot);
          _holding[button.id] = _slotSentinel;
        } else if (!_snapshot.down(button)) {
          _holding.remove(button.id);
        }
        continue;
      }

      final action = bindings[InputSource.pad(button.id)];
      if (action == null) continue;

      if (button == PadButton.triggerLeft || button == PadButton.triggerRight) {
        final axis = button == PadButton.triggerLeft
            ? PadAxis.triggerLeft
            : PadAxis.triggerRight;
        _analogue(action, _snapshot.axis(axis));
        continue;
      }

      _digital(button.id, action, down: _snapshot.down(button));
    }
  }

  /// Adds the view movement accumulated since the last call, and forgets it.
  ///
  /// **Adds**, where [DesktopInput.drainLook] *assigns* — an asymmetry worth
  /// stating because it is invisible at the call site. `GameLoop` takes one
  /// callback, so a game with both devices composes them:
  ///
  /// ```dart
  /// drainLook: (Vector2 out) {
  ///   _desktop.drainLook(out);
  ///   _pad.drainLook(out);
  /// }
  /// ```
  ///
  /// The mouse's own accumulator is authoritative for the mouse, and the pad's
  /// contribution is added on top, so moving both at once turns the view by the
  /// sum rather than by whichever ran last.
  void drainLook(Vector2 out) {
    out.setValues(out.x + _look.x, out.y + _look.y);
    _look.setZero();
  }

  /// Takes the player's numbers out of a config.
  ///
  /// Here rather than in each game, so `pad.look` is spelled once instead of
  /// three times slightly differently. The names are documented on
  /// [GameConfig.settings].
  void applySettings(GameConfig config) {
    routes = routes.copyWith(
      lookRate: config.settingOf('pad.look', PadRoutes.defaultLookRate),
    );
    const rest = Deadzone();
    pad.deadzone = Deadzone(
      stick: config.settingOf('pad.deadzone.stick', rest.stick),
      trigger: config.settingOf('pad.deadzone.trigger', rest.trigger),
    );
  }

  /// Writes the player's numbers back, for a settings panel that changed them.
  void storeSettings(GameConfig config) {
    config
      ..setSetting('pad.look', routes.lookRate)
      ..setSetting('pad.deadzone.stick', pad.deadzone.stick)
      ..setSetting('pad.deadzone.trigger', pad.deadzone.trigger);
  }

  void _routeStick(PadStickUse use, double x, double y, double dt) {
    switch (use) {
      case PadStickUse.ignored:
        break;
      case PadStickUse.move:
        // Y is negated because a pad reports positive downwards — Apple's
        // convention and the browser's, which the device package passes on
        // unchanged rather than flipping where a reader cannot see it. Forward
        // is positive here, so the flip happens in the open.
        state.setStickAxis(x, -y);
      case PadStickUse.look:
        // Not negated: the mouse also reports positive downwards, and the
        // camera subtracts. A stick that agreed with the mouse about x and
        // disagreed about y would be a bug nobody could find by reading.
        _look.setValues(
          _look.x + x * routes.lookRate * dt,
          _look.y + y * routes.lookRate * dt,
        );
    }
  }

  /// A control that has a magnitude as well as a bit.
  void _analogue(GameAction action, double magnitude) {
    final key = '$_analogueMark${action.name}';
    final wasDown = _holding.containsKey(key);

    if (magnitude > 0.0) {
      state.setActionValue(action, magnitude);
      _speaking.add(action);
    } else if (_speaking.remove(action)) {
      // Withdrawn rather than zeroed, so a key bound to the same action starts
      // meaning something again. See the class doc.
      state.clearActionValue(action);
    }

    if (!wasDown && magnitude >= pressAt) {
      _holding[key] = action;
      state.press(action);
    } else if (wasDown && magnitude <= releaseAt) {
      _holding.remove(key);
      state.release(action);
    }
  }

  void _digital(String buttonId, GameAction action, {required bool down}) {
    final wasDown = _holding.containsKey(buttonId);
    if (down && !wasDown) {
      _holding[buttonId] = action;
      state.press(action);
    } else if (!down && wasDown) {
      _holding.remove(buttonId);
      state.release(action);
    }
  }

  /// Lets go of everything the pad was holding, and nothing else.
  void _letGo() {
    // Once per control, not once per action: two buttons bound to firing pressed
    // twice, and [InputState.release] is what counts them back down.
    for (final action in _holding.values) {
      if (action == _slotSentinel) continue;
      state.release(action);
    }
    for (final action in _speaking) {
      state.clearActionValue(action);
    }
    _holding.clear();
    _speaking.clear();
    _look.setZero();
    // Only if the pad was the one writing it. A game whose stick is routed to
    // nothing has never touched the axis and must not start now.
    if (routes.leftStick == PadStickUse.move ||
        routes.rightStick == PadStickUse.move) {
      state.setStickAxis(0.0, 0.0);
    }
  }

  /// Marks an entry in [_holding] that came from an axis rather than a button,
  /// so the two cannot collide on a name.
  static const String _analogueMark = 'axis:';

  /// Stands in for "this button is down and selects a slot", which holds no
  /// action and must never be released as one.
  static const GameAction _slotSentinel = GameAction('');
}
