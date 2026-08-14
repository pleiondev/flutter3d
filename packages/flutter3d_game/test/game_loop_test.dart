/// The four lines that tie the clock, the input and the simulation together.
///
/// `GameLoop` is nine lines of logic and had no test at all, which is the worst
/// ratio in the package: it is small enough to look obviously right and it owns
/// three decisions that live nowhere else. Its own doc says as much — *"the
/// order of the four things it does is the part that is easy to get wrong, and
/// every place that drives a simulation would otherwise have to get it right
/// again"*.
///
/// Each test below was written by breaking the thing it covers first. The
/// mutation that would defeat it is named in the test.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A look source that hands over whatever it has accumulated and empties.
///
/// The real one is the mouse-capture plugin. What matters here is the same
/// contract: taking the motion is destructive, so a loop that takes it and
/// then discards it has lost it for good.
final class _Look {
  double x = 0.0;
  double y = 0.0;
  int drains = 0;

  void add(double dx, double dy) {
    x += dx;
    y += dy;
  }

  void drain(Vector2 out) {
    drains++;
    out.setValues(x, y);
    x = 0.0;
    y = 0.0;
  }
}

void main() {
  late InputState input;
  late _Look look;
  late List<double> looksSeen;

  GameLoop build({double stepSeconds = 1.0 / 60.0}) {
    input = InputState();
    look = _Look();
    looksSeen = <double>[];
    return GameLoop(
      input: input,
      clock: FixedStep(stepSeconds: stepSeconds),
      drainLook: look.drain,
      onStep: (double dt) {
        looksSeen.add(input.lookDelta.x);
      },
    );
  }

  test('a frame too short to run a step does not take the look', () {
    // The subtle one, and the reason `drainLook` sits below the guard. On a
    // display faster than the simulation most frames run no step at all;
    // draining there would take the motion and throw it away, and the view
    // would move at the simulation's rate minus whatever was swallowed.
    //
    // Mutation: hoist the drain above the `steps == 0` return. This fails.
    final loop = build();
    look.add(10.0, 0.0);

    expect(loop.advance(1.0 / 240.0), 0);
    expect(look.drains, 0, reason: 'the accumulator was emptied for nothing');
    expect(look.x, 10.0, reason: 'the motion has to still be there');

    // And it arrives, whole, on the frame that does run a step.
    expect(loop.advance(1.0 / 60.0), 1);
    expect(looksSeen.single, closeTo(10.0, 1e-9));
  });

  test('a frame worth three steps gives each step a third of the look', () {
    // Handing it all to the first step makes a frame that ran three steps turn
    // the camera in a single jerk, then sit still for two.
    //
    // Mutation: pass `_look.x` instead of `_look.x * perStep`. This fails on
    // the second and third entries.
    final loop = build();
    look.add(9.0, 0.0);

    expect(loop.advance(3.0 / 60.0), 3);
    expect(looksSeen, hasLength(3));
    for (final seen in looksSeen) {
      expect(seen, closeTo(3.0, 1e-9));
    }
  });

  test('the look is taken once for the frame, not once per step', () {
    final loop = build();
    look.add(6.0, 0.0);
    loop.advance(3.0 / 60.0);
    expect(look.drains, 1);
  });

  test('a press is seen by one step and not the next', () {
    // `beginStep`/`endStep` bracket every step, which is what makes a latch a
    // one-shot. Without the bracket a key tapped once fires a weapon three
    // times on a frame that ran three steps.
    //
    // Mutation: move `input.endStep()` outside the loop. This fails.
    final pressedIn = <int>[];
    var index = 0;
    input = InputState();
    look = _Look();
    final loop = GameLoop(
      input: input,
      clock: FixedStep(),
      drainLook: look.drain,
      onStep: (double dt) {
        if (input.pressed(GameAction.fire)) pressedIn.add(index);
        index++;
      },
    );

    input.press(GameAction.fire);
    loop.advance(3.0 / 60.0);

    expect(pressedIn, <int>[0],
        reason: 'the press was still latched on a later step');
  });

  test('held state survives every step of the frame', () {
    // The other half of the same rule: a latch is an event and being held is a
    // condition, so one is cleared per step and the other is not.
    final heldIn = <bool>[];
    input = InputState();
    look = _Look();
    final loop = GameLoop(
      input: input,
      clock: FixedStep(),
      drainLook: look.drain,
      onStep: (double dt) => heldIn.add(input.held(GameAction.sprint)),
    );

    input.press(GameAction.sprint);
    loop.advance(3.0 / 60.0);

    expect(heldIn, <bool>[true, true, true]);
  });

  test('a loop with no look source runs anyway', () {
    // `drainLook` is nullable, and a simulation driven from a test or from a
    // build with no pointer capture has none.
    var ran = 0;
    final loop = GameLoop(
      input: InputState(),
      clock: FixedStep(),
      onStep: (double dt) => ran++,
    );
    expect(loop.advance(2.0 / 60.0), 2);
    expect(ran, 2);
  });

  test('alpha comes from the clock rather than being recomputed', () {
    final loop = build();
    loop.advance(1.5 / 60.0);
    expect(loop.alpha, closeTo(0.5, 1e-6));
  });
}
