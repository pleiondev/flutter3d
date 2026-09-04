/// What the game says before the lights.
///
/// **There was nothing here, and the licence made that a problem rather than
/// an omission.** The car is CC BY 4.0, whose text asks that attribution
/// travel wherever the work does; the only place this game named Dave Love was
/// inside the settings panel, behind a gear, past the volume sliders — which is
/// a screen most players never open and none is asked to. The other two games
/// each put their credits on a title card, met once by everybody, and this one
/// was the game that actually needed to.
///
/// So the attribution moves here. The settings keep their copy: two places is
/// not a duplication problem, it is the licence being honoured twice.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_app/flutter3d_app.dart'; // CreditsSection, Credit

import 'credits.dart';

/// The card the season opens on.
///
/// ## The race waits for it, and that is a decision
///
/// A title card can be a picture the game runs behind, or a gate the game
/// waits at. This one waits, for three reasons, in the order they mattered:
///
/// 1. **The lights.** The circuit starts its countdown the moment it is read —
///    `RacePhase.countdown` is where a fresh `RaceState` begins — so a card
///    drawn over a running race is a card the player dismisses to find they
///    have already missed the start. Either the card waits or the countdown
///    does, and the countdown is a piece of the simulation.
/// 2. **The attribution.** A card that takes itself down after a few seconds is
///    attribution nobody read. A card that goes when the player says so has at
///    least been in front of them until they decided to leave.
/// 3. **The browser.** A page may not make a sound until the player has done
///    something. This game opened its mixer at launch and spent that permission
///    before the player had given it, so the first sound of the race was the one
///    that got refused; the platformer opens on the first gesture for exactly
///    this reason, and this card is that gesture.
///
/// Shown once a session and never again: a card that comes back every time the
/// keyboard is let go is a card in the middle of a race.
class TitleCard extends StatelessWidget {
  const TitleCard({super.key, required this.prompt, this.touch = false});

  /// What the player has to do to begin. Different on a handset, which has no
  /// key to press.
  final String prompt;

  /// Whether this build is driven with fingers, in which case none of the keys
  /// below exist and listing them would be a screen of nonsense.
  final bool touch;

  /// What the game is actually driven by, said once.
  ///
  /// Built from what the build is rather than written as a `const` list: the
  /// platformer's card said "click to dash" in a browser for months because a
  /// list of keys beside the keys, checked by nothing, drifts the first time
  /// either changes. This one is smaller and the rule is the same.
  List<String> get _controls => touch
      ? const <String>[
          'The band on the left steers. Hold it into the corner.',
          'The pedals on the right are the brake and the throttle.',
          'Pit stops are the button in the top corner — stopped, not moving.',
          'A controller works too, if one is paired.',
        ]
      : const <String>[
          'W and S, or the arrows, are the throttle and the brake.',
          'A and D steer. Space is the handbrake.',
          'T changes the tyres, once the car has stopped.',
          // Positions rather than printed labels: this game cannot know
          // whether the pad in the player's hands calls its lower face button
          // `A` or Cross, and deliberately does not try to find out.
          // One sentence over two lines, not two entries missing a comma.
          // ignore: no_adjacent_strings_in_list
          'Or a controller: the triggers drive, the d-pad steers, the lower '
              'face button is the handbrake.',
          'Escape opens the settings, and stops the race while they are open.',
        ];

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black.withValues(alpha: 0.78),
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
                'Ring',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 46,
                  fontWeight: FontWeight.w200,
                  letterSpacing: 6,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Five circuits, one car, and a lap time that outlives the '
                'evening.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 22),
              for (final line in _controls)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    line,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              const SizedBox(height: 26),
              // The licence's own condition, on the screen every player meets.
              const CreditsSection(credits: Credits.models),
              const SizedBox(height: 26),
              Text(
                prompt,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
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
