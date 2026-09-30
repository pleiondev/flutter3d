/// What each player needs to see: their health running down, what they
/// carry, their score, and the announcer's lines.
///
/// **The announcer is written, not spoken, for now.** The arcade's voice is
/// the genre's signature, and a recorded voice is an asset somebody has to
/// make and license; until there is one, the lines it would say appear in the
/// middle of the screen for as long as a voice would take to say them.
library;

// Flutter's `Hero` is a page transition; this game's is somebody holding a
// controller.
import 'package:flutter/material.dart' hide Hero;
import 'package:flutter3d_game_crawler/flutter3d_game_crawler.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'crawl_visuals.dart';

/// The lines the announcer has to say, and how long each has left.
final class Announcer {
  final List<({String line, double left})> _lines =
      <({String line, double left})>[];

  /// What is on screen now, newest last.
  List<String> get lines => <String>[for (final l in _lines) l.line];

  /// Reads a step's events for anything worth saying.
  void hear(Iterable<GameEvent> events) {
    for (final event in events) {
      final line = switch (event) {
        HeroHungry(:final hero) => '${_name(hero)} needs food!',
        HeroDied(:final hero) => '${_name(hero)} has fallen.',
        ThiefStole(:final hero, :final what) =>
          'A thief took ${_name(hero)}\'s ${what.name}!',
        ThiefEscaped(what: final Stolen what) =>
          'The thief got away with a ${what.name}.',
        GeneratorDestroyed(:final hero) => '${_name(hero)} broke a generator.',
        _ => null,
      };
      if (line == null) continue;
      _lines.add((line: line, left: 3.0));
      if (_lines.length > 4) _lines.removeAt(0);
    }
  }

  /// Lets [seconds] pass.
  void pass(double seconds) {
    for (var i = _lines.length - 1; i >= 0; i--) {
      final left = _lines[i].left - seconds;
      if (left <= 0.0) {
        _lines.removeAt(i);
      } else {
        _lines[i] = (line: _lines[i].line, left: left);
      }
    }
  }

  static String _name(Hero hero) {
    final name = hero.kind.name;
    return 'The ${name[0].toUpperCase()}${name.substring(1)}';
  }
}

class CrawlHud extends StatelessWidget {
  const CrawlHud({
    super.key,
    required this.heroes,
    required this.lines,
    this.title,
  });

  final List<Hero> heroes;
  final List<String> lines;

  /// The level's name, shown for its first moments.
  final String? title;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Stack(
      children: <Widget>[
        Positioned(
          left: 12.0,
          right: 12.0,
          top: 12.0,
          child: Row(
            children: <Widget>[
              for (final hero in heroes) Expanded(child: _Panel(hero: hero)),
            ],
          ),
        ),
        if (title case final String name)
          Positioned(
            left: 0.0,
            right: 0.0,
            top: 96.0,
            child: Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFF2E6CF),
                fontSize: 28.0,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        Positioned(
          left: 0.0,
          right: 0.0,
          bottom: 48.0,
          child: Column(
            children: <Widget>[
              for (final line in lines)
                Text(
                  line,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFFFD27A),
                    fontSize: 22.0,
                    fontWeight: FontWeight.w700,
                    shadows: <Shadow>[Shadow(blurRadius: 4.0)],
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.hero});

  final Hero hero;

  @override
  Widget build(BuildContext context) {
    final c = colourOf(hero.kind);
    final colour = Color.fromARGB(
      255,
      (c.x * 255).round(),
      (c.y * 255).round(),
      (c.z * 255).round(),
    );
    final health = hero.health.current.ceil();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6.0),
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
      decoration: BoxDecoration(
        color: const Color(0xAA101014),
        border: Border(left: BorderSide(color: colour, width: 4.0)),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(color: Color(0xFFE8E2D6), fontSize: 14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              hero.kind.name.toUpperCase(),
              style: TextStyle(color: colour, fontWeight: FontWeight.w700),
            ),
            Text(
              hero.isAlive ? 'health $health' : 'fallen',
              style: TextStyle(
                color: hero.isAlive && health < Hero.hungryBelow
                    ? const Color(0xFFFF7A6B)
                    : null,
                fontSize: 18.0,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text('keys ${hero.keys}  potions ${hero.potions}'),
            Text('score ${hero.score}'),
          ],
        ),
      ),
    );
  }
}
