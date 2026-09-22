/// The three screens a game is on when it is not the game: still loading, the
/// renderer never started, and the level would not read.
///
/// **Four hand-rolled copies and three inline spinners.** Every application in
/// this repository had written at least one of these, and the package that
/// exports settings, rebinding, credits, saves and a clock exported none of
/// them — although this is every non-game screen a game actually needs. Two of
/// the copies had grown things the others had not: the crypt's renderer
/// failure carries the shader-bundle diagnostic, which is engine knowledge and
/// had no business living in a game; the platformer's level failure carries a
/// way out, which is the half that matters most, because the level that will
/// not load is usually the saved one and a player cannot throw a save away
/// from a black screen.
///
/// So the union of the four is here, and the way out is optional rather than
/// required: a game with no save to throw away should not have to invent a
/// button.
library;

import 'package:flutter/material.dart';

/// Shown between a renderer that has started and a level that has not yet.
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key, this.message = 'Loading…'});

  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: Center(
      child: Text(message, style: const TextStyle(color: Colors.white54)),
    ),
  );
}

/// Shown before the renderer exists, and if it never does.
///
/// The shader-bundle sentence is here rather than in a game because it is the
/// engine's own build step that produces the thing that is missing, and a
/// person meeting this screen is far more likely to have changed the Flutter
/// SDK than to have broken their game.
class RendererFailure extends StatelessWidget {
  const RendererFailure({super.key, required this.error});

  static const String _bundleHint =
      'The shader bundle is built by '
      'packages/flutter3d_impeller/tool/build_shaders.sh, and has to be '
      'rebuilt after every Flutter SDK change.';

  final Object? error;

  @override
  Widget build(BuildContext context) => _Sheet(
    title: 'The renderer did not start.',
    lines: <String>['$error', _bundleHint],
  );
}

/// Shown when [asset] threw rather than loaded.
///
/// **This used to be a black screen for ever** in two of the three games: the
/// load caught its own throw and printed it, which is a line in a console
/// nobody playing can see. Every one of these is a content mistake — the
/// failure a person editing a level makes — so the message names the file.
///
/// [onStartOver] is the way out, and is optional. Where a game has one, the
/// failing level is usually the saved one and throwing the run away is the
/// only thing that rescues the player.
class LevelLoadFailed extends StatelessWidget {
  const LevelLoadFailed({
    super.key,
    required this.asset,
    required this.error,
    this.onStartOver,
    this.startOverLabel = 'Throw the run away and start again',
  });

  final String asset;
  final Object error;
  final VoidCallback? onStartOver;
  final String startOverLabel;

  @override
  Widget build(BuildContext context) => _Sheet(
    title: 'That level would not load.',
    lines: <String>[asset, '$error'],
    action: onStartOver == null
        ? null
        : TextButton(onPressed: onStartOver, child: Text(startOverLabel)),
  );
}

/// The shape all three share: black, centred, readable at a phone's width.
class _Sheet extends StatelessWidget {
  const _Sheet({required this.title, required this.lines, this.action});

  final String title;
  final List<String> lines;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 22),
                ),
                for (final line in lines) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    line,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 14,
                    ),
                  ),
                ],
                if (action != null) ...<Widget>[
                  const SizedBox(height: 22),
                  action!,
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
