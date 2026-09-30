/// Two machines, one crawl, over a wire that is late and loses messages.
///
///     flutter test test/net_crawl_test.dart
///
/// Two crawls staged from the same document, each driving its own hero
/// through `flame_multiplayer`'s `RollbackPlay` over a `LoopbackWire` a
/// tenth of a second long that drops one frame message in ten. Generators pour, monsters die, shots
/// fly and potions are drunk while the sessions guess each other's hands and
/// roll back when a guess was wrong. Every step both sides settle has to be
/// the same crawl on both — the whole claim of a rollback session, on the
/// genre that is hardest on it: its bodies are born and buried as it goes.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flame_multiplayer/flame_multiplayer.dart';
import 'package:flutter3d_demo_crawler/src/level_open.dart';
import 'package:flutter3d_demo_crawler/src/net_crawl.dart';
import 'package:flutter3d_demo_crawler/src/staging.dart';
import 'package:flutter3d_game_crawler/flutter3d_game_crawler.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

StagedCrawl _stage() {
  final level = Level.fromJson(
    jsonDecode(File(levelAsset('kennels')).readAsStringSync())
        as Map<String, Object?>,
  );
  final world = CollisionWorld();
  level.addTo(world);
  world.update();
  return stage(
    level,
    world,
    party: <HeroClass>[HeroClass.elf, HeroClass.wizard],
    random: GameRandom(21),
  );
}

/// A player's hands on step [i], different for each [slot]: walking in
/// circles, firing in bursts, a potion now and then.
Map<String, Object?> _hands(int slot, int i) {
  final t = i / 60.0 + slot * 1.3;
  return heroFrame(
    math.cos(t * (slot == 0 ? 0.9 : 0.6)),
    math.sin(t * (slot == 0 ? 0.9 : 0.6)),
    fire: (i ~/ 20 + slot).isEven,
    drink: i == 200 + slot * 50,
  );
}

void main() {
  test('two machines settle every step on the same crawl', () {
    final (wireA, wireB) = LoopbackWire.pair(
      delaySteps: 6,
      lossRate: 0.1,
      seed: 5,
    );
    final a = _stage();
    final b = _stage();
    a.sim.heroes[0].potions = 1;
    b.sim.heroes[0].potions = 1;
    a.sim.heroes[1].potions = 1;
    b.sim.heroes[1].potions = 1;

    final settledA = <int, String>{};
    final settledB = <int, String>{};
    var stepA = 0;
    var stepB = 0;
    RollbackPlay<Snapshot> play(
      StagedCrawl crawl,
      int slot,
      PeerWire wire,
      Map<int, String> settled,
      int Function() step,
    ) => RollbackPlay<Snapshot>(
      wire: wire,
      localSlot: slot,
      capture: () => _hands(slot, step()),
      applyAndStep: (List<Map<String, Object?>> hands) {
        for (var i = 0; i < 2; i++) {
          applyHeroFrame(hands[i], crawl.sim.heroes[i]);
        }
        crawl.sim.step(1.0 / 60.0);
      },
      save: crawl.sim.save,
      restore: crawl.sim.restore,
      onSettled: (int step, Snapshot after) =>
          settled[step] = jsonEncode(after.data),
    );
    final hostSide = play(a, 0, wireA, settledA, () => stepA);
    final guestSide = play(b, 1, wireB, settledB, () => stepB);

    for (var i = 0; i < 600; i++) {
      hostSide.advance();
      guestSide.advance();
      stepA++;
      stepB++;
      wireA.tick();
      wireB.tick();
    }

    expect(hostSide.connected && guestSide.connected, isTrue);
    expect(hostSide.session.droppedCorrections, 0);
    expect(guestSide.session.droppedCorrections, 0);

    // **Against a crawl that never guessed**, not only against each other:
    // the two sides are symmetric, guess wrong on the same steps and roll
    // back as far, so a restore that loses something loses it on both and
    // they still agree. One machine applying both players' true frames,
    // each on the step the session applies it — captured `inputDelay`
    // steps earlier — is what a correct rollback has to come back to.
    final truth = _stage();
    truth.sim.heroes[0].potions = 1;
    truth.sim.heroes[1].potions = 1;
    const delay = 3;
    final settledTruth = <int, String>{};
    for (var s = 0; s < 600; s++) {
      for (final slot in const <int>[0, 1]) {
        applyHeroFrame(
          s >= delay ? _hands(slot, s - delay) : const <String, Object?>{},
          truth.sim.heroes[slot],
        );
      }
      truth.sim.step(1.0 / 60.0);
      settledTruth[s] = jsonEncode(truth.sim.save().data);
    }

    final common = settledA.keys.where(settledB.containsKey).toList()..sort();
    expect(common.length, greaterThan(500));
    for (final step in common) {
      expect(settledA[step], settledB[step], reason: 'diverged at step $step');
      expect(
        settledA[step],
        settledTruth[step],
        reason:
            'both sides agree, on something that did not happen, at step '
            '$step',
      );
    }
    // And something happened worth agreeing about.
    expect(a.horde.count + a.sim.heroes[0].score, greaterThan(0));
    expect(a.sim.heroes.every((Hero h) => h.potions == 0), isTrue);
  });

  test('a frame travels as whole hundredths and comes back the same', () {
    final hero = _stage().sim.heroes.first;
    applyHeroFrame(heroFrame(0.123456, -2.0, fire: true, drink: false), hero);

    // A Vector3 holds single precision; what matters is that both machines
    // apply the same hundredth, which the integer on the wire guarantees.
    expect(hero.wish.x, closeTo(0.12, 1e-6));
    expect(hero.wish.z, -1.0);
    expect(hero.fire, isTrue);
    expect(hero.drink, isFalse);
  });
}
