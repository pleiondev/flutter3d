/// What the game says before the lights.
///
/// **There was nothing here, and a licence once made that a problem rather
/// than an omission.** The first car was CC BY 4.0, whose text asks that
/// attribution travel wherever the work does, and the only place this game
/// named its author was inside the settings panel, behind a gear — a screen
/// most players never open. So the credits are here, met once by everybody,
/// and the settings keep their copy. The car is CC0 now; whatever comes in
/// under an attribution licence next is named here without anybody having to
/// remember to.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_game_ui/screens.dart' show TitleSheet;

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
  const TitleCard({
    super.key,
    required this.prompt,
    this.touch = false,
    this.onBegin,
  });

  /// What the player has to do to begin. Different on a handset, which has no
  /// key to press.
  final String prompt;

  /// The touch that takes the card down, on a build that has no key to press.
  ///
  /// **Here rather than on the screen's own start layer, which cannot see it.**
  /// That layer is a `Positioned.fill` *below* this card in the same `Stack`,
  /// and a card is a [ColoredBox] — which hit-tests opaque. So every pointer
  /// that lands anywhere on this screen stops here, and a handset, which has no
  /// keyboard and no `Escape` and reads a prompt that says "touch to start",
  /// had nothing that would start the season. The platformer does not have this
  /// fault because its own `_begin` listener wraps the whole stack rather than
  /// sitting inside it: an ancestor is on the hit-test path even when a
  /// descendant absorbs, and a sibling underneath is not.
  ///
  /// A [Listener] and not a [GestureDetector]: this must not enter the arena
  /// against the card's own scroll view, or a card too tall for the screen
  /// would begin the race on the first drag of a read.
  final VoidCallback? onBegin;

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
  Widget build(BuildContext context) => TitleSheet(
    title: 'Ring',
    tagline:
        'Five circuits, one car, and a lap time that outlives the evening.',
    lines: _controls,
    // The licence's own condition, on the screen every player meets. `owed`
    // rather than every model shipped. The roadside is CC0 and asks for
    // nothing, so listing it here would be four lines of courtesy that push
    // the "touch to start" line off a 600-point screen — which is how this was
    // found. What the game ships is still accounted for in `credits.models`,
    // and the test reads that from the assets directory.
    credits: credits.owed,
    prompt: prompt,
    onBegin: onBegin,
  );
}
