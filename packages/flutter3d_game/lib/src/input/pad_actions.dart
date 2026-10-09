import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:pad_input/pad_input.dart';
import 'package:vector_math/vector_math.dart';

import '../config/game_config.dart';
import 'action_input.dart';
import 'action_map.dart';
import 'bindings.dart' show InputSource, SlotActions;

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
/// **The file is `pad_actions.dart` and the class is `PadInput`**, which is a
/// mismatch on purpose. The plugin this reads is now called `pad_input`, and a
/// file of that name importing `package:pad_input/pad_input.dart` is two
/// different things one line apart: the raw device, and this — the translator
/// that turns its sticks and triggers into a game's own verbs. The class keeps
/// its name because every call site says it; the file gives its up because the
/// package needed it more.
///
/// ## What each control does is the action map's
///
/// A stick is a [DualAxisBinding] on [InputSource.padStick]: the left one on
/// [DualAxisAction.move] walks, the right one on [DualAxisAction.look] turns
/// the view at [lookRate]. A direction of an axis bound as a button —
/// [InputSource.padHalfAxis] — presses a [GameAction] with a magnitude, which
/// is how a stick steers. A button bound to a [SlotActions] action picks its
/// slot. All of it is in the map, so a player rebinds it and a file keeps
/// it; [addDefaultsTo] and [addDrivingDefaultsTo] are the two layouts a game
/// starts from.
final class PadInput {
  /// A pad reading [actions]; without one, a map holding only the pad's
  /// defaults — see [addDefaultsTo].
  PadInput({
    required this.state,
    Gamepad? pad,
    ActionMap? actions,
    this.lookRate = defaultLookRate,
    this.pressAt = 0.5,
    this.releaseAt = 0.35,
  }) : pad = pad ?? Gamepad.instance,
       actions = actions ?? addDefaultsTo(ActionMap(actions: ActionSet.common)),
       assert(releaseAt < pressAt, 'a threshold without a gap chatters') {
    _actionInput = ActionInput(state: state, map: this.actions);
  }

  /// The action map this pad reads: its buttons, and its composites, axes
  /// and sticks on `pad:` sources, read every [tick] — see
  /// [InputSource.padAxis] and [InputSource.padStick]. The look binding on
  /// `pad:stick.right` shapes [drainLook] with its sensitivity and invert.
  ///
  /// **The one input model.** The pad took a bare button table as well, and
  /// two ways in meant two places a rebinding could land; the map holds the
  /// table, so a game hands the same map to the keyboard, the pad and the
  /// settings screen.
  final ActionMap actions;

  late final ActionInput _actionInput;

  /// Adds the pad's defaults for a game that walks to [map] and returns it:
  /// the left stick walks, the right stick looks, the d-pad walks and the
  /// face buttons jump and use.
  ///
  /// ```dart
  /// final map = PadInput.addDefaultsTo(DesktopInput.defaultActionMap());
  /// ```
  ///
  /// **Only what [map] does not bind already.** A source the map holds keeps
  /// its binding, so a game calls this on the map it read from a player's
  /// settings and a file saved before a control existed gains it without
  /// losing a rebinding the player made.
  ///
  /// One table, because a player's bindings are one file: `key:` and `pad:` are
  /// prefixes in the same map, which the map's JSON already round-trips.
  static ActionMap addDefaultsTo(ActionMap map) {
    // The d-pad walks. Free, because `_recomputeMoveAxis` already sums held
    // directions with the stick and clamps the total — and useful, because a
    // menu driven by the same actions needs something discrete.
    _bindButtons(map, <PadButton, GameAction>{
      PadButton.dpadUp: GameAction.moveForward,
      PadButton.dpadDown: GameAction.moveBack,
      PadButton.dpadLeft: GameAction.moveLeft,
      PadButton.dpadRight: GameAction.moveRight,
      // Where a thumb finds them, not what is printed on them: on an Xbox pad
      // this is `A` and on a PlayStation pad it is Cross, and the file says
      // `pad:face.south` either way.
      PadButton.faceSouth: GameAction.jump,
      PadButton.faceWest: GameAction.use,
      // Clicking the stick you are already pushing, which is where every
      // console game of the last fifteen years has put running.
      PadButton.stickLeftClick: GameAction.sprint,
    });
    // Up is negative on a pad, as in the browser and on Apple's platforms;
    // forward is positive in the simulation, so the flip is the binding's.
    _bindStick(
      map,
      const DualAxisBinding(
        DualAxisAction.move,
        InputSource('${InputSource.padPrefix}stick.left'),
        tuning: AxisSettings(invertY: true),
      ),
    );
    _bindStick(
      map,
      const DualAxisBinding(
        DualAxisAction.look,
        InputSource('${InputSource.padPrefix}stick.right'),
      ),
    );
    return map;
  }

  /// Adds the pad's defaults for a game that drives to [map] and returns it:
  /// the left stick's sideways axis steers through [steerLeft] and
  /// [steerRight], half over for half the steering, and no stick walks or
  /// looks. The pedals are the game's to bind: a trigger is a button with a
  /// magnitude, so it is bound like one.
  ///
  /// Like [addDefaultsTo], it leaves a source [map] binds already alone.
  static ActionMap addDrivingDefaultsTo(
    ActionMap map, {
    required GameAction steerLeft,
    required GameAction steerRight,
  }) {
    final axis = PadAxis.leftStickX.name;
    for (final (source, action) in <(InputSource, GameAction)>[
      (InputSource.padHalfAxis(axis, positive: false), steerLeft),
      (InputSource.padHalfAxis(axis, positive: true), steerRight),
    ]) {
      if (map.buttons[source] == null) map.buttons.bind(source, action);
    }
    return map;
  }

  /// Binds the d-pad to the first four slots, clockwise from the top, in
  /// place of walking, and returns [map].
  ///
  /// A d-pad has no numbers on it, so there is no right answer and this is the
  /// one a player can guess. Offered rather than default because a game that
  /// walks with the d-pad cannot also select with it.
  static ActionMap addSlotDefaultsTo(ActionMap map) {
    for (final (index, button) in <PadButton>[
      PadButton.dpadUp,
      PadButton.dpadRight,
      PadButton.dpadDown,
      PadButton.dpadLeft,
    ].indexed) {
      map.buttons.bind(InputSource.pad(button.id), SlotActions.of(index));
    }
    return map;
  }

  static void _bindButtons(ActionMap map, Map<PadButton, GameAction> buttons) {
    for (final MapEntry(key: button, value: action) in buttons.entries) {
      final source = InputSource.pad(button.id);
      if (map.buttons[source] == null) map.buttons.bind(source, action);
    }
  }

  static void _bindStick(ActionMap map, DualAxisBinding binding) {
    if (!map.routes(binding.source)) map.bind(binding);
  }

  /// Whether [map] mentions a gamepad at all.
  ///
  /// For the awkward case that arrives with every new device: a config saved
  /// before this package existed has no `pad:` in it, and a player should not
  /// have to delete their settings to use a controller. A game reads its saved
  /// map, asks this, and adds the defaults if the answer is no — which leaves
  /// every rebinding they *did* make alone.
  static bool knowsPad(ActionMap map) => map.bindings
      .expand((ActionBinding b) => b.sources)
      .any((InputSource source) => source.id.startsWith(InputSource.padPrefix));

  final InputState state;
  final Gamepad pad;

  /// How far the view turns per second at full deflection of a stick bound
  /// to [DualAxisAction.look], **in the mouse's units**.
  ///
  /// Odd-looking, and deliberately so. [InputState.lookDelta] is in whatever
  /// the device reports and the camera applies one sensitivity to all of it,
  /// so a stick that arrived in a currency of its own would be a second
  /// sensitivity nobody can see. Set from [GameSettingKeys.padLook] by
  /// [applySettings]. Deliberately **linear**: a response curve is the other
  /// thing everybody tunes here, and nobody can tune it without a device.
  double lookRate;

  /// [lookRate] when nobody has chosen: `flutter3d_game_shooter`'s player
  /// turns 0.0022 radians per unit, so this is about 2.4 radians a second.
  static const double defaultLookRate = 1100.0;

  /// How far a trigger travels before it counts as pressed, and how far back
  /// before it counts as released.
  ///
  /// Two numbers rather than one, because one number chatters: a trigger resting
  /// against a threshold sends a stream of presses and releases, and a weapon
  /// bound to it fires as fast as the frame rate. The platform's own idea of
  /// "down" is deliberately ignored for the triggers — it is a threshold
  /// somebody else chose, and two platforms would choose differently.
  final double pressAt;

  /// How far back a pressed trigger travels before it counts as released, a
  /// fraction of its travel from nought to one.
  final double releaseAt;

  final PadSnapshot _snapshot = PadSnapshot();

  /// What the pad is holding, and the only thing it is allowed to release.
  ///
  /// Keyed by button rather than a set of actions, so two buttons bound to one
  /// action release it once — when the second of them comes up, not the first.
  final Map<String, GameAction> _holding = <String, GameAction>{};

  /// Actions carrying a magnitude the pad supplied, by the control that
  /// supplied it and with how far it is pressed, so it can withdraw them and
  /// so two controls on one action are answered by the harder press.
  final Map<String, ({GameAction action, double magnitude})> _speaking =
      <String, ({GameAction action, double magnitude})>{};

  /// The analogue controls [tick] read this time round. One that spoke and
  /// was not read (its binding removed, or [routes] swapped while it was
  /// pressed) would otherwise hold its last magnitude for good, and win every
  /// maximum its action takes.
  final Set<String> _readThisTick = <String>{};

  final Vector2 _look = Vector2.zero();

  bool _wasConnected = false;

  bool get isSupported => pad.isSupported;

  /// Whether a pad answered the last [tick].
  bool get isConnected => _snapshot.isConnected;

  /// What the pad is holding, for a screen rather than for a simulation.
  ///
  /// A title card waiting for "press any button", a rebinding row listening for
  /// the next press, a game-over screen offering a restart: none of those are
  /// verbs the simulation has, and inventing an action for each would put words
  /// in the binding table that no game logic ever reads.
  Iterable<PadButton> get heldButtons => _snapshot.held;

  /// Reads the pad and writes what it says into the state.
  ///
  /// [dt] is real seconds since the last call, and is needed for one thing: a
  /// stick reports a **rate** and [InputState.addLook] accumulates a
  /// **displacement**, so the integration has to happen somewhere and this is
  /// the only place that knows both numbers.
  void tick(double dt) {
    pad.read(_snapshot);

    if (!_snapshot.isConnected) {
      // A pad that was never there touches nothing. Zeroing the stick
      // unconditionally would fight a touch control for a device that does not
      // exist, on every frame of every build.
      if (_wasConnected) _letGo();
      _wasConnected = false;
      return;
    }
    _wasConnected = true;
    _readThisTick.clear();

    _integrateLook(dt);
    _halfAxes();

    for (final button in PadButton.known) {
      final action = actions.buttons[InputSource.pad(button.id)];
      if (action == null) continue;

      if (SlotActions.indexOf(action) case final int slot) {
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

      if (button == PadButton.triggerLeft || button == PadButton.triggerRight) {
        final axis = button == PadButton.triggerLeft
            ? PadAxis.triggerLeft
            : PadAxis.triggerRight;
        _analogue(button.id, action, _snapshot.axis(axis));
        continue;
      }

      _digital(button.id, action, down: _snapshot.down(button));
    }

    _routeActions();

    // Whatever spoke and was not read this tick has been unbound or rerouted
    // from under a press: it stops speaking, and its action is answered by
    // what is left.
    final gone = _speaking.keys.where((k) => !_readThisTick.contains(k));
    for (final key in gone.toList()) {
      _answer(_speaking.remove(key)!.action);
    }
  }

  /// Adds the view movement accumulated since the last call, and forgets it.
  ///
  /// **Adds**, where [DesktopInput.drainLook] *assigns* — an asymmetry worth
  /// stating because it is invisible at the call site. `EngineLoop` takes one
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
    final (x, y) = _actionInput.shapeDelta(
      DualAxisAction.look,
      InputSource.padStick('right'),
      _look.x,
      _look.y,
    );
    out.setValues(out.x + x, out.y + y);
    _look.setZero();
  }

  /// Adds this tick's turn of every stick bound to [DualAxisAction.look] to
  /// the view, integrated over [dt] at [lookRate]: a stick reports a rate
  /// and the look is a displacement. Not negated — the mouse also reports
  /// positive downwards, and the camera subtracts.
  void _integrateLook(double dt) {
    for (final (side, x, y) in _sticks) {
      final source = InputSource.padStick(side);
      final looks = actions.axisBindings.any(
        (ActionBinding b) =>
            b is DualAxisBinding &&
            b.action == DualAxisAction.look &&
            b.source == source,
      );
      if (!looks) continue;
      _look.setValues(
        _look.x + _snapshot.axis(x) * lookRate * dt,
        _look.y + _snapshot.axis(y) * lookRate * dt,
      );
    }
  }

  /// Every direction of an axis the button table binds, read as a button
  /// with a magnitude.
  void _halfAxes() {
    for (final source in actions.buttons.sources.toList()) {
      final id = source.id;
      const prefix = '${InputSource.padPrefix}axis.';
      if (!id.startsWith(prefix) || id.length <= prefix.length) continue;
      final sign = id[id.length - 1];
      if (sign != '+' && sign != '-') continue;
      final axis = _axes[id.substring(prefix.length, id.length - 1)];
      final action = actions.buttons[source];
      if (axis == null || action == null) continue;
      final value = _snapshot.axis(axis);
      final magnitude = sign == '+'
          ? (value > 0.0 ? value : 0.0)
          : (value < 0.0 ? -value : 0.0);
      _analogue(id, action, magnitude);
    }
  }

  static final Map<String, PadAxis> _axes = PadAxis.values.asNameMap();

  static const List<(String, PadAxis, PadAxis)> _sticks =
      <(String, PadAxis, PadAxis)>[
        ('left', PadAxis.leftStickX, PadAxis.leftStickY),
        ('right', PadAxis.rightStickX, PadAxis.rightStickY),
      ];

  /// Hands the pad's state to the action map's non-button bindings: each
  /// button a composite uses, each axis and each stick an analogue binding
  /// names. Nothing is read for a source no binding mentions.
  void _routeActions() {
    final input = _actionInput;
    for (final button in PadButton.known) {
      final source = InputSource.pad(button.id);
      if (!input.routes(source)) continue;
      _snapshot.down(button)
          ? input.sourceDown(source)
          : input.sourceUp(source);
    }
    for (final axis in PadAxis.values) {
      final source = InputSource.padAxis(axis.name);
      if (input.routes(source)) input.sourceValue(source, _snapshot.axis(axis));
    }
    for (final (side, x, y) in _sticks) {
      final source = InputSource.padStick(side);
      if (input.routes(source)) {
        input.sourcePair(source, _snapshot.axis(x), _snapshot.axis(y));
      }
    }
  }

  /// Takes the player's numbers out of [settings]: [lookRate] from
  /// [GameSettingKeys.padLook] and the dead zones from
  /// [GameSettingKeys.stickDeadZone] and [GameSettingKeys.triggerDeadZone].
  ///
  /// Here rather than in each game, so the keys are read once instead of
  /// three times slightly differently.
  void applySettings(GameSettings settings) {
    lookRate = settings.valueOf(GameSettingKeys.padLook);
    pad.deadzone = Deadzone(
      stick: settings.valueOf(GameSettingKeys.stickDeadZone),
      trigger: settings.valueOf(GameSettingKeys.triggerDeadZone),
    );
  }

  /// A control that has a magnitude as well as a bit.
  ///
  /// Keyed by [control] — the trigger or the half-axis — and not by [action],
  /// for the reason [_holding] gives: two triggers bound to one action used
  /// to share one entry, so the one at rest released what the other had just
  /// pressed, and the action chattered down and up every frame it was held.
  void _analogue(String control, GameAction action, double magnitude) {
    final key = '$_analogueMark$control';
    final wasDown = _holding.containsKey(key);
    _readThisTick.add(key);

    final before = _speaking[key];
    if (magnitude > 0.0) {
      _speaking[key] = (action: action, magnitude: magnitude);
    } else {
      _speaking.remove(key);
    }
    // A control rebound to another action leaves the old one to be answered
    // by whatever still presses it.
    if (before != null && before.action != action) _answer(before.action);
    _answer(action, spoke: before != null || magnitude > 0.0);

    if (!wasDown && magnitude >= pressAt) {
      _holding[key] = action;
      state.press(action);
    } else if (wasDown && magnitude <= releaseAt) {
      _holding.remove(key);
      state.release(action);
    }
  }

  /// Sets [action] to the hardest press among the controls speaking for it.
  ///
  /// **The harder press answers**, not whichever control was read last: two
  /// triggers on one action at 1.0 and 0.2 used to give 0.2, and letting one
  /// go withdrew the value the other had just written, so for that frame the
  /// action fell back to its held 1.0. Withdrawn rather than zeroed once no
  /// control speaks for it, so a key bound to the same action starts meaning
  /// something again; and only when one did, or an idle trigger would
  /// withdraw a key's value every frame. See the class doc.
  void _answer(GameAction action, {bool spoke = true}) {
    final strongest = _speaking.values
        .where((s) => s.action == action)
        .fold<double>(
          0.0,
          (best, s) => s.magnitude > best ? s.magnitude : best,
        );
    if (strongest > 0.0) {
      state.setActionValue(action, strongest);
    } else if (spoke) {
      state.clearActionValue(action);
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
    for (final spoken in _speaking.values) {
      state.clearActionValue(spoken.action);
    }
    _holding.clear();
    _speaking.clear();
    _look.setZero();
    // Clears what the map's sticks wrote, and only that: a game whose
    // sticks are bound to nothing goes on never having touched the axis.
    _actionInput.letGo();
  }

  /// Marks an entry in [_holding] that came from an axis rather than a button,
  /// so the two cannot collide on a name.
  static const String _analogueMark = 'axis:';

  /// Stands in for "this button is down and selects a slot", which holds no
  /// action and must never be released as one.
  static const GameAction _slotSentinel = GameAction('');
}
