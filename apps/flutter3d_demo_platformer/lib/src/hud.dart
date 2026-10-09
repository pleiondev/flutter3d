import 'package:flutter/material.dart';
import 'package:flutter3d_game/flutter3d_game.dart'; // SettingsOverlay
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter3d_game_ui/hud.dart' show HudBanner, HudTally;
import 'package:flutter3d_game_ui/screens.dart' show EndingSheet, EndingTally;

import 'credits.dart';

/// Coins, deaths, and what the game is waiting for.
///
/// Flutter widgets over the top of the rendered frame rather than geometry in
/// the scene, which is the one thing this stack gets for free that a C++ engine
/// spends a year on.
class Hud extends StatelessWidget {
  const Hud({
    super.key,
    required this.coins,
    required this.deaths,
    required this.lives,
    required this.elapsed,
    required this.state,
    required this.captured,
    required this.levelName,
    this.keys = const <String>{},
    this.message,
    this.behind = false,
    this.lost = 0.0,
    this.finale = false,
    this.touch = false,
  });

  final int coins;
  final int deaths;

  /// Deaths left, or negative where a run cannot be lost.
  final int lives;

  /// How long this run has been played, in seconds of simulated time.
  final double elapsed;

  final RunState state;
  final bool captured;
  final String levelName;

  /// Which keys the runner is carrying. A door asks "have you got one", so the
  /// player has to be able to answer the same question without guessing.
  final Set<String> keys;

  /// The last thing the level said, or null.
  ///
  /// **The level has always said things and nobody was listening.** A locked
  /// gate answers "You need the blue key" into a list the platformer never
  /// drained, so a player who walked into one was told nothing and had no way
  /// to learn a key existed.
  final String? message;

  /// Whether the machine has just been failing to run the game at full speed.
  ///
  /// **The game used to slow down and say nothing**, which reads as the game
  /// being like that rather than as this machine being unable to run it. See
  /// `Pace`: nothing is dropped until a frame takes longer than 83 ms, so this
  /// is never a close call.
  final bool behind;

  /// Simulated seconds this run never ran, so the clock can admit it.
  final double lost;

  /// Whether the level just finished was the last one.
  ///
  /// **A game that ends is different from a level that ends.** Finishing
  /// Ascent used to put up the same panel as finishing the tutorial, whose
  /// whole message was "Press escape to let the mouse go" — so the reward for
  /// four hundred metres of climbing was a note about the mouse pointer, and
  /// nothing ever said the game was over or who made it.
  final bool finale;

  /// Whether the player has fingers rather than a keyboard.
  ///
  /// **Only the sentence at the end of a run turns on it**, and it has to:
  /// this screen told every player to press R, and a handset has no R and no
  /// pad. The answer is passed in rather than read from `Playing`, so this
  /// widget can be pumped both ways in a test — `flutter_test` reports itself
  /// as Android, and a widget that asked would only ever be seen one way.
  final bool touch;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: <Widget>[
          Positioned(
            left: 24,
            top: 20,
            // Bounded and wrapping, because a `Row` of fixed sizes is a row that
            // runs off the screen the moment a player turns their text up — and
            // the tallies are the one part of this screen somebody with low
            // vision most needs to read. `Wrap` puts the overflow on a second
            // line instead of into the debug console.
            right: 24,
            child: Wrap(
              spacing: 24,
              runSpacing: 8,
              children: <Widget>[
                HudTally(label: 'coins', value: '$coins'),
                HudTally(label: 'falls', value: '$deaths'),
                if (lives >= 0) HudTally(label: 'lives', value: '$lives'),
                HudTally(label: 'time', value: clock(elapsed)),
                if (keys.isNotEmpty)
                  HudTally(
                    label: keys.length == 1 ? 'key' : 'keys',
                    // Named rather than counted: a door wants a colour, so a
                    // number here would be the wrong answer to the question the
                    // player is about to be asked.
                    value: (keys.toList()..sort()).join(' '),
                  ),
              ],
            ),
          ),

          if (behind && state == RunState.running)
            Positioned(
              right: 24,
              top: 24,
              child: Text(
                'This machine is behind — the game is running slowly.',
                style: TextStyle(
                  color: Colors.amber.withValues(alpha: 0.9),
                  fontSize: 13,
                  shadows: const <Shadow>[
                    Shadow(blurRadius: 8, color: Colors.black87),
                  ],
                ),
              ),
            ),

          if (message != null && state == RunState.running)
            Positioned(
              left: 0,
              right: 0,
              bottom: 96,
              child: Center(child: HudBanner(message!)),
            ),
          if (state == RunState.finished && finale)
            Ending(
              coins: coins,
              deaths: deaths,
              elapsed: elapsed,
              lost: lost,
              touch: touch,
            )
          else if (state == RunState.finished)
            Center(
              child: _Results(
                title: levelName,
                coins: coins,
                deaths: deaths,
                elapsed: elapsed,
                subtitle: 'Press escape to let the mouse go.',
                lost: lost,
              ),
            )
          else if (state == RunState.lost)
            Center(
              child: _Results(
                title: 'Out of lives',
                coins: coins,
                deaths: deaths,
                elapsed: elapsed,
                subtitle: touch
                    ? 'Tap to start again.'
                    : 'Press R to start again.',
                lost: lost,
              ),
            )
          else if (!captured)
            const Center(child: HudBanner('Click to play')),
        ],
      ),
    );
  }
}

/// The end of the game: what the run came to, and who made it.
///
/// **The credits are here because the licence puts them here.** Two of the
/// models are CC BY 4.0, and a credits screen is where a game discharges that
/// — see `credits`, which is also read by the settings panel, so a player who
/// never finishes still sees it.
///
/// Laid out by `EndingSheet`, which the crypt and the season end on too; what
/// is here is this game's sentence and its three numbers.
class Ending extends StatelessWidget {
  const Ending({
    super.key,
    required this.coins,
    required this.deaths,
    required this.elapsed,
    this.lost = 0.0,
    this.touch = false,
  });

  final int coins;
  final int deaths;
  final double elapsed;
  final double lost;

  /// Whether the player has fingers rather than a keyboard. See [Hud.touch].
  final bool touch;

  @override
  Widget build(BuildContext context) => EndingSheet(
    title: 'You reached the summit.',
    backdrop: 0.82,
    tallies: <EndingTally>[
      EndingTally('time', clock(elapsed)),
      EndingTally('coins', '$coins'),
      EndingTally('falls', '$deaths'),
    ],
    valueStyle: const TextStyle(
      color: Colors.white,
      fontSize: 30,
      fontWeight: FontWeight.w600,
      shadows: <Shadow>[Shadow(blurRadius: 8, color: Colors.black87)],
    ),
    aside: lost >= 1.0
        ? 'This machine lost ${lost.round()}s the game never ran.'
        : null,
    credits: credits.models,
    again: touch ? 'Tap to climb it again.' : 'Press R to climb it again.',
  );
}

/// Minutes and seconds, which is how a run is read rather than how it is
/// counted.
///
/// A free function so the results screen and the tally show the same thing: two
/// formatters is two formats, and the second one is always the one on the
/// screenshot. Now three screens and `flutter3d_game`'s, for the same reason one
/// step further out — the racing game had the other half of it.
String clock(double seconds) => clockText(seconds, none: '0:00');

/// What a run came to. Shown when it ends, either way.
class _Results extends StatelessWidget {
  const _Results({
    required this.title,
    required this.coins,
    required this.deaths,
    required this.elapsed,
    required this.subtitle,
    this.lost = 0.0,
  });

  final String title;
  final int coins;
  final int deaths;
  final double elapsed;
  final String subtitle;

  /// Simulated seconds the machine could not run.
  ///
  /// **The time above counts simulated seconds**, so a run that dropped four of
  /// them took four seconds longer than it says. Printed rather than folded in:
  /// adding the loss to the clock would make the game look slower than it ran,
  /// and hiding it makes the clock a small lie.
  final double lost;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w300,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                HudTally(label: 'time', value: clock(elapsed)),
                const SizedBox(width: 28),
                HudTally(label: 'coins', value: '$coins'),
                const SizedBox(width: 28),
                HudTally(label: 'falls', value: '$deaths'),
              ],
            ),
            if (lost >= 1.0) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                'This machine lost ${lost.round()}s the game never ran.',
                style: TextStyle(
                  color: Colors.amber.withValues(alpha: 0.85),
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
