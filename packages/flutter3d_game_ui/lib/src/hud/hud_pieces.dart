import 'package:flutter/material.dart';

import '../l10n/game_localizations.dart';
import '../theme/game_ui_theme.dart';

/// A dark, rounded panel that stacks a few [HudLine]s.
///
/// Draws nothing at all when it has nothing to stack, so a layout can list
/// its lines conditionally without a panel-shaped smudge left behind. Its
/// background is [GameUiTheme.panel].
class HudPanel extends StatelessWidget {
  const HudPanel({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: GameUiTheme.of(context).panel,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

/// One labelled value in a [HudPanel]: a short label in a fixed column, and
/// the value beside it in tabular figures.
///
/// **The colours and the column are the theme's** — [GameUiTheme.hudLabel],
/// [GameUiTheme.accent], [GameUiTheme.hudLabelWidth] — rather than constants
/// here, so a game with a palette of its own sets them once.
///
/// The label column is wide enough for a seven-letter label at thirteen
/// points, bold, with a point and a half of tracking. It was 52 once, and
/// `RECORD` wrapped: the panel showed `RECOR` above a lonely `D`. A fixed
/// width rather than an intrinsic one because the lines are built
/// independently and a column of labels that each measured itself would not
/// line up, which is the thing this column is for.
class HudLine extends StatelessWidget {
  const HudLine({
    super.key,
    required this.label,
    required this.value,
    this.accent = false,
    this.accentColor,
  });

  final String label;
  final String value;

  /// Whether this line has just become true. Colour, because a player
  /// reading it is doing something else at the time.
  final bool accent;

  /// The colour an [accent] line is drawn in; null for [GameUiTheme.accent],
  /// a warm yellow that already means "you have done it" on a chequered
  /// flag.
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = GameUiTheme.of(context);
    final lit = accentColor ?? theme.accent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: theme.hudLabelWidth,
            child: Text(
              label,
              // One line, always: a label that outgrew the box would wrap
              // rather than say so.
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                color: accent ? lit : theme.hudLabel,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: accent ? lit : theme.text,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              // Tabular figures, or the whole line jitters as the
              // thousandths tick over.
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// How a [HudTally] is drawn: the colour, and the size of its two lines.
final class HudTallyStyle {
  const HudTallyStyle({
    this.color = Colors.white,
    this.valueSize = 30,
    this.labelSize = 12,
    this.tabular = false,
  });

  final Color color;

  /// The value's font size, in logical pixels.
  final double valueSize;

  /// The label's font size, in logical pixels.
  final double labelSize;

  /// Whether the value is set in tabular figures, for a number that changes
  /// while it is being read.
  final bool tabular;
}

/// A big number with a small label under it — `12` over `COINS` — read by a
/// screen reader as one thing, `"coins 12"`, rather than as two unrelated
/// numbers in a row of numbers.
class HudTally extends StatelessWidget {
  const HudTally({
    super.key,
    required this.label,
    required this.value,
    this.style = const HudTallyStyle(),
  });

  final String label;
  final String value;
  final HudTallyStyle style;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label $value',
    excludeSemantics: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          value,
          style: TextStyle(
            color: style.color,
            fontSize: style.valueSize,
            fontWeight: FontWeight.w600,
            fontFeatures: style.tabular
                ? const <FontFeature>[FontFeature.tabularFigures()]
                : null,
            shadows: const <Shadow>[
              Shadow(blurRadius: 8, color: Colors.black87),
            ],
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: style.color.withValues(alpha: 0.7),
            fontSize: style.labelSize,
            letterSpacing: 2,
          ),
        ),
      ],
    ),
  );
}

/// A sentence across the middle of the screen, on a dark rounded box: what
/// the game is waiting for, or what just happened.
class HudBanner extends StatelessWidget {
  const HudBanner(
    this.text, {
    super.key,
    this.color = Colors.white,
    this.fontSize = 18,
  });

  final String text;
  final Color color;

  /// The text's font size, in logical pixels.
  final double fontSize;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: fontSize),
      ),
    ),
  );
}

/// A speed in kilometres an hour, large, from metres a second.
///
/// Kilometres an hour, because that is the number on a dashboard; the
/// simulation works in metres a second and is right to.
class Speedometer extends StatelessWidget {
  const Speedometer({super.key, required this.metersPerSecond});

  /// The speed shown, in metres per second.
  final double metersPerSecond;

  /// What the dial says for [metersPerSecond]: whole kilometres an hour.
  static int kphOf(double metersPerSecond) => (metersPerSecond * 3.6).round();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
    decoration: BoxDecoration(
      color: GameUiTheme.of(context).panel,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          '${kphOf(metersPerSecond)}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 48,
            fontWeight: FontWeight.w800,
            fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          Flutter3dGameLocalizations.of(context).kilometersPerHour,
          style: TextStyle(
            color: GameUiTheme.of(context).hudLabel,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}
