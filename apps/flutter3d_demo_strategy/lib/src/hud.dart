/// What a player is told about the match they are playing.
///
/// **This screen was one line of text.** It said what both sides had brought
/// home and, on a hover, what was under the cursor — nothing about the purse
/// being spent, nothing about how far off the finishing line was, and nothing
/// at all about the squad the player had picked out, which is the one fact on
/// this screen that only the screen knows. A player could not tell a click that
/// selected six workers from a click that selected none.
///
/// Widgets over the rendered frame rather than geometry in the scene, which is
/// the thing this stack gets for nothing that an engine written in C++ spends a
/// year on. Everything drawn here comes out of [StrategyReadout]: this file
/// holds no arithmetic and cannot reach a unit.
library;

import 'package:flutter/material.dart';

import 'hud_readout.dart';

/// The tallies, the standing, and what the mouse does.
class StrategyHud extends StatelessWidget {
  /// Draws [readout].
  const StrategyHud({super.key, required this.readout});

  /// The frame's worth of numbers.
  final StrategyReadout readout;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: <Widget>[
          Positioned(
            left: 16,
            top: 16,
            // Bounded on both sides and wrapping. A `Row` inside a `Positioned`
            // with no right edge is given unbounded width, so it never
            // overflows and never complains — it lays the last tallies out past
            // the screen instead, where they are still in the tree and still
            // findable by a test that only asked whether they exist. A player
            // who has turned their text up is the one who most needs to read
            // them, and is exactly who would have lost them.
            right: 16,
            child: Wrap(
              spacing: 22,
              runSpacing: 8,
              children: <Widget>[
                _Tally(label: 'stock', value: amountText(readout.stock)),
                _Tally(
                  label: 'delivered',
                  value: progressText(readout.delivered, readout.goal),
                ),
                _Tally(label: 'selected', value: '${readout.selected}'),
                // Everybody else's total. Your own is the `delivered` row
                // above, against the line; a second one beside it would be the
                // same number twice.
                for (final tally in tallyBySide(readout))
                  if (tally.side != readout.side)
                    _Tally(label: tally.label, value: tally.amount),
                if (readout.under case final String under)
                  _Tally(label: 'under', value: under),
              ],
            ),
          ),

          Positioned(
            left: 16,
            right: 16,
            bottom: 14,
            child: Text(
              controlsHint,
              style: TextStyle(
                color: const Color(0xFFE8ECF4).withValues(alpha: 0.55),
                fontSize: 12,
                letterSpacing: 0.6,
              ),
            ),
          ),

          // Only once there is something to say. A banner reading "in play"
          // across the middle of every frame of every match is a banner a
          // player stops seeing, and this one has to be noticed the once.
          if (readout.standing.isOver)
            Center(
              child: _Banner(
                standingText(readout.standing, side: readout.side),
              ),
            ),
        ],
      ),
    );
  }
}

class _Tally extends StatelessWidget {
  const _Tally({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    // Read as one thing — "selected 6" — rather than as two unrelated numbers
    // in a row of numbers. Not how a blind player would play this game, and
    // that is not who it is for: it is for the reader that is already on.
    return Semantics(
      label: '$label $value',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFFE8ECF4),
              fontSize: 24,
              fontWeight: FontWeight.w600,
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
              shadows: <Shadow>[Shadow(blurRadius: 8, color: Colors.black87)],
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: const Color(0xFFE8ECF4).withValues(alpha: 0.7),
              fontSize: 11,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        child: Text(
          text,
          style: const TextStyle(color: Color(0xFFE8ECF4), fontSize: 22),
        ),
      ),
    );
  }
}
