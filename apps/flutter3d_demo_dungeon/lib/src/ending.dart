/// How the crypt ends.
///
/// **It did not.** Walking out of the sanctum — the fifth level, the three
/// tanks, the last thing in the game — put `You are out.` over the corridor
/// for three seconds and then left the player standing in a finished level
/// with the crosshair still up. No statement that the game was over, nothing
/// about what the crawl had cost, no credits, and nothing to press: the only
/// way back to the start was R, which nothing on screen mentioned, or closing
/// the application.
///
/// The shape is the platformer's [Ending], deliberately. Two games in one
/// repository whose endings are laid out differently is two designs where
/// there is one decision, and the platformer's was argued out already: a
/// full-screen sheet rather than a panel over the level, because the level is
/// behind it and this is the moment to stop looking at the level; the tallies
/// the genre is actually played for; the credits, because the licence puts
/// them where the work is; and one line saying how to play again, in words
/// this build can honour.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_app/flutter3d_app.dart'; // clockText, CreditsSection

import 'credits.dart';

/// How a player is told to start again, in words the build they are on has.
///
/// A function rather than a ternary inside the widget, for the reason
/// `seasonCompleteNotice` in the racing game is one: the wording and the
/// control it names must not be able to drift apart, and this way the claim
/// can be read without a window. A handset has no R and no pad, and the tap
/// layer the screen mounts on exactly this condition is what the touch half
/// names.
String crawlAgain({required bool touch}) =>
    touch ? 'Tap to go down again.' : 'Press R to go down again.';

/// The end of the crypt: what the crawl came to, and who made it.
class CryptEnding extends StatelessWidget {
  const CryptEnding({
    super.key,
    required this.kills,
    required this.seconds,
    required this.levels,
    this.touch = false,
  });

  /// Everything this crawl killed, across every level of it.
  final int kills;

  /// Simulated seconds the crawl took. Not wall seconds: a machine that could
  /// not keep up spent longer than this and the crypt did not run for it.
  final double seconds;

  /// Levels of the crypt this crawl stood in — see `Crawl.levels`, and the
  /// note there about a run resumed from disk.
  final int levels;

  /// Whether the player has fingers rather than a keyboard.
  ///
  /// Passed in rather than read from `Playing`, so this widget can be pumped
  /// both ways in a test: `flutter_test` reports itself as Android, and a
  /// widget that asked would only ever be seen one way.
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
                'You are out of the crypt.',
                style: TextStyle(
                  color: Color(0xFFF2E4C8),
                  fontSize: 30,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 20),
              // `Wrap` and not `Row`: three tallies at a large text size is a
              // row that runs off a handset held in landscape, and the numbers
              // are the part of this screen somebody with low vision most wants
              // to read.
              Wrap(
                spacing: 28,
                runSpacing: 12,
                children: <Widget>[
                  _Tally(
                    label: 'time',
                    value: clockText(seconds, none: '0:00'),
                  ),
                  _Tally(label: 'kills', value: '$kills'),
                  _Tally(
                    label: levels == 1 ? 'level' : 'levels',
                    value: '$levels',
                  ),
                ],
              ),
              const SizedBox(height: 26),
              const CreditsSection(
                credits: Credits.models,
                heading: 'Art in this game',
              ),
              const SizedBox(height: 22),
              Text(
                crawlAgain(touch: touch),
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
            fontSize: 30,
            fontWeight: FontWeight.w600,
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
