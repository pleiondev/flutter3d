/// A match played twice, and now it is the same match wherever it is played.
///
///     flutter test test/parity_test.dart
///     flutter test --platform chrome test/parity_test.dart
///
/// **`match_test.dart` already replays a match, and this is a different
/// question.** That file plays a run, records the order tape, and plays the tape
/// back into a fresh map in the same process; what it proves is that the tape
/// carries everything a step reads. It cannot say whether the *arithmetic*
/// agrees between two machines, because both of its runs happen on the same one.
/// This file writes the answer down instead: forty checkpoints, committed, and
/// any platform that disagrees says which one it disagreed at first.
///
/// **Which matters here sooner than it does in the other genres.** A crowd on a
/// hillside is where a networked match would live, and a networked match is a
/// server replaying what a client sent: the run is only evidence if the two
/// arrive at the same world. The racer next door is the cautionary tale — its
/// tyre curve reached the platform's transcendentals and drove a measurably
/// different car in a browser, at twenty-three checkpoints of forty. A digest
/// trace is what turned that from "it does not match" into "it stopped matching
/// at step 75", and that is the whole reason this is a trace rather than one
/// number at the end.
///
/// **The scenario is the mirror, not a document.** `mirror` in `match_test.dart`
/// stages two camps on a flat field out of numbers written here, so what is
/// being measured is the step: the separation push, the flow field, the fog
/// lattice, the harvest loop and the production timer, each of them run a
/// thousand times. A map read from a file would put a document reader between
/// the measurement and the thing measured, and the demo's own map is not this
/// package's to reach for.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:flutter_test/flutter_test.dart';

import 'match_test.dart' show mirror;

/// The step `match_test.dart` plays at, kept the same so the two files describe
/// one match rather than two arrangements that happen to share a mirror.
const double _step = 1.0 / 30.0;

void main() {
  group('a thousand steps of a match', () {
    test('is the match that was recorded, wherever it is played', () {
      final DigestTrace trace = _play();
      final Divergence? divergence = trace.divergenceFromHex(_recorded);
      expect(
        divergence,
        isNull,
        reason:
            'this platform played a different match: $divergence. Everything a '
            'step here reaches for is meant to be pinned — `GameRandom` for the '
            'dice and `Portable` for the arithmetic, which the structure rule '
            '`a step asks no machine for an answer` holds the call sites of — '
            'so check that rule before this file: a step that has started '
            'asking `dart:math` for a sine is the difference, and moving a '
            'number below to make this green would only hide it.',
      );
    });

    test('and playing it twice in one process gives the same match twice', () {
      // The floor under the test above. Without it a run that was merely
      // unstable in one process would read as a platform difference, and the
      // table would be re-recorded to chase it.
      expect(_play().digests, _play().digests);
    });

    test('and a seam moved is a different match', () {
      // The companion every recorded trace needs: a comparison that cannot fail
      // is a comparison that proves nothing. Fourteen metres of extra walk for
      // one side, and the two runs part company.
      expect(_play().digests, isNot(_play(seamTwo: 34.0).digests));
    });
  });
}

/// Plays a mirror and digests the whole match every [every] steps.
///
/// **The save is taken only at a checkpoint**, which the racing parity file has
/// no reason to bother with and this one does: a car is a dozen numbers and a
/// match is every unit, every building, every seam and a fog lattice, so saving
/// on each of a thousand steps would cost more than the steps do. What is
/// digested is `Match.save` rather than a list of fields somebody thought of —
/// the same argument `match_test.dart` gives for comparing the bytes of a save:
/// a field added to the world is in the comparison the same afternoon, and a
/// hand-made digest goes on passing without it.
DigestTrace _play({double seamTwo = 20.0, int steps = 1200, int every = 30}) {
  final Match match = mirror(seamTwo: seamTwo, target: 10000.0);
  final trace = DigestTrace(every: every);
  for (var step = 1; step <= steps; step++) {
    match.step(_step);
    if (step % every == 0) trace.observe(step, match.save().data);
  }
  return trace;
}

/// Recorded on macOS-arm64 under the VM, 2026-09-08, and matched by Chrome on
/// the same machine the same day — forty of forty, first time, with no number
/// below moved to earn it.
///
/// **One accepted table, and it is worth saying that it was one from the
/// start.** The racer had to carry two for a while because its tyre curve
/// reached the platform's own transcendentals, and the pair *was* the finding.
/// Nothing a step does here asks a machine for an answer, so a second table
/// would be a defect rather than a platform.
///
/// A target of ten thousand, so the match is still running at step twelve
/// hundred: a trace whose last checkpoints are all of a finished match is a
/// trace measuring a world that has stopped moving. `mirror` runs both sides on
/// one policy from one arrangement, so the run underneath these numbers is also
/// the fairness case — the two sides stay level, and a step that favoured
/// whichever side it walked first would show up here as well as there.
const List<String> _recorded = <String>[
  '4bf7e8cb',
  '270ca193',
  '3b5d7d0d',
  '41bf1a68',
  'd266d559',
  '9c4e1e2e',
  '8a7fe96e',
  '91377bbd',
  'ee182ff4',
  '4879ba73',
  '78d59d38',
  '226f06e9',
  '51349317',
  'f7c6be40',
  '8131043e',
  '0297b501',
  '9e40236b',
  '83f15782',
  '1df8c05e',
  '8d03801e',
  'cf36f147',
  'c8ac928f',
  '7c369fc5',
  '1d8cd2e4',
  '6d6f95ab',
  'a8e3845e',
  '34a8310f',
  '97db9317',
  'c79f8391',
  '2fd41325',
  '18203ac1',
  'e3ab4456',
  'd24e9a9c',
  '481c10c3',
  'f9148c66',
  '6e18599d',
  '6a66fff7',
  '67f5e079',
  '5d241ffe',
  '5be26087',
];
