/// Two `CrawlerGame`s, one crawl: the online mode as the app runs it.
///
///     flutter test test/online_game_test.dart
///
/// `net_crawl_test` holds the rollback to the crawl with nothing else around
/// it; this is the rest of the way — the handshake that tells each machine
/// the other's class, the party put in the room's order on both, the level
/// entered through the game's own `enter`, and its steps driven by
/// `fixedUpdate` through a session on the level's own channel, over a wire
/// that is late and loses messages. Every step both games settle must be the
/// same crawl on both.
library;

import 'dart:convert';

import 'package:flame_multiplayer/flame_multiplayer.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_demo_crawler/src/crawler_game.dart';
import 'package:flutter3d_game_crawler/flutter3d_game_crawler.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show Snapshot;
import 'package:flutter_test/flutter_test.dart';

Future<CrawlerGame> _game(
  String hero,
  int slot,
  Map<String, String> settled,
) async {
  final it = cpuTestDevice(width: 8, height: 8);
  final game =
      CrawlerGame(
          party: <String>[hero],
          room: 'test',
          slot: slot,
          onSettled: (String level, int step, Snapshot after) =>
              settled['$level/$step'] = jsonEncode(after.data),
        )
        ..open3d(it.device)
        ..attachRenderer(Renderer.create(device: it.device));
  await initializeGame(() => game);
  return game;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('two games shake hands, go in together and agree', () async {
    final (wireA, wireB) = LoopbackWire.pair(
      delaySteps: 3,
      lossRate: 0.1,
      seed: 3,
    );
    final settledA = <String, String>{};
    final settledB = <String, String>{};
    final host = await _game('elf', 0, settledA);
    final guest = await _game('wizard', 1, settledB);
    expect(host.phase, CrawlPhase.connecting);

    host.goOnline(wireA);
    guest.goOnline(wireB);

    Future<void> frame() async {
      host.update(1.0 / 60.0);
      guest.update(1.0 / 60.0);
      wireA.tick();
      wireB.tick();
      await Future<void>.delayed(Duration.zero);
      await host.ready();
      await guest.ready();
    }

    for (
      var i = 0;
      i < 400 &&
          (host.phase != CrawlPhase.playing ||
              guest.phase != CrawlPhase.playing);
      i++
    ) {
      await frame();
    }
    expect(host.phase, CrawlPhase.playing, reason: 'the host never went in');
    expect(guest.phase, CrawlPhase.playing, reason: 'the guest never went in');

    // Hero nought is the room's maker on both machines.
    for (final game in <CrawlerGame>[host, guest]) {
      expect(
        <HeroClass>[for (final hero in game.staged!.sim.heroes) hero.kind],
        <HeroClass>[HeroClass.elf, HeroClass.wizard],
      );
    }

    for (var i = 0; i < 240; i++) {
      await frame();
    }

    final common = settledA.keys.where(settledB.containsKey).toList();
    expect(common.length, greaterThan(150), reason: 'too little agreed on');
    for (final key in common) {
      expect(settledA[key], settledB[key], reason: 'diverged at $key');
    }
  });
}
