import 'package:flutter3d_sim/src/input/game_action.dart';
import 'package:flutter3d_sim/src/input/input_state.dart';
import 'package:test/test.dart';

/// An action this package does not ship, declared here because the point of
/// [GameAction] being open is that a caller can do exactly this.
const GameAction _shoot = GameAction('shoot');

/// What a comparison against a `Vector2` can actually be held to.
///
/// `vector_math` stores its vectors in a `Float32List`, so anything written
/// through one comes back rounded to single precision — `0.3` and `0.4` give a
/// length of `0.500000011920929`, not `0.5`. Nothing to fix, but a tolerance of
/// `1e-9` is unreachable by construction and asserting it only produces a test
/// that looks strict and is merely wrong.
const double _float32Epsilon = 1e-6;

void main() {
  late InputState input;

  setUp(() => input = InputState());

  group('latching presses', () {
    test('a press is held until a step consumes it', () {
      input.press(GameAction.jump);

      expect(input.pressed(GameAction.jump), isTrue);
      expect(input.held(GameAction.jump), isTrue);
    });

    test('a press reads true for exactly one step', () {
      input.press(GameAction.jump);

      input.beginStep();
      expect(input.pressed(GameAction.jump), isTrue);
      input.endStep();

      input.beginStep();
      expect(input.pressed(GameAction.jump), isFalse);
      // Still physically down — the edge is gone, the condition is not.
      expect(input.held(GameAction.jump), isTrue);
      input.endStep();
    });

    test('a tap entirely between two steps is not lost', () {
      // The failure this guards against gets worse as the frame rate drops,
      // which is exactly when the player is least willing to forgive it.
      input.press(_shoot);
      input.release(_shoot);

      input.beginStep();
      expect(input.pressed(_shoot), isTrue);
      expect(input.released(_shoot), isTrue);
      expect(input.held(_shoot), isFalse);
      input.endStep();
    });

    test('several taps between steps collapse into one press', () {
      // Not ideal, but honest: the alternative is a queue, and nobody fires
      // three shots by tapping inside sixteen milliseconds on purpose.
      input.press(_shoot);
      input.release(_shoot);
      input.press(_shoot);
      input.release(_shoot);

      input.beginStep();
      expect(input.pressed(_shoot), isTrue);
      input.endStep();

      input.beginStep();
      expect(input.pressed(_shoot), isFalse);
      input.endStep();
    });

    test('holding across many steps produces one press and stays held', () {
      input.press(_shoot);

      var presses = 0;
      for (var i = 0; i < 10; i++) {
        input.beginStep();
        if (input.pressed(_shoot)) presses++;
        expect(input.held(_shoot), isTrue);
        input.endStep();
      }

      expect(presses, 1);
    });

    test('a release is latched the same way as a press', () {
      input.press(GameAction.sprint);
      input.beginStep();
      input.endStep();

      input.release(GameAction.sprint);
      input.beginStep();
      expect(input.released(GameAction.sprint), isTrue);
      expect(input.held(GameAction.sprint), isFalse);
      input.endStep();

      input.beginStep();
      expect(input.released(GameAction.sprint), isFalse);
      input.endStep();
    });
  });

  group('the movement axis', () {
    test('is zero with nothing held', () {
      expect(input.moveAxis.x, 0.0);
      expect(input.moveAxis.y, 0.0);
    });

    test('forward is positive y, right is positive x', () {
      input.press(GameAction.moveForward);
      expect(input.moveAxis.y, 1.0);

      input.release(GameAction.moveForward);
      input.press(GameAction.moveRight);
      expect(input.moveAxis.x, 1.0);
    });

    test('opposite keys cancel', () {
      input.press(GameAction.moveForward);
      input.press(GameAction.moveBack);

      expect(input.moveAxis.y, 0.0);
    });

    test('diagonal movement is not faster than straight movement', () {
      // The oldest speed exploit there is: unclamped, holding two keys moves
      // about 1.41 times as fast as holding one.
      input.press(GameAction.moveForward);
      input.press(GameAction.moveRight);

      expect(input.moveAxis.length, closeTo(1.0, _float32Epsilon));
    });

    test('a stick shorter than full deflection is left alone', () {
      // Clamping only guards the ceiling. An analogue stick pushed halfway must
      // still mean half speed, or a touch build loses all its walking speeds.
      input.setStickAxis(0.3, 0.4);

      expect(input.moveAxis.length, closeTo(0.5, _float32Epsilon));
    });

    test('a stick and the keyboard combine, still clamped', () {
      input.setStickAxis(1.0, 0.0);
      input.press(GameAction.moveForward);

      expect(input.moveAxis.length, closeTo(1.0, _float32Epsilon));
    });

    test(
      'survives a step boundary, because it is a condition not an event',
      () {
        input.press(GameAction.moveForward);

        input.beginStep();
        input.endStep();

        expect(input.moveAxis.y, 1.0);
      },
    );
  });

  group('view movement', () {
    test('accumulates every event since the last step', () {
      input.addLook(3.0, -1.0);
      input.addLook(2.0, 4.0);

      expect(input.lookDelta.x, 5.0);
      expect(input.lookDelta.y, 3.0);
    });

    test('is cleared by the step that consumed it', () {
      input.addLook(5.0, 5.0);

      input.beginStep();
      expect(input.lookDelta.x, 5.0);
      input.endStep();

      expect(input.lookDelta.x, 0.0);
      expect(input.lookDelta.y, 0.0);
    });

    test('motion during a step is kept for the next one', () {
      // A mouse event landing mid-step belongs to the step after it, not to
      // nowhere.
      input.beginStep();
      input.endStep();
      input.addLook(2.0, 2.0);

      input.beginStep();
      expect(input.lookDelta.x, 2.0);
      input.endStep();
    });
  });

  group('weapon selection', () {
    test('is reported to the step that follows it', () {
      input.requestSlot(3);

      input.beginStep();
      expect(input.slotRequest, 3);
      input.endStep();

      expect(input.slotRequest, isNull);
    });

    test('the most recent request inside one frame wins', () {
      input.requestSlot(1);
      input.requestSlot(2);

      expect(input.slotRequest, 2);
    });

    test('is null when nothing was asked for', () {
      expect(input.slotRequest, isNull);
    });
  });

  group('losing focus', () {
    test('clear drops held state, or the player walks into a wall forever', () {
      // A key that was down when the window went away never sends its key-up.
      input.press(GameAction.moveForward);
      input.addLook(10.0, 10.0);
      input.requestSlot(2);

      input.clear();

      expect(input.held(GameAction.moveForward), isFalse);
      expect(input.moveAxis.y, 0.0);
      expect(input.lookDelta.x, 0.0);
      expect(input.slotRequest, isNull);
    });

    test('clear also drops the stick, which reports nothing on release', () {
      input.setStickAxis(1.0, 1.0);

      input.clear();

      expect(input.moveAxis.length, 0.0);
    });
  });

  group('an action with a magnitude', () {
    // **A trigger is not a button and not a stick**, and until this existed the
    // input layer had no word for it: the racing game read `held(throttle)` and
    // turned an analogue pedal into an on-off switch.
    test('a held action with nothing to say is fully asked for', () {
      // The compatibility promise. Every existing caller can read `value`
      // instead of `held` and behave identically, which is what makes it safe
      // to use everywhere.
      final input = InputState()..press(GameAction.jump);

      expect(input.value(GameAction.jump), 1.0);
      expect(input.value(GameAction.sprint), 0.0);
    });

    test('and a device that can measure says how far', () {
      final input = InputState()..setActionValue(GameAction.sprint, 0.42);

      expect(input.value(GameAction.sprint), closeTo(0.42, 1e-9));
    });

    test('a magnitude is not a press, and nought is not a release', () {
      // Independent on purpose: a game may want the threshold, the proportion,
      // or each in a different place, so a device reports both and neither
      // implies the other.
      final input = InputState()..setActionValue(GameAction.sprint, 0.9);

      expect(
        input.held(GameAction.sprint),
        isFalse,
        reason:
            'a magnitude decided what "pressed" means, which is the '
            "game's decision and not the device's",
      );

      input
        ..press(GameAction.sprint)
        ..setActionValue(GameAction.sprint, 0.0);
      expect(
        input.held(GameAction.sprint),
        isTrue,
        reason: 'a trigger returning to rest released the action by itself',
      );
    });

    test('it survives a step, because it is a condition and not an event', () {
      // The same rule the stick axis follows, and for the same reason: a
      // trigger held at half is still held at half on the next step.
      final input = InputState()..setActionValue(GameAction.sprint, 0.5);

      input
        ..beginStep()
        ..endStep();

      expect(input.value(GameAction.sprint), closeTo(0.5, 1e-9));
    });

    test('and losing focus drops it', () {
      // Mutation: leave `_values` alone in `clear()`. A player who alt-tabs
      // while pulling the trigger comes back to a car at full throttle.
      final input = InputState()..setActionValue(GameAction.sprint, 1.0);

      input.clear();

      expect(input.value(GameAction.sprint), 0.0);
    });

    test('and it is bounded, because a device may lie', () {
      final input = InputState()
        ..setActionValue(GameAction.sprint, 1.4)
        ..setActionValue(GameAction.jump, -0.3);

      expect(input.value(GameAction.sprint), 1.0);
      expect(input.value(GameAction.jump), 0.0);
    });

    test('a magnitude does not move the player', () {
      // Movement is already analogue through the stick. Folding a trigger into
      // the move axis would make the throttle a direction.
      final input = InputState()..setActionValue(GameAction.moveForward, 1.0);

      expect(input.moveAxis.y, 0.0);
    });
  });

  group('two things holding one action', () {
    test('lifting one of them keeps it held', () {
      // **A bug that shipped.** `W` and the up arrow are both bound to walking
      // forward, and a player holding both who lifted one stopped dead — a set
      // has no idea how many fingers are on it. Same again for a hand on the
      // keyboard and a thumb on a pad, which is where this was noticed.
      final input = InputState()
        ..press(GameAction.moveForward)
        ..press(GameAction.moveForward);

      input.release(GameAction.moveForward);

      expect(input.held(GameAction.moveForward), isTrue);
    });

    test('and the release is not announced either', () {
      // A game that ends a variable-height jump on `released` would cut it
      // short the moment either of two bound buttons came up.
      final input = InputState()
        ..press(GameAction.jump)
        ..press(GameAction.jump);

      input.release(GameAction.jump);

      expect(input.released(GameAction.jump), isFalse);
    });

    test('and lifting the last one does release it', () {
      final input = InputState()
        ..press(GameAction.jump)
        ..press(GameAction.jump)
        ..release(GameAction.jump)
        ..release(GameAction.jump);

      expect(input.held(GameAction.jump), isFalse);
      expect(input.released(GameAction.jump), isTrue);
    });

    test('and the movement axis agrees with the count', () {
      final input = InputState()
        ..press(GameAction.moveForward)
        ..press(GameAction.moveForward)
        ..release(GameAction.moveForward);

      expect(input.moveAxis.y, 1.0);
    });

    test('and a release with nothing held is still a release', () {
      // What a key-up arriving after `clear()` looks like: focus went away, the
      // state was dropped, and the key the player was holding reports up when
      // the window comes back. It must not go negative and hold the action for
      // ever afterwards.
      final input = InputState()..release(GameAction.jump);

      expect(input.held(GameAction.jump), isFalse);
      expect(input.released(GameAction.jump), isTrue);

      input
        ..press(GameAction.jump)
        ..release(GameAction.jump);
      expect(input.held(GameAction.jump), isFalse);
    });
  });

  group('an action that latches instead of being held', () {
    // **The accommodation every guideline names first and nearly every game
    // omits.** Sprinting is held, and holding a key for the length of a climb is
    // a real barrier for a player with limited grip or a tremor.

    test('a press turns it on and stays on', () {
      final input = InputState()..setToggled(GameAction.sprint, toggled: true);

      input
        ..press(GameAction.sprint)
        ..release(GameAction.sprint);

      expect(
        input.held(GameAction.sprint),
        isTrue,
        reason: 'the release is what a latch is for ignoring',
      );
    });

    test('and the next press turns it off', () {
      final input = InputState()..setToggled(GameAction.sprint, toggled: true);

      input
        ..press(GameAction.sprint)
        ..release(GameAction.sprint)
        ..press(GameAction.sprint)
        ..release(GameAction.sprint);

      expect(input.held(GameAction.sprint), isFalse);
      expect(
        input.released(GameAction.sprint),
        isTrue,
        reason: 'a simulation watching for the edge still sees one',
      );
    });

    test('and it latches from whichever device pressed it', () {
      // The reason this is in `InputState` and not in a translator: a keyboard,
      // a pad and a thumb must all latch the same action, and three copies would
      // be three that disagree.
      final input = InputState()..setToggled(GameAction.sprint, toggled: true);

      input.press(GameAction.sprint);
      expect(input.held(GameAction.sprint), isTrue);

      // As a second device would: a fresh press, no matching release.
      input.press(GameAction.sprint);
      expect(input.held(GameAction.sprint), isFalse);
    });

    test('and losing focus lets go of it', () {
      // A player who alt-tabs mid-climb must not come back sprinting into a
      // wall. Held state dies with focus, latched or not.
      final input = InputState()..setToggled(GameAction.sprint, toggled: true);
      input.press(GameAction.sprint);

      input.clear();

      expect(input.held(GameAction.sprint), isFalse);
    });

    test('but the choice of what latches survives it', () {
      // A setting, not state. Making a player set it again because a window lost
      // focus would be the accommodation failing in the one moment it matters.
      final input = InputState()..setToggled(GameAction.sprint, toggled: true);

      input.clear();

      expect(input.isToggled(GameAction.sprint), isTrue);
      input.press(GameAction.sprint);
      input.release(GameAction.sprint);
      expect(input.held(GameAction.sprint), isTrue);
    });

    test('and turning the setting off does not leave it stuck on', () {
      // **The mutation this exists for.** The key that would have released it is
      // up already and the press that would have flipped it is not coming, so a
      // sprint left on here is a sprint nothing can turn off.
      final input = InputState()..setToggled(GameAction.sprint, toggled: true);
      input.press(GameAction.sprint);

      input.setToggled(GameAction.sprint, toggled: false);

      expect(input.held(GameAction.sprint), isFalse);
    });

    test('and an ordinary action is untouched by any of it', () {
      final input = InputState()..setToggled(GameAction.sprint, toggled: true);

      input
        ..press(GameAction.jump)
        ..release(GameAction.jump);

      expect(input.held(GameAction.jump), isFalse);
    });
  });
}
