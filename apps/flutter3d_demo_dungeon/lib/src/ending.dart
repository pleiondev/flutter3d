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
/// The shape is `EndingSheet`'s, from `flutter3d_game_ui/screens.dart`, which every
/// game here ends on: a full-screen sheet rather than a panel over the level;
/// the tallies the genre is actually played for; the credits, because the
/// licence puts them where the work is; and one line saying how to play
/// again, in words this build can honour. What is here is the crypt's: its
/// sentence, its four numbers and the way deeper.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_game/flutter3d_game.dart' show clockText;
import 'package:flutter3d_game_ui/screens.dart';

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
    required this.bestStreak,
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

  /// The longest run of kills this crawl made without being hurt in between.
  /// See `Crawl.streak` for what breaks one.
  final int bestStreak;

  /// Whether the player has fingers rather than a keyboard.
  ///
  /// Passed in rather than read from `Playing`, so this widget can be pumped
  /// both ways in a test: `flutter_test` reports itself as Android, and a
  /// widget that asked would only ever be seen one way.
  final bool touch;

  @override
  Widget build(BuildContext context) => EndingSheet(
    title: 'You are out of the crypt.',
    titleColor: const Color(0xFFF2E4C8),
    tallies: <EndingTally>[
      EndingTally('time', clockText(seconds, none: '0:00')),
      EndingTally('kills', '$kills'),
      EndingTally(levels == 1 ? 'level' : 'levels', '$levels'),
      EndingTally('best streak', '$bestStreak'),
    ],
    credits: credits.models,
    again: crawlAgain(touch: touch),
    trailing: <Widget>[
      if (!touch) ...<Widget>[
        const SizedBox(height: 8),
        Text(
          'Or N, to go deeper, where nobody built the rooms.',
          key: const ValueKey<String>('ending:deeper'),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 13,
          ),
        ),
      ],
    ],
  );
}
