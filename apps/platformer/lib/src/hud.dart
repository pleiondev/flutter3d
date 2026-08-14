import 'package:flutter/material.dart';
import 'package:flutter3d_platformer/flutter3d_platformer.dart';

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
    required this.state,
    required this.captured,
  });

  final int coins;
  final int deaths;
  final RunState state;
  final bool captured;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: <Widget>[
          Positioned(
            left: 24,
            top: 20,
            child: Row(
              children: <Widget>[
                _Tally(label: 'coins', value: '$coins'),
                const SizedBox(width: 24),
                _Tally(label: 'falls', value: '$deaths'),
              ],
            ),
          ),
          if (state == RunState.finished)
            const Center(
              child: _Banner('The summit. Press escape to let the mouse go.'),
            )
          else if (!captured)
            const Center(child: _Banner('Click to play')),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w600,
            shadows: <Shadow>[Shadow(blurRadius: 8, color: Colors.black87)],
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 12,
            letterSpacing: 2,
          ),
        ),
      ],
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
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
      ),
    );
  }
}
