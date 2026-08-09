import 'package:flutter3d_game/src/loop/fixed_step.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const step = 1.0 / 60.0;

  group('spending accumulated time', () {
    test('a frame shorter than a step runs nothing and keeps the time', () {
      final loop = FixedStep();

      expect(loop.advance(step / 3.0), 0);
      expect(loop.advance(step / 3.0), 0);
      // The three thirds together are one whole step, which is the point: time
      // must not be lost to rounding across a long session.
      expect(loop.advance(step / 3.0), 1);
    });

    test('a frame worth six steps runs exactly six', () {
      // A step of 1/16 s and a frame of 6/16 s, because both are exact in
      // binary. Asking for six steps out of 0.1 s at 1/60 s a step is a test of
      // whether the rounding happens to fall the right way, and it does not:
      // repeated subtraction leaves the accumulator a hair under the sixth step.
      // The real guarantee is that nothing drifts over a long run, and the
      // 144 Hz test below is the one that checks it.
      //
      // The ceiling is raised past six as well, or this would measure that
      // instead.
      final loop = FixedStep(stepSeconds: 0.0625, maxStepsPerFrame: 10);

      expect(loop.advance(0.375), 6);
    });

    test('leftover time carries into the next frame', () {
      final loop = FixedStep();

      expect(loop.advance(step * 1.5), 1);
      expect(loop.advance(step * 0.5), 1);
    });

    test('a long stall runs the ceiling, not the backlog', () {
      // Ten seconds is six hundred steps. Running them would take longer than
      // ten seconds and ask for more next frame, which is how a simulation
      // stops responding altogether.
      final loop = FixedStep();

      expect(loop.advance(10.0), 5);
    });

    test('the backlog is dropped rather than carried', () {
      final loop = FixedStep(stepSeconds: 0.0625);
      loop.advance(10.0);

      // If the excess were kept, this frame would still be paying it off.
      expect(loop.advance(0.0625), 1);
    });

    test('dropped time is reported instead of hidden', () {
      // Ten seconds at 1/16 s a step is 160 steps; five run and the rest go.
      final loop = FixedStep(stepSeconds: 0.0625);
      loop.advance(10.0);

      expect(loop.droppedSteps, 155);
    });

    test('a steady 60 Hz frame runs exactly one step', () {
      final loop = FixedStep();

      for (var i = 0; i < 100; i++) {
        expect(loop.advance(step), 1);
      }
    });

    test('a 144 Hz display averages out to the step rate', () {
      final loop = FixedStep();
      const frame = 1.0 / 144.0;

      var steps = 0;
      for (var i = 0; i < 1440; i++) {
        steps += loop.advance(frame);
      }

      // Ten seconds of frames is ten seconds of simulation, whatever the
      // display is doing. Within one step, because 1/144 and 1/60 are both
      // inexact in binary and 1440 additions of the first accumulate a little
      // error — the property worth guaranteeing is that it does not grow.
      expect(steps, closeTo(600, 1));
    });
  });

  group('the interpolation fraction', () {
    test('stays in [0, 1) whatever the frame time', () {
      final loop = FixedStep();
      var time = 0.0;

      for (var i = 0; i < 500; i++) {
        // Deliberately ragged: a real frame time is never a clean divisor.
        time += 0.001;
        loop.advance(time % 0.037);
        expect(loop.alpha, greaterThanOrEqualTo(0.0));
        expect(loop.alpha, lessThan(1.0));
      }
    });

    test('is zero when time divides evenly into steps', () {
      final loop = FixedStep();
      loop.advance(step * 3);

      expect(loop.alpha, closeTo(0.0, 1e-9));
    });

    test('is the leftover fraction of a step', () {
      final loop = FixedStep();
      loop.advance(step * 2.5);

      expect(loop.alpha, closeTo(0.5, 1e-9));
    });

    test('survives the ceiling being hit', () {
      final loop = FixedStep();
      loop.advance(10.0);

      expect(loop.alpha, greaterThanOrEqualTo(0.0));
      expect(loop.alpha, lessThan(1.0));
    });
  });

  group('bad input', () {
    test('a negative frame time changes nothing', () {
      final loop = FixedStep();
      loop.advance(step * 0.5);

      expect(loop.advance(-1.0), 0);
      // The half step is still there, not cancelled out.
      expect(loop.advance(step * 0.5), 1);
    });

    test('a non-finite frame time does not poison the accumulator', () {
      final loop = FixedStep();

      expect(loop.advance(double.nan), 0);
      expect(loop.advance(double.infinity), 0);
      expect(loop.advance(step), 1);
      expect(loop.alpha, closeTo(0.0, 1e-9));
    });

    test('zero is a legal frame time', () {
      final loop = FixedStep();

      expect(loop.advance(0.0), 0);
    });
  });

  group('configuration', () {
    test('a different step size is honoured', () {
      // 1/8 s and 4/8 s, exact in binary for the same reason as above.
      final loop = FixedStep(stepSeconds: 0.125);

      expect(loop.advance(0.5), 4);
    });

    test('a different ceiling is honoured', () {
      final loop = FixedStep(maxStepsPerFrame: 2);

      expect(loop.advance(1.0), 2);
    });
  });

  group('reset', () {
    test('drops pending time, because a pause did not happen in the game', () {
      final loop = FixedStep();
      loop.advance(step * 0.9);
      loop.reset();

      expect(loop.advance(step * 0.2), 0);
      expect(loop.alpha, closeTo(0.2, 1e-9));
    });
  });
}
