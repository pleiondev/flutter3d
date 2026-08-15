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
    required this.lives,
    required this.elapsed,
    required this.state,
    required this.captured,
    required this.levelName,
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
                if (lives >= 0) ...<Widget>[
                  const SizedBox(width: 24),
                  _Tally(label: 'lives', value: '$lives'),
                ],
                const SizedBox(width: 24),
                _Tally(label: 'time', value: clock(elapsed)),
              ],
            ),
          ),
          if (state == RunState.finished)
            Center(
              child: _Results(
                title: levelName,
                coins: coins,
                deaths: deaths,
                elapsed: elapsed,
                subtitle: 'Press escape to let the mouse go.',
              ),
            )
          else if (state == RunState.lost)
            Center(
              child: _Results(
                title: 'Out of lives',
                coins: coins,
                deaths: deaths,
                elapsed: elapsed,
                subtitle: 'Press R to start again.',
              ),
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

/// Minutes and seconds, which is how a run is read rather than how it is
/// counted.
///
/// A free function so the results screen and the tally show the same thing: two
/// formatters is two formats, and the second one is always the one on the
/// screenshot.
String clock(double seconds) {
  final whole = seconds.floor();
  final minutes = whole ~/ 60;
  final rest = whole % 60;
  return '$minutes:${rest.toString().padLeft(2, '0')}';
}

/// What a run came to. Shown when it ends, either way.
class _Results extends StatelessWidget {
  const _Results({
    required this.title,
    required this.coins,
    required this.deaths,
    required this.elapsed,
    required this.subtitle,
  });

  final String title;
  final int coins;
  final int deaths;
  final double elapsed;
  final String subtitle;

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
                _Tally(label: 'time', value: clock(elapsed)),
                const SizedBox(width: 28),
                _Tally(label: 'coins', value: '$coins'),
                const SizedBox(width: 28),
                _Tally(label: 'falls', value: '$deaths'),
              ],
            ),
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
