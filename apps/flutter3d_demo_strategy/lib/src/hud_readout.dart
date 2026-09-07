/// Everything the HUD says, gathered once a frame.
///
/// **Values, not the match.** The same split the racing game's readout makes
/// and for the same reason: a widget handed a `Match` can reach through it to a
/// unit, and the day a HUD is the reason a stockpile changed is a day nobody
/// enjoys. What crosses this seam is a handful of numbers and a string, so the
/// widgets below it cannot do anything but draw.
///
/// The other half of why this file exists is that it can be read without a
/// window. Gathering is a function of a match and two facts about the pointer,
/// so a test can assert what a player is told about a match it played in a
/// millisecond, and the widget tests next door only have to prove that the
/// numbers reach the screen.
library;

import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';

/// What the display shows, gathered once a frame.
final class StrategyReadout {
  /// Holds the frame's worth of numbers.
  const StrategyReadout({
    required this.side,
    required this.stock,
    required this.deliveredBySide,
    required this.goal,
    required this.selected,
    required this.standing,
    this.under,
  });

  /// Whose screen this is. Everything below is said from that side's point of
  /// view, and the number is carried rather than assumed so that a document
  /// with three camps can be watched from any of them.
  final int side;

  /// What this side has in its purse and can spend.
  final double stock;

  /// What each side has brought home in total, this side included.
  ///
  /// **Not the same number as [stock] and deliberately kept apart**: a purse is
  /// what a side has *left* after building, and only the total settles a match.
  /// A HUD that showed one and called it the other would tell a player they
  /// were losing every time they spent.
  final List<double> deliveredBySide;

  /// What a side has to bring home to win, or infinity on a map with no line —
  /// which is playable, and simply ends when the ground runs out.
  final double goal;

  /// How many units the player has picked out.
  final int selected;

  /// How the match stands.
  final Standing standing;

  /// What the cursor is over, in the player's words, or null for empty ground.
  final String? under;

  /// What this side has brought home.
  double get delivered => deliveredBySide[side];
}

/// The readout for [match], seen from [side].
///
/// [selected] and [under] come from the screen rather than the match, because
/// they are the two things on this HUD that no simulation knows: whom a player
/// has picked out, and where they are pointing.
StrategyReadout readoutOf(
  Match match, {
  required int side,
  int selected = 0,
  String? under,
}) => StrategyReadout(
  side: side,
  stock: match.simulation.stock[side].amount,
  deliveredBySide: List<double>.of(match.simulation.delivered),
  goal: match.goal.delivered,
  selected: selected,
  standing: match.standing,
  under: under,
);

/// A quantity of the stuff this game is played for, as a player reads it.
///
/// Rounded, because the simulation counts it in fractions of a sack — a worker
/// fills at eight a second and empties whatever it is holding — and a tally
/// that flickers through three decimals is a tally nobody can compare to the
/// one they saw a moment ago.
String amountText(double amount) => amount.round().toString();

/// What a side has brought home against what it needs, as `137 / 400`.
///
/// The line alone on a map that has none: `double.infinity` printed as a goal
/// would read as a bug, and a map without a finishing line genuinely has no
/// number to put there.
String progressText(double delivered, double goal) => goal.isFinite
    ? '${amountText(delivered)} / ${amountText(goal)}'
    : amountText(delivered);

/// How a match stands, from [side]'s point of view.
///
/// Sides are named by their number rather than called "the bot", because how
/// many there are is read out of the document: a map with three camps has two
/// opponents and neither of them is *the* one.
String standingText(Standing standing, {required int side}) {
  if (!standing.isOver) return 'in play';
  return switch (standing.winner) {
    null => 'drawn',
    final int winner when winner == side => 'you win',
    final int winner => 'side $winner wins',
  };
}

/// What every side has brought home, in side order and named as the viewer
/// would name them.
///
/// A list rather than a sentence, so the widget lays it out and a test reads it.
/// The viewer's own entry is in it — a caller that shows the progress row
/// already has that number and skips its own side by number rather than by
/// label, which is why the side is carried alongside.
List<({int side, String label, String amount})> tallyBySide(
  StrategyReadout readout,
) => <({int side, String label, String amount})>[
  for (var it = 0; it < readout.deliveredBySide.length; it++)
    (
      side: it,
      label: it == readout.side ? 'you' : 'side $it',
      amount: amountText(readout.deliveredBySide[it]),
    ),
];

/// What the mouse does here, written where a player can see it.
///
/// **Said on the screen because two of the three are not what a strategy game
/// usually does.** A drag with the primary button draws a rectangle rather than
/// pushing the view — the view moved on a drag until selection existed, and it
/// had to give the gesture up — so a player who knew this demo yesterday would
/// otherwise find the map nailed down and no way to learn why.
const String controlsHint =
    'drag to select · click the ground to send them · right-drag to move the '
    'view · scroll to zoom';
