/// What is drawn over the 3D layer: the select screen, and the HUD in play.
///
/// One Flame overlay that reads the game, redrawn whenever the game says it
/// has something new.
library;

// Flutter's `Hero` is a page transition; this game's is somebody holding a
// controller.
import 'package:flame_flutter3d/flame_flutter3d.dart' show FlameInputBridge;
import 'package:flutter/material.dart' hide Hero;
import 'package:flutter3d_game_crawler/flutter3d_game_crawler.dart';

import 'crawl_visuals.dart';
import 'crawler_game.dart';
import 'hud.dart';

class CrawlScreens extends StatelessWidget {
  const CrawlScreens({super.key, required this.game});

  final CrawlerGame game;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: game.changed,
    builder: (BuildContext context, int _, Widget? _) => switch (game.phase) {
      CrawlPhase.choosing => _Choosing(game: game),
      CrawlPhase.loading => const Center(
        child: Text('…', style: TextStyle(color: Color(0xFFE8E2D6))),
      ),
      CrawlPhase.connecting => Center(
        child: Text(
          game.message ?? 'Room ${game.room}: waiting for the other player…',
          style: const TextStyle(color: Color(0xFFE8E2D6), fontSize: 20),
        ),
      ),
      _ => CrawlHud(
        heroes: game.staged?.sim.heroes ?? const <Hero>[],
        lines: <String>[
          ...game.announcer.lines,
          if (game.phase != CrawlPhase.playing) ?game.message,
        ],
        title: game.levelTime < 2.5 ? game.title : null,
      ),
    },
  );
}

/// Who has joined, as what, and how the rest can.
class _Choosing extends StatelessWidget {
  const _Choosing({required this.game});

  final CrawlerGame game;

  @override
  Widget build(BuildContext context) {
    final seated = game.seats.seated;
    final free = game.devices
        .where((Device d) => !seated.contains(d.input))
        .toList();
    return ColoredBox(
      color: const Color(0xFF0C0B10),
      child: DefaultTextStyle(
        style: const TextStyle(color: Color(0xFFE8E2D6), fontSize: 18.0),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                'CRAWLER',
                style: TextStyle(fontSize: 56.0, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 24.0),
              for (var i = 0; i < 4; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6.0),
                  child: i < seated.length
                      ? _seat(i, seated[i])
                      : Text(
                          'Player ${i + 1}: free — press fire on '
                          '${free.isEmpty ? 'a controller' : free.first.name}',
                          style: const TextStyle(color: Color(0xFF807A70)),
                        ),
                ),
              const SizedBox(height: 24.0),
              const Text(
                'Two can share the keyboard: WASD, Space to fire, Q for a potion;\n'
                'and the arrows, / to fire, . for a potion.\n'
                'Players three and four need a controller: stick to move, A to '
                'fire, B for a potion.\n\n'
                'Joined: left or right changes class.\n'
                'When everybody is in, press a potion button to start.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFFB8B0A2), fontSize: 15.0),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _seat(int i, FlameInputBridge input) {
    final kind = game.classes[input]!;
    final c = colourOf(kind);
    final device = game.devices.firstWhere((Device d) => d.input == input);
    return Text(
      'Player ${i + 1}: ${kind.name} (${device.name.split(',').first})',
      style: TextStyle(
        color: Color.fromARGB(
          255,
          (c.x * 255).round(),
          (c.y * 255).round(),
          (c.z * 255).round(),
        ),
        fontSize: 24.0,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}
