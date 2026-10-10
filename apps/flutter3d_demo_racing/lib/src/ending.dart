/// How the season ends.
///
/// **It did not.** Winning the fifth circuit put `Season complete — press R to
/// race it again` across the middle of the screen and left the race running
/// underneath it for ever: nothing calls `moveOn` after the last circuit, so
/// the car went on driving a race that was over, behind a caption, while the
/// engine noise carried on. That caption is the whole of what this game had to
/// say about finishing it — no lap count, no best lap, no list of the circuits
/// won, and no credits.
///
/// The shape is `EndingSheet`'s, from `flutter3d_game_ui/screens.dart`, which the
/// platformer and the crypt end on too: three games whose endings were each
/// laid out by hand were three designs where there is one decision. What is
/// here is the season's sentence and its three numbers.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_game_ui/screens.dart';

import 'credits.dart';
import 'race_readout.dart';

/// The end of the season: what the driving came to, and who made the car.
class SeasonEnding extends StatelessWidget {
  const SeasonEnding({
    super.key,
    required this.circuits,
    required this.laps,
    required this.bestLap,
    this.touch = false,
  });

  /// Circuits won this season. Five is the whole of it — see [Season].
  final int circuits;

  /// Laps driven across all of them.
  final int laps;

  /// The quickest of those laps, or null if the season somehow held none.
  ///
  /// The season's own, not the record on disk: `GhostKeeper.record` is what has
  /// ever been driven here across every evening, and a screen that reported it
  /// at the end of a slow season would congratulate a driver on somebody
  /// else's lap.
  final double? bestLap;

  /// Whether the player has fingers rather than a keyboard.
  ///
  /// Passed in rather than read from `Playing`, so a test can pump this both
  /// ways: `flutter_test` reports itself as Android, and a widget that asked
  /// would only ever be seen one way.
  final bool touch;

  @override
  Widget build(BuildContext context) => EndingSheet(
    title: 'The season is yours.',
    tallies: <EndingTally>[
      EndingTally(circuits == 1 ? 'circuit' : 'circuits', '$circuits'),
      EndingTally(laps == 1 ? 'lap' : 'laps', '$laps'),
      // The null goes straight through: `formatLapTime` answers a lap nobody
      // drove with the same dashes the HUD's own line shows, and `0:00.000`
      // at the end of a season would read as a world record.
      EndingTally('best lap', formatLapTime(bestLap)),
    ],
    valueStyle: const TextStyle(
      color: Colors.white,
      fontSize: 28,
      fontWeight: FontWeight.w600,
      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
    ),
    credits: credits.models,
    creditsHeading: 'The car',
    // The same sentence the caption used to carry alone, and still the only
    // place the wording and the control that honours it are decided — see
    // [seasonCompleteNotice].
    again: seasonCompleteNotice(touch: touch),
  );
}
