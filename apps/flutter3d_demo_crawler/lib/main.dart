/// Up to four heroes, one screen, and a maze that keeps making monsters.
///
///     flutter run -d macos
///     flutter run -d macos --dart-define=CRAWLER_PARTY=warrior,elf
///
/// Two machines, one crawl, through the relay `flutter3d_net` ships
/// (`dart run flutter3d_net:relay 8199`): one makes the room, the other
/// joins it, and each plays its own hero from WASD.
///
///     flutter run -d macos --dart-define=CRAWLER_ROOM=cave \
///       --dart-define=CRAWLER_PARTY=elf
///     flutter run -d macos --dart-define=CRAWLER_ROOM=cave \
///       --dart-define=CRAWLER_JOIN=true --dart-define=CRAWLER_PARTY=wizard
///
/// `--dart-define=relay=ws://host:8199/` points both at a relay elsewhere.
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

import 'dart:async';

// Flutter's `Hero` is a page transition; this game's is somebody holding a
// controller.
import 'package:flame/game.dart' show FlameGame;
import 'package:flame_flutter3d/flame_flutter3d.dart';
import 'package:flutter/material.dart' hide Hero, Material;
import 'package:flutter3d_net/flutter3d_net.dart' show WebSocketTransport;

import 'src/crawler_game.dart';
import 'src/screens.dart';

/// A party to go straight in with, skipping the select screen:
/// `--dart-define=CRAWLER_PARTY=warrior,elf`, the first on WASD and the
/// second on the arrows. For a demo, and for looking at a level at once.
const String _party = String.fromEnvironment('CRAWLER_PARTY');

/// The room to play online in; empty for one screen.
const String _room = String.fromEnvironment('CRAWLER_ROOM');

/// Whether this machine joins [_room] rather than making it: whoever made it
/// drives hero nought on both machines, whoever joined hero one.
const bool _join = bool.fromEnvironment('CRAWLER_JOIN');

/// Where the relay is.
final Uri _relay = Uri.parse(
  const String.fromEnvironment('relay', defaultValue: 'ws://127.0.0.1:8199/'),
);

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
    // Online, a machine's hero goes in as whatever it names, a warrior if
    // nothing: there is no select screen to share.
    party: _party.isNotEmpty
        ? _party.split(',')
        : _room.isNotEmpty
        ? const <String>['warrior']
        : const <String>[],
    room: _room.isEmpty ? null : _room,
    slot: _join ? 1 : 0,
  );

  @override
  void initState() {
    super.initState();
    if (_room.isNotEmpty) unawaited(_connect());
  }

  Future<void> _connect() async {
    try {
      _game.goOnline(
        await WebSocketTransport.connect(_relay.resolve('room/$_room')),
      );
    } on Object catch (error) {
      _game.message = 'No relay at $_relay: $error';
    }
  }

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
