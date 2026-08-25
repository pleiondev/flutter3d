import 'package:flutter/material.dart';

/// The three black screens the game can be on instead of the game: the
/// renderer failing to start, a level failing to load, and the moment between
/// the two while one is still loading.
///
/// **Kept apart from `main.dart` on purpose.** None of the three reads a
/// simulation or a renderer — each is a message and a colour — and grouping
/// them here is what makes it obvious they are the same shape.

/// Shown before the renderer exists, and if it never does.
class RendererFailure extends StatelessWidget {
  const RendererFailure({super.key, required this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Text(
              'The renderer did not start.\n\n$error\n\n'
              'The shader bundle is built by '
              'packages/flutter3d/tool/build_shaders.sh, and has to be rebuilt '
              'after every Flutter SDK change.',
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ),
      );
}

/// Shown when [asset] threw rather than loaded.
///
/// **This used to be a black screen for ever**: the load caught its own throw
/// and printed it, which is a line in a console nobody playing the game can
/// see. Every one of these is a content mistake — the failure a person
/// editing a level makes.
class LevelLoadFailed extends StatelessWidget {
  const LevelLoadFailed({super.key, required this.asset, required this.error});

  final String asset;
  final Object error;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Text(
              'That level would not load.\n\n$asset\n\n$error',
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ),
      );
}

/// Shown between a renderer that has started and a level that has not yet.
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'Loading…',
            style: TextStyle(color: Colors.white54),
          ),
        ),
      );
}
