import 'package:flutter3d_game/src/input/game_action.dart';
import 'package:flutter3d_game/src/input/input_state.dart';
import 'package:flutter_test/flutter_test.dart';

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
      input.press(GameAction.fire);
      input.release(GameAction.fire);

      input.beginStep();
      expect(input.pressed(GameAction.fire), isTrue);
      expect(input.released(GameAction.fire), isTrue);
      expect(input.held(GameAction.fire), isFalse);
      input.endStep();
    });

    test('several taps between steps collapse into one press', () {
      // Not ideal, but honest: the alternative is a queue, and nobody fires
      // three shots by tapping inside sixteen milliseconds on purpose.
      input.press(GameAction.fire);
      input.release(GameAction.fire);
      input.press(GameAction.fire);
      input.release(GameAction.fire);

      input.beginStep();
      expect(input.pressed(GameAction.fire), isTrue);
      input.endStep();

      input.beginStep();
      expect(input.pressed(GameAction.fire), isFalse);
      input.endStep();
    });

    test('holding across many steps produces one press and stays held', () {
      input.press(GameAction.fire);

      var presses = 0;
      for (var i = 0; i < 10; i++) {
        input.beginStep();
        if (input.pressed(GameAction.fire)) presses++;
        expect(input.held(GameAction.fire), isTrue);
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

    test('survives a step boundary, because it is a condition not an event', () {
      input.press(GameAction.moveForward);

      input.beginStep();
      input.endStep();

      expect(input.moveAxis.y, 1.0);
    });
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
      input.requestWeapon(3);

      input.beginStep();
      expect(input.weaponRequest, 3);
      input.endStep();

      expect(input.weaponRequest, isNull);
    });

    test('the most recent request inside one frame wins', () {
      input.requestWeapon(1);
      input.requestWeapon(2);

      expect(input.weaponRequest, 2);
    });

    test('is null when nothing was asked for', () {
      expect(input.weaponRequest, isNull);
    });
  });

  group('losing focus', () {
    test('clear drops held state, or the player walks into a wall forever', () {
      // A key that was down when the window went away never sends its key-up.
      input.press(GameAction.moveForward);
      input.addLook(10.0, 10.0);
      input.requestWeapon(2);

      input.clear();

      expect(input.held(GameAction.moveForward), isFalse);
      expect(input.moveAxis.y, 0.0);
      expect(input.lookDelta.x, 0.0);
      expect(input.weaponRequest, isNull);
    });

    test('clear also drops the stick, which reports nothing on release', () {
      input.setStickAxis(1.0, 1.0);

      input.clear();

      expect(input.moveAxis.length, 0.0);
    });
  });
}
