import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'game_action.dart';

/// What the player is asking for, as one object that every input device writes
/// into and the simulation alone reads.
///
/// ## Latching, and why it is not optional
///
/// Devices produce events whenever they feel like it; the simulation consumes
/// them on a fixed step. At 30 frames per second with a 60 Hz step those two
/// rates are far enough apart that a key can go down and come back up entirely
/// between two steps. Comparing "held now" against "held last step" would see
/// nothing happened and swallow the shot — and it would do so more often the
/// worse the frame rate, which is exactly when the player is least forgiving.
///
/// So presses and releases are *latched*: they record that an edge happened at
/// all, survive until a step consumes them, and are cleared by [endStep]. A tap
/// too short to be held during any step still reads as [pressed] for exactly one
/// step.
///
/// ## Reading
///
/// Only the simulation calls [beginStep]/[endStep], and only between them are
/// [pressed] and [released] meaningful.
final class InputState {
  /// Physically down right now.
  final Set<GameAction> _held = <GameAction>{};

  /// Went down at least once since the last [endStep].
  final Set<GameAction> _pressedLatch = <GameAction>{};

  /// Came up at least once since the last [endStep].
  final Set<GameAction> _releasedLatch = <GameAction>{};

  /// Analogue movement from a stick, in `[-1, 1]` on each axis.
  final Vector2 _stickAxis = Vector2.zero();

  /// How hard an action is being asked for, where a device can say.
  ///
  /// Only holds the actions something has given a magnitude to; everything else
  /// answers from [held] — see [value].
  final Map<GameAction, double> _values = <GameAction, double>{};

  final Vector2 _moveAxis = Vector2.zero();
  final Vector2 _lookDelta = Vector2.zero();

  int? _slotRequest;

  // MARK: - Reading, from inside a step

  /// Movement intent: `x` strafes right, `y` moves forward. Never longer than 1.
  ///
  /// Clamped rather than left as a sum, or holding forward and right on the
  /// keyboard would move about 1.41 times as fast as holding forward alone —
  /// the oldest speed exploit there is.
  Vector2 get moveAxis => _moveAxis;

  /// Accumulated view movement since the last step, in whatever units the device
  /// reports. Sensitivity is applied by the camera, not here.
  Vector2 get lookDelta => _lookDelta;

  bool held(GameAction action) => _held.contains(action);

  /// True for the one step that consumes a press, even if the button was already
  /// released again by then.
  bool pressed(GameAction action) => _pressedLatch.contains(action);

  bool released(GameAction action) => _releasedLatch.contains(action);

  /// How hard [action] is being asked for, from nought to one.
  ///
  /// **An action has a magnitude as well as a bit**, and the point is that
  /// nothing downstream learns which device supplied it. A key gives one, a
  /// gamepad trigger gives 0.42, a future on-screen slider gives 0.7, and a
  /// simulation reading this cannot tell them apart — which is the same promise
  /// [moveAxis] already makes for a stick against four keys.
  ///
  /// A held action with no magnitude answers one, so every existing caller that
  /// switches to this keeps behaving exactly as it did. That is what makes it
  /// safe to read `value` everywhere and `held` only where a bit is genuinely
  /// what is wanted.
  ///
  /// Deliberately **not** folded into [moveAxis]: movement is already analogue
  /// through the stick, and an action's magnitude is about how far a trigger is
  /// pulled, which is a different question with a different answer.
  double value(GameAction action) =>
      _values[action] ?? (held(action) ? 1.0 : 0.0);

  /// The numbered slot asked for since the last step, if any.
  ///
  /// A weapon in a shooter, an item in an adventure, an ability in a
  /// platformer: what the number means is the game's business, and this used to
  /// say `weaponRequest` because only one game had ever asked.
  ///
  /// Last request wins. Two slots chosen inside a single frame is a fumble, and
  /// arriving at the one the player pressed most recently is what they meant.
  int? get slotRequest => _slotRequest;

  // MARK: - Writing, from a device

  void press(GameAction action) {
    _held.add(action);
    _pressedLatch.add(action);
    _recomputeMoveAxis();
  }

  void release(GameAction action) {
    _held.remove(action);
    _releasedLatch.add(action);
    _recomputeMoveAxis();
  }

  /// Says how hard an action is being asked for.
  ///
  /// Independent of [press] and [release]: a device that can measure travel
  /// reports both, because a game may want the threshold, the proportion, or
  /// each in a different place. A magnitude of nought is not a release —
  /// releasing is [release] — so a trigger returning to rest still has to say so
  /// both ways.
  void setActionValue(GameAction action, double magnitude) =>
      _values[action] = magnitude.clamp(0.0, 1.0);

  /// Sets the analogue movement axis, for a stick or a d-pad.
  void setStickAxis(double x, double y) {
    _stickAxis.setValues(x, y);
    _recomputeMoveAxis();
  }

  /// Adds view movement. Called once per mouse event or once per drag update;
  /// the values pile up until a step takes them.
  void addLook(double dx, double dy) {
    _lookDelta.setValues(_lookDelta.x + dx, _lookDelta.y + dy);
  }

  void requestSlot(int slot) {
    _slotRequest = slot;
  }

  /// Drops everything, held state included.
  ///
  /// For losing focus. A key that was down when the window went away never
  /// produces its key-up, so without this the player walks into a wall forever
  /// after alt-tabbing.
  void clear() {
    _held.clear();
    _pressedLatch.clear();
    _releasedLatch.clear();
    _stickAxis.setZero();
    _lookDelta.setZero();
    _moveAxis.setZero();
    _values.clear();
    _slotRequest = null;
  }

  // MARK: - Step boundaries

  /// Marks the start of a simulation step. Currently nothing to do, and it
  /// exists anyway so that call sites are already correct when it does.
  void beginStep() {}

  /// Marks the end of a simulation step and clears everything one-shot.
  ///
  /// Held state and the movement axis survive, because they describe a condition
  /// rather than an event.
  void endStep() {
    _pressedLatch.clear();
    _releasedLatch.clear();
    _lookDelta.setZero();
    _slotRequest = null;
  }

  void _recomputeMoveAxis() {
    var x = _stickAxis.x;
    var y = _stickAxis.y;

    if (_held.contains(GameAction.moveRight)) x += 1.0;
    if (_held.contains(GameAction.moveLeft)) x -= 1.0;
    if (_held.contains(GameAction.moveForward)) y += 1.0;
    if (_held.contains(GameAction.moveBack)) y -= 1.0;

    final lengthSquared = x * x + y * y;
    if (lengthSquared > 1.0) {
      final scale = 1.0 / math.sqrt(lengthSquared);
      x *= scale;
      y *= scale;
    }
    _moveAxis.setValues(x, y);
  }
}
