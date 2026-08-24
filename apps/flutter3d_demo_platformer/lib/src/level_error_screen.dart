import 'package:flutter/material.dart';

/// What a level that would not load looks like.
///
/// **It used to look like nothing at all.** There was no `catch` around the
/// load, so a malformed document, a missing texture or a save naming a level
/// that has since been renamed left a black screen with no message and no way
/// out — and every one of those is a mistake made while *editing content*,
/// which is the most likely mistake this game has.
///
/// The way out matters as much as the message: the failing level is usually the
/// saved one, so the only thing that can rescue a player is throwing the save
/// away, and they cannot do that from a black screen.
class LevelErrorScreen extends StatelessWidget {
  const LevelErrorScreen({
    super.key,
    required this.asset,
    required this.error,
    required this.onStartOver,
  });

  final String asset;
  final Object error;

  /// Clears the run and goes back to the first level.
  final VoidCallback onStartOver;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'That level would not load.',
                  style: TextStyle(color: Colors.white, fontSize: 22),
                ),
                const SizedBox(height: 14),
                Text(
                  asset,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '$error',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 22),
                TextButton(
                  onPressed: onStartOver,
                  child: const Text('Throw the run away and start again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
