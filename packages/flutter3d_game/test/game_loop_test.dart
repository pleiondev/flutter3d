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

/// An action this package does not ship, declared here because the point of
/// [GameAction] being open is that a caller can do exactly this.
const GameAction _shoot = GameAction('shoot');

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
        if (input.pressed(_shoot)) pressedIn.add(index);
        index++;
      },
    );

    input.press(_shoot);
    loop.advance(3.0 / 60.0);

    expect(pressedIn, <int>[
      0,
    ], reason: 'the press was still latched on a later step');
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

  group('the longest frame', () {
    test('a window that was dragged does not arrive as a hundred steps', () {
      // **Not a slow frame — a laptop that was shut, or a debugger sitting at a
      // breakpoint.** Handing fifteen seconds to a fixed step is fifteen seconds
      // of simulation in one frame, which arrives as everything in the world
      // teleporting.
      final loop = build();

      final steps = loop.advance(15.0);

      expect(steps, lessThanOrEqualTo((0.25 * 60).ceil()));
      expect(loop.lastFrame, 0.25);
    });

    test('and an ordinary frame passes through untouched', () {
      final loop = build();

      loop.advance(1 / 60);

      expect(loop.lastFrame, closeTo(1 / 60, 1e-9));
    });

    test('and what it accepted is what everything else in the frame gets', () {
      // **The bug this exists for.** All three games advanced their particles
      // with the raw frame time one line after clamping the simulation's — so
      // after a hitch the smoke was somewhere the car had not been. Nothing
      // else has to remember to clamp now, and nothing gets to clamp it
      // differently.
      final loop = build();

      loop.advance(9.0);

      expect(loop.lastFrame, loop.longestFrame);
    });

    test('and a paused frame took no time at all', () {
      // Run one real frame first: a loop that has never advanced reports zero
      // anyway, so pausing a fresh one proves nothing — which is how the first
      // version of this test passed with the line it was written for deleted.
      final loop = build();
      loop.advance(1 / 60);
      expect(loop.lastFrame, greaterThan(0.0));

      loop.paused = true;
      loop.advance(1 / 60);

      expect(
        loop.lastFrame,
        0.0,
        reason: 'the world stood still and the smoke did not',
      );
    });

    test('and a frame of nothing is a frame of nothing', () {
      // `Duration.zero` on the first tick, and a `NaN` from a clock that has
      // been asked what time it was before it started.
      final loop = build();

      loop.advance(double.nan);

      expect(loop.lastFrame, 0.0);
    });
  });

  test('alpha comes from the clock rather than being recomputed', () {
    final loop = build();
    loop.advance(1.5 / 60.0);
    expect(loop.alpha, closeTo(0.5, 1e-6));
  });

  group('paused', () {
    test('runs nothing, and does not report a stall that did not happen', () {
      // The interesting half. An implementation that accumulated the time and
      // then dropped the backlog would also work — and would report ten
      // seconds of dropped steps, through a counter kept precisely so that a
      // real stall is noticeable.
      //
      // Mutation: let the clock have the time while paused. `droppedSteps`
      // goes up and this fails.
      final loop = build()..paused = true;

      expect(loop.advance(10.0), 0);
      expect(looksSeen, isEmpty);
      expect(
        loop.clock.droppedSteps,
        0,
        reason:
            'ten seconds behind a menu was reported as a performance '
            'problem',
      );
    });

    test('resuming does not run the time the pause took', () {
      // Mutation: drop the `clock.reset()` on the resume edge. Without it the
      // accumulator is whatever was left when the pause began, which is a
      // fraction of a step — so make the pause itself the thing that would
      // burst, by leaving a nearly-full accumulator behind.
      final loop = build();
      loop.advance(0.9 / 60.0);
      expect(looksSeen, isEmpty, reason: 'not enough for a step yet');

      loop.paused = true;
      loop.advance(5.0);
      loop.paused = false;

      // The 0.9 of a step that was waiting is gone with the pause: none of that
      // time happened in the game.
      expect(loop.advance(0.5 / 60.0), 0);
      expect(loop.advance(0.6 / 60.0), 1);
    });

    test('a press taken while paused does not reach the first step after', () {
      // The key that unpauses would otherwise also fire the weapon.
      final loop = build();
      loop.paused = true;
      input.press(_shoot);
      loop.advance(1.0 / 60.0);

      final firedIn = <int>[];
      var index = 0;
      final counting = GameLoop(
        input: input,
        clock: FixedStep(),
        onStep: (double dt) {
          if (input.pressed(_shoot)) firedIn.add(index);
          index++;
        },
      );
      counting.advance(2.0 / 60.0);

      expect(firedIn, isEmpty);
    });

    test('a key still held when the game comes back is still held', () {
      // The other half: a latch is an event and being held is a condition.
      final loop = build();
      input.press(GameAction.sprint);

      loop.paused = true;
      loop.advance(1.0);
      loop.paused = false;

      final heldIn = <bool>[];
      final counting = GameLoop(
        input: input,
        clock: FixedStep(),
        onStep: (double dt) => heldIn.add(input.held(GameAction.sprint)),
      );
      counting.advance(1.0 / 60.0);

      expect(heldIn, <bool>[true]);
    });

    test('motion behind a menu is thrown away rather than saved up', () {
      // The opposite of what a frame too short to step does, and the difference
      // is how long the wait is: a pause can last minutes, and the motion would
      // arrive as one turn of the camera on the frame the game came back.
      final loop = build()..paused = true;
      look.add(500.0, 0.0);

      loop.advance(1.0 / 60.0);
      expect(look.drains, 1, reason: 'the motion was left to pile up');

      loop.paused = false;
      expect(loop.advance(1.0 / 60.0), 1);
      expect(
        looksSeen.single,
        0.0,
        reason:
            'five hundred pixels of menu-time mouse movement turned the '
            'camera on the frame the game resumed',
      );
    });
  });
}
