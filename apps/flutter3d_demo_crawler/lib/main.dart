/// Up to four heroes, one screen, and a maze that keeps making monsters.
///
///     flutter run -d macos
///     flutter run -d macos --dart-define=CRAWLER_PARTY=warrior,elf
///
/// Press fire to join — Space on WASD, / on the arrows, A on a controller —
/// move sideways to choose a class, and press a potion button (Q, the full
/// stop, B) to go in. Everybody shares one view, which rises as the party
/// spreads and stops anybody walking off its edge. Health drains by the
/// second; food brings it back. A key opens any one locked door. Walking into
/// a monster is fighting it; a potion clears everything on screen.
///
/// The game is `CrawlerGame`, a Flame game over the 3D layer; this file shows
/// it and draws the screens over it.
library;

// Flutter's `Hero` is a page transition; this game's is somebody holding a
// controller.
import 'package:flame/game.dart' show FlameGame;
import 'package:flame_flutter3d/flame_flutter3d.dart';
import 'package:flutter/material.dart' hide Hero, Material;

import 'src/crawler_game.dart';
import 'src/screens.dart';

/// A party to go straight in with, skipping the select screen:
/// `--dart-define=CRAWLER_PARTY=warrior,elf`, the first on WASD and the
/// second on the arrows. For a demo, and for looking at a level at once.
const String _party = String.fromEnvironment('CRAWLER_PARTY');

void main() => runApp(const CrawlerApp());

class CrawlerApp extends StatelessWidget {
  const CrawlerApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    title: 'Crawler',
    debugShowCheckedModeBanner: false,
    home: _CrawlScreen(),
  );
}

class _CrawlScreen extends StatefulWidget {
  const _CrawlScreen();

  @override
  State<_CrawlScreen> createState() => _CrawlScreenState();
}

class _CrawlScreenState extends State<_CrawlScreen> {
  final CrawlerGame _game = CrawlerGame(
    party: _party.isEmpty ? const <String>[] : _party.split(','),
  );

  @override
  void dispose() {
    // The world lives with the game, not the widget: it goes here.
    _game.close3d();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF0C0B10),
    body: Flutter3dFlameWidget(
      game: _game,
      overlayBuilderMap: <String, Widget Function(BuildContext, FlameGame)>{
        'screen': (BuildContext context, FlameGame game) =>
            CrawlScreens(game: game as CrawlerGame),
      },
      initialActiveOverlays: const <String>['screen'],
    ),
  );
}
