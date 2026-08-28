/// The small pieces `RaceHud` is built from, and nothing wider than one of
/// them: a labelled line, the panel that stacks a few of them, and the
/// speedometer that reads a [RaceReadout] instead of a label and a value.
library;

import 'package:flutter/material.dart';

import 'race_readout.dart';

class HudPanel extends StatelessWidget {
  const HudPanel({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
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

class HudLine extends StatelessWidget {
  const HudLine({
    super.key,
    required this.label,
    required this.value,
    this.accent = false,
  });

  final String label;
  final String value;

  /// Whether this line has just become true. Colour, because a driver reading
  /// it is doing something else at the time.
  final bool accent;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          // **Wide enough for the longest label there is**, which is `RECORD!`
          // at thirteen points, bold, with a point and a half of tracking. It
          // was 52, and `RECORD` wrapped: the panel showed `RECOR` above a
          // lonely `D`, pushing the line below it down and leaving the value
          // beside it floating against nothing.
          //
          // A fixed width rather than an intrinsic one because these lines are
          // built independently and a column of labels that each measured
          // itself would not line up — which is the thing this column is for.
          // `hud_label_test.dart` holds the number to the text rather than the
          // other way round, so a longer label fails a test instead of wrapping
          // in a corner of somebody's screen.
          width: 72,
          child: Text(
            label,
            // One line, always. Without this the guard above is a comment: a
            // label that outgrew the box would wrap again rather than say so.
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              color: accent ? _accent : const Color(0xFF9AA4B2),
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: accent ? _accent : Colors.white,
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

  /// The colour the flag is, which is the one thing on this screen that already
  /// meant "you have done it".
  static const Color _accent = Color(0xFFFFD166);
}

class Speedometer extends StatelessWidget {
  const Speedometer({super.key, required this.readout});

  final RaceReadout readout;

  @override
  Widget build(BuildContext context) {
    // Kilometres an hour, because that is the number on a car. The simulation
    // works in metres a second and is right to.
    final kph = (readout.speed * 3.6).round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '$kph',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 48,
              fontWeight: FontWeight.w800,
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'km/h',
            style: TextStyle(
              color: Color(0xFF9AA4B2),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
