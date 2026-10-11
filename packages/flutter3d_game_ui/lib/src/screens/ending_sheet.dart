import 'package:flutter/material.dart';

import '../l10n/game_localizations.dart';
import '../theme/game_ui_theme.dart';
import 'credits.dart';

/// One number on a scoreboard and what it counts.
final class EndingTally {
  const EndingTally(this.label, this.value);

  /// What is counted, in lower case: `time`, `falls`, `best streak`.
  final String label;

  /// The number as the player reads it, already formatted.
  final String value;
}

/// How a game ends: one sentence, the tallies it is played for, who made the
/// art, and how to play again.
///
/// **Full-screen rather than a panel over the level**, because the level is
/// behind it and this is the moment to stop looking at it. Three games here
/// had each laid this out by hand, the same way, because the decision had
/// been argued out once: the tallies, the credits because a licence puts them
/// where the work is, and one line saying how to begin again in words the
/// build can honour.
class EndingSheet extends StatelessWidget {
  const EndingSheet({
    super.key,
    required this.title,
    required this.tallies,
    required this.credits,
    required this.again,
    this.creditsHeading,
    this.creditsFootnote,
    this.titleColor,
    this.backdrop = 0.86,
    this.valueStyle = defaultValueStyle,
    this.aside,
    this.trailing = const <Widget>[],
  });

  /// The one sentence: `You reached the summit.`
  final String title;

  /// The scoreboard, in reading order.
  final List<EndingTally> tallies;

  /// Who made the art, and the heading the list goes under.
  final List<Credit> credits;

  /// Null for [Flutter3dGameLocalizations.artInThisGame], in the player's
  /// language.
  final String? creditsHeading;

  /// What the game made itself, under the credits — see
  /// [CreditsSection.footnote]. Null for no such line.
  final String? creditsFootnote;

  /// How to play again, in the words of the device in hand. A game decides it
  /// in one function and the control that honours it beside it, so the two
  /// cannot drift apart.
  final String again;

  /// The sentence's colour; null for [GameUiTheme.text].
  final Color? titleColor;

  /// How opaque [GameUiTheme.sheet] is over the level, nought to one.
  final double backdrop;

  /// How each tally's number is drawn, over [GameUiTheme.text]; its label
  /// is always the small line under it.
  final TextStyle valueStyle;

  /// One line in amber under the tallies, or null: something the numbers do
  /// not say, such as time the machine lost and the game never ran.
  final String? aside;

  /// Anything after the line about playing again.
  final List<Widget> trailing;

  /// A number thirty points high and bold, in [GameUiTheme.text].
  static const TextStyle defaultValueStyle = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w600,
  );

  @override
  Widget build(BuildContext context) {
    final theme = GameUiTheme.of(context);
    return ColoredBox(
      color: theme.sheet.withValues(alpha: backdrop),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    color: titleColor ?? theme.text,
                    fontSize: 30,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 20),
                // `Wrap` and not `Row`: four tallies at a large text size is a
                // row that runs off a handset held in landscape, and the numbers
                // are the part of this screen somebody with low vision most
                // wants to read.
                Wrap(
                  spacing: 28,
                  runSpacing: 12,
                  children: <Widget>[
                    for (final tally in tallies)
                      TallyView(tally: tally, valueStyle: valueStyle),
                  ],
                ),
                if (aside case final said?) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    said,
                    style: TextStyle(color: theme.notice, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 26),
                CreditsSection(
                  credits: credits,
                  heading:
                      creditsHeading ??
                      Flutter3dGameLocalizations.of(context).artInThisGame,
                  footnote: creditsFootnote,
                ),
                const SizedBox(height: 22),
                Text(
                  again,
                  style: TextStyle(
                    color: theme.label,
                    fontSize: 14,
                    letterSpacing: 1,
                  ),
                ),
                ...trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One [EndingTally] drawn: the number, and under it what it counts.
///
/// **Read as one thing**, `falls 3`, rather than as two unrelated words in a
/// row of numbers, for the screen reader that is already on.
class TallyView extends StatelessWidget {
  const TallyView({
    super.key,
    required this.tally,
    this.valueStyle = EndingSheet.defaultValueStyle,
  });

  final EndingTally tally;
  final TextStyle valueStyle;

  @override
  Widget build(BuildContext context) {
    final theme = GameUiTheme.of(context);
    return Semantics(
      label: '${tally.label} ${tally.value}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            tally.value,
            style: TextStyle(color: theme.text).merge(valueStyle),
          ),
          Text(
            tally.label,
            style: TextStyle(
              color: theme.label,
              fontSize: 12,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }
}
