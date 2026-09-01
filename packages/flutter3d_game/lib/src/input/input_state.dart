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

  /// How many things are holding each held action down — see [release].
  final Map<GameAction, int> _holds = <GameAction, int>{};

  /// Actions a press flips rather than holds — see [setToggled].
  final Set<GameAction> _toggled = <GameAction>{};

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

  /// What became held and what let go this step, for something that has to
  /// write it all down rather than ask about one action.
  ///
  /// **Added for [InputTape] and narrow on purpose.** Everything else here
  /// answers a question about one action, which is what a game wants: a
  /// simulation asks "is the player firing", never "what happened". A recorder
  /// is the one caller that cannot ask by name, because it does not know which
  /// names a genre invented.
  ///
  /// Unmodifiable views, so writing one down cannot alter it.
  Iterable<GameAction> get pressedThisStep =>
      List<GameAction>.unmodifiable(_pressedLatch);

  Iterable<GameAction> get releasedThisStep =>
      List<GameAction>.unmodifiable(_releasedLatch);

  /// Everything held right now, for a recorder that starts mid-run.
  ///
  /// A tape records transitions, and a player already holding forward when the
  /// recording begins made that transition before the first entry — so a
  /// replay that pressed nothing would stand still where the player walked.
  /// The recorder writes these as pressed on its first entry, and nothing else
  /// has a reason to enumerate them.
  Iterable<GameAction> get heldNow => List<GameAction>.unmodifiable(_held);

  /// Every action with an analogue reading, and the reading.
  ///
  /// A trigger held half way is not a press and not a release, so a tape that
  /// recorded only transitions would replay a run with the accelerator off.
  Map<GameAction, double> get analogueValues =>
      Map<GameAction, double>.unmodifiable(_values);

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

  /// Whether the devices are ignored.
  ///
  /// **For a replay, and it is the replay's problem being solved.** A tape
  /// being played writes into this same object, and the keyboard goes on
  /// writing too: a player holding forward while a kill camera plays would
  /// add a second hold to every one the tape presses, and the tape's releases
  /// would then release nothing. So while this is set every device write is
  /// dropped — and `InputTapePlayback` lifts it around its own writes, because
  /// the tape is the one device that is meant to get through.
  ///
  /// Held state is not cleared by setting this; call [clear] for that, at the
  /// moment the replay's own history takes over.
  bool muted = false;

  void press(GameAction action) {
    if (muted) return;
    if (_toggled.contains(action)) {
      // A press flips it and a release says nothing. Which is the whole feature:
      // see [setToggled].
      if (_held.remove(action)) {
        _holds.remove(action);
        _releasedLatch.add(action);
      } else {
        _held.add(action);
        _holds[action] = 1;
        _pressedLatch.add(action);
      }
      _recomputeMoveAxis();
      return;
    }
    _holds[action] = (_holds[action] ?? 0) + 1;
    _held.add(action);
    _pressedLatch.add(action);
    _recomputeMoveAxis();
  }

  /// Lets go of one hold on [action], which releases it only if it was the last.
  ///
  /// **Counted, not a bit**, and the difference is visible in the shipped games:
  /// `W` and the up arrow are both bound to walking forward, so a player holding
  /// both and lifting one used to stop dead. Same again for a hand on the
  /// keyboard and a thumb on a pad, which is how this was found.
  ///
  /// The count is per action rather than per source, because [press] does not say
  /// who is pressing and should not have to: a device that produces edges — every
  /// one here does — presses once and releases once, and the arithmetic works out
  /// without anybody being identified. A device that pressed twice without
  /// releasing would stay held, and that is a bug in the device.
  void release(GameAction action) {
    if (muted) return;
    // A toggled action is let go by pressing it again, so the release that ends
    // an ordinary hold has nothing to do here.
    if (_toggled.contains(action)) return;
    final holds = (_holds[action] ?? 0) - 1;
    if (holds > 0) {
      _holds[action] = holds;
      return;
    }
    _holds.remove(action);
    _held.remove(action);
    _releasedLatch.add(action);
    _recomputeMoveAxis();
  }

  /// Makes [action] latch: a press turns it on and the next press turns it off.
  ///
  /// **An accessibility setting, and a plain one.** Sprinting is held, and
  /// holding a key for the length of a climb is a real barrier for a player with
  /// limited grip or a tremor — the accommodation every guideline names first
  /// and the one nearly every game omits. A latch costs one set and two
  /// branches.
  ///
  /// Here rather than in a device because it is not about a device: a keyboard,
  /// a pad and a thumb should all latch the same action, and putting it in one
  /// translator would mean the other two disagreed. It is also why [release]
  /// does nothing for a latched action — the device still reports the release,
  /// honestly, and this is the layer that decides it means nothing.
  ///
  /// A latch survives [endStep] and dies with [clear], like any other held
  /// state: a player who alt-tabs mid-climb comes back standing still rather
  /// than sprinting into a wall. **The choice of which actions latch does not
  /// die with it** — that is a setting, not state, and a player should not have
  /// to set it again because a window lost focus.
  void setToggled(GameAction action, {required bool toggled}) {
    if (toggled) {
      _toggled.add(action);
      return;
    }
    _toggled.remove(action);
    // Left held would be a sprint nothing can turn off: the key that would have
    // released it is up already, and the press that would have flipped it is not
    // coming.
    if (_held.remove(action)) {
      _holds.remove(action);
      _releasedLatch.add(action);
      _recomputeMoveAxis();
    }
  }

  /// Whether [action] latches rather than being held.
  bool isToggled(GameAction action) => _toggled.contains(action);

  /// Says how hard an action is being asked for.
  ///
  /// Independent of [press] and [release]: a device that can measure travel
  /// reports both, because a game may want the threshold, the proportion, or
  /// each in a different place. A magnitude of nought is not a release —
  /// releasing is [release] — so a trigger returning to rest still has to say so
  /// both ways.
  void setActionValue(GameAction action, double magnitude) {
    if (muted) return;
    _values[action] = magnitude.clamp(0.0, 1.0);
  }

  /// Stops saying anything about how hard [action] is asked for.
  ///
  /// **Not the same as a magnitude of nought**, and the difference is what makes
  /// two devices able to share one action. A magnitude present is authoritative:
  /// a trigger resting at zero really does mean no throttle. So a gamepad that
  /// went away, or whose trigger came back to rest, has to *withdraw* its
  /// number rather than set it to zero — otherwise the last thing the pad said
  /// shadows the keyboard for the rest of the process, and `W` stops working the
  /// first time anybody touches a trigger.
  void clearActionValue(GameAction action) {
    if (muted) return;
    _values.remove(action);
  }

  /// Sets the analogue movement axis, for a stick or a d-pad.
  void setStickAxis(double x, double y) {
    if (muted) return;
    _stickAxis.setValues(x, y);
    _recomputeMoveAxis();
  }

  /// Adds view movement. Called once per mouse event or once per drag update;
  /// the values pile up until a step takes them.
  void addLook(double dx, double dy) {
    if (muted) return;
    _lookDelta.setValues(_lookDelta.x + dx, _lookDelta.y + dy);
  }

  void requestSlot(int slot) {
    if (muted) return;
    _slotRequest = slot;
  }

  /// Drops everything, held state included.
  ///
  /// For losing focus. A key that was down when the window went away never
  /// produces its key-up, so without this the player walks into a wall forever
  /// after alt-tabbing.
  void clear() {
    _held.clear();
    _holds.clear();
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
