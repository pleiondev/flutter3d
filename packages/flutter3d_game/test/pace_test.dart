/// What happens when the machine cannot keep up.
///
///     flutter test test/pace_test.dart
///
/// **`FixedStep.droppedSteps` was read by nobody.** It has counted, since the
/// loop was written, the simulated time the machine was too slow to run — and
/// with nothing reading it, a game that fell behind ran in silent slow motion
/// and a run timer counting simulated seconds quietly stopped agreeing with the
/// clock on the wall.
///
/// **What a player is told about it is tested in the game that tells them.**
/// This file used to mount the platformer's HUD, which meant this package —
/// the one whose pubspec says in as many words that the dependency runs the
/// other way — dev-depended on a genre package *and on an application*, and
/// imported `package:flutter3d_demo_platformer/src/hud.dart`, another package's `lib/src`.
/// Three rules at once, in two lines, under a comment saying it was not so.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';

const double _step = 1.0 / 60.0;
const double _frame = 1.0 / 60.0;

/// Runs [frames] frames during which nothing is dropped.
void _smooth(Pace pace, int frames, {int from = 0}) {
  for (var i = 0; i < frames; i++) {
    pace.note(dropped: from, dt: _frame, stepSeconds: _step);
  }
}

void main() {
  group('Pace', () {
    test('a smooth run is never behind', () {
      final pace = Pace();
      _smooth(pace, 600);

      expect(pace.behind, isFalse);
      expect(pace.lost, 0.0);
    });

    test('one hitch is not a slow machine', () {
      // A garbage collection, or a window dragged between two monitors. Warning
      // about it teaches the player to ignore the warning.
      final pace = Pace();
      pace.note(dropped: 3, dt: 0.1, stepSeconds: _step);

      expect(pace.behind, isFalse);
      expect(pace.lost, closeTo(3 * _step, 1e-9));
    });

    test('but a run of them is', () {
      // Sixty dropped steps is a second of game that never happened.
      final pace = Pace();
      var dropped = 0;
      for (var i = 0; i < 12; i++) {
        dropped += 5;
        pace.note(dropped: dropped, dt: 0.1, stepSeconds: _step);
      }

      expect(pace.behind, isTrue);
      expect(pace.lost, closeTo(1.0, 1e-6));
    });

    test('and it forgets once the machine catches up', () {
      // The warning is about now, not about the whole run. What survives is
      // [lost], which is about the whole run.
      final pace = Pace();
      var dropped = 0;
      for (var i = 0; i < 12; i++) {
        dropped += 5;
        pace.note(dropped: dropped, dt: 0.1, stepSeconds: _step);
      }
      expect(pace.behind, isTrue);

      _smooth(pace, 600, from: dropped);

      expect(pace.behind, isFalse, reason: 'still complaining ten seconds on');
      expect(pace.lost, closeTo(1.0, 1e-6), reason: 'the run still lost it');
    });

    test('a level load is not the machine failing', () {
      // Reading a level takes far longer than a frame and drops simulated time
      // every time. Counting it would light the warning on every level of every
      // run, which is the same as not having one.
      final pace = Pace();
      pace.note(dropped: 120, dt: 2.0, stepSeconds: _step);
      pace.reset(120);

      expect(pace.behind, isFalse);
      expect(pace.lost, 0.0);
      // And the loop's total is not counted again on the next frame.
      pace.note(dropped: 120, dt: _frame, stepSeconds: _step);
      expect(pace.lost, 0.0);
    });
  });}
