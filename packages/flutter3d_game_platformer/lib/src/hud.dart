/// The readouts this genre has, as widgets a game lays out itself.
///
/// **Not a HUD.** A platformer's own heads-up display is a title card, a
/// results screen and a message line, all of which belong to the game that
/// wrote them. What belongs to the genre is the handful of numbers below: what
/// has been picked up, how many lives are left, and how long the run has taken.
///
/// The genre ships the readouts and the game ships the layout, which is the
/// same split the shooter's `hud.dart` makes and for the same reason: each
/// widget takes the genre's own type rather than the numbers pulled out of it,
/// because pulling them out is where the mistakes were.
library;

import 'package:flutter/widgets.dart';
import 'purse.dart';

/// How a game wants its readouts drawn.
final class ReadoutStyle {
  const ReadoutStyle({
    this.text = const TextStyle(color: Color(0xFFFFFFFF), fontSize: 18.0),
    this.dim = const Color(0x66FFFFFF),
    this.pipSize = 10.0,
  });

  final TextStyle text;

  /// A life already spent, and anything the player is not being asked to look
  /// at.
  final Color dim;

  final double pipSize;
}

/// What the runner is carrying, one line per kind.
///
/// **Takes the [Purse] rather than a count**, because a platformer collects
/// more than one thing and a readout built around "coins" has to be rewritten
/// the first time a level has gems in it. What is in the purse is what is
/// drawn, in the order [order] gives or the order it was collected in.
final class PurseReadout extends StatelessWidget {
  const PurseReadout({
    super.key,
    required this.purse,
    this.order = const <String>[],
    this.style = const ReadoutStyle(),
  });

  final Purse purse;

  /// The kinds to draw, in the order to draw them. Empty draws everything the
  /// purse holds, which is what a game with one kind wants and what a game
  /// with five usually does not.
  final List<String> order;

  final ReadoutStyle style;

  @override
  Widget build(BuildContext context) {
    final kinds = order.isEmpty ? purse.counts.keys.toList() : order;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final String kind in kinds)
          Text('$kind ${purse[kind]}', style: style.text),
      ],
    );
  }
}

/// Lives left, as a pip each.
///
/// **A run with no limit draws nothing**, rather than an infinity or a very
/// large number. `PlatformerSimulation.lives` is negative when nothing is
/// counting, and a strip of pips that appears only when lives matter is how a
/// player learns that they do.
final class LivesStrip extends StatelessWidget {
  const LivesStrip({
    super.key,
    required this.lives,
    this.of,
    this.style = const ReadoutStyle(),
  });

  /// How many are left. Negative means unlimited; see the class doc.
  final int lives;

  /// How many the run started with, so the spent ones can be drawn dim. Null
  /// draws only what is left.
  final int? of;

  final ReadoutStyle style;

  @override
  Widget build(BuildContext context) {
    if (lives < 0) return const SizedBox.shrink();
    final total = of ?? lives;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var i = 0; i < total; i++)
          Padding(
            padding: EdgeInsets.only(right: style.pipSize * 0.4),
            child: SizedBox(
              width: style.pipSize,
              height: style.pipSize,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: i < lives ? style.text.color! : style.dim,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
