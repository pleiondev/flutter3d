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
/// The shape is the platformer's `Ending`, and the crypt's, for the reason
/// given there: three games in one repository whose endings are each laid out
/// differently is three designs where there is one decision.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_app/flutter3d_app.dart'; // CreditsSection

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
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black.withValues(alpha: 0.86),
    child: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'The season is yours.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 20),
              // `Wrap` and not `Row`: three tallies at a large text size is a
              // row that runs off a handset held in landscape.
              Wrap(
                spacing: 28,
                runSpacing: 12,
                children: <Widget>[
                  _Tally(
                    label: circuits == 1 ? 'circuit' : 'circuits',
                    value: '$circuits',
                  ),
                  _Tally(label: laps == 1 ? 'lap' : 'laps', value: '$laps'),
                  // The null goes straight through: `formatLapTime` answers a
                  // lap nobody drove with the same dashes the HUD's own line
                  // shows, and `0:00.000` at the end of a season would read as
                  // a world record.
                  _Tally(label: 'best lap', value: formatLapTime(bestLap)),
                ],
              ),
              const SizedBox(height: 26),
              const CreditsSection(credits: Credits.models, heading: 'The car'),
              const SizedBox(height: 22),
              Text(
                // The same sentence the caption used to carry alone, and still
                // the only place the wording and the control that honours it
                // are decided — see [seasonCompleteNotice].
                seasonCompleteNotice(touch: touch),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 14,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// One number and what it counts, read as one thing.
class _Tally extends StatelessWidget {
  const _Tally({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label $value',
    excludeSemantics: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w600,
            fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 12,
            letterSpacing: 2,
          ),
        ),
      ],
    ),
  );
}
