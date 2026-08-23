/// What the crypt shows, asked of the level the game ships.
///
///     flutter test test/reactions_test.dart
///
/// **The word "particle" did not appear anywhere in this application's tests.**
/// A monster that dies with no sparks, a shot with no muzzle flare and a rocket
/// that lands with no fire were each a thing somebody had to happen to notice,
/// because the decisions lived in three private methods of a `State` that
/// nothing can mount.
///
/// The platformer reached the same place from the other direction: its
/// `Soundtrack` claimed the visible half was "already covered by the frame
/// tests", and it was not covered by anything.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_demo_dungeon/src/effects.dart';
import 'package:flutter3d_demo_dungeon/src/reactions.dart';
import 'package:flutter3d_demo_dungeon/src/staging.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_game_shooter/sample.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:flutter_test/flutter_test.dart';

const double _dt = 1.0 / 60.0;

Level _crypt() => Level.fromJson(
      jsonDecode(File('assets/levels/crypt.json').readAsStringSync())
          as Map<String, Object?>,
    );

/// The shipped level, the shipped registry, and eyes on the result.
final class _Run {
  _Run({Inventory? inventory}) {
    level.addTo(world);
    staged = stage(
      level,
      world,
      input: input,
      registry: sampleRegistry(),
      inventory: inventory ?? startingInventory(),
    );
    world.update();
  }

  final Level level = _crypt();
  final CollisionWorld world = CollisionWorld();
  final InputState input = InputState();
  late final Staged staged;

  final Reactions reactions = Reactions();
  final List<Shown> shown = <Shown>[];
  final List<Lingering> lingering = <Lingering>[];
  int flashes = 0;

  /// Every hit of every step, because `sim.hits` holds only the last one's.
  final List<ShotHit> hits = <ShotHit>[];

  void run(int steps, {Set<GameAction> holding = const <GameAction>{}}) {
    for (var i = 0; i < steps; i++) {
      input.beginStep();
      for (final action in holding) {
        input.press(action);
      }
      staged.sim.step(_dt);
      input.endStep();
      for (final action in holding) {
        input.release(action);
      }
      hits.addAll(staged.sim.hits);
      final reaction = reactions.listen(staged.sim, staged.player);
      shown.addAll(reaction.bursts);
      lingering.addAll(reaction.lingering);
      if (reaction.flash) flashes++;
    }
  }

  bool saw(ParticleEffect effect) =>
      shown.any((Shown s) => identical(s.effect, effect));
}

void main() {
  test('firing shows a flare at the barrel, not at the eye', () {
    // The one thing that should *not* be at the eye — unlike the sound, which
    // pans audibly wrong anywhere else. Mutation: use `firedFrom` unchanged and
    // the flash comes out of the player's forehead.
    final run = _Run()..run(2, holding: <GameAction>{ShooterActions.fire});

    expect(run.saw(Effects.muzzleFlash), isTrue, reason: 'no flare at all');
    final flare = run.shown.firstWhere(
      (Shown s) => identical(s.effect, Effects.muzzleFlash),
    );
    final eye = run.staged.sim.firedFrom;
    expect(flare.at.distanceTo(eye), greaterThan(0.3),
        reason: 'the flare is inside the player');
    expect(flare.direction, isNotNull, reason: 'a flare with no barrel line');
  });

  test('and a shot that lands shows it where it landed', () {
    // Sparks and dust at the point, leaning along the surface normal. Both,
    // because one alone reads as a spark on nothing.
    final run = _Run()
      ..run(6, holding: <GameAction>{ShooterActions.fire});

    expect(run.hits.any((ShotHit h) => h.struckSomething), isTrue,
        reason: 'nothing in the crypt was hit, so this proves nothing');
    expect(run.saw(Effects.impactSparks), isTrue);
    expect(run.saw(Effects.impactDust), isTrue);
  });

  test('and a shot that lands flashes the screen', () {
    // Whether, not how much: how much is the player's accessibility setting,
    // and `Reactions` has no business deciding it.
    final run = _Run()..run(6, holding: <GameAction>{ShooterActions.fire});

    expect(run.flashes, greaterThan(0));
  });

  test('and a shot at nothing does not', () {
    // Mutation: flash on every shot rather than on every hit. The screen
    // strobes for as long as the trigger is held, which is exactly the
    // photosensitivity problem the setting exists for.
    //
    // The shot is staged rather than aimed away, because every direction in a
    // crypt eventually meets a wall — and what is being checked is the rule,
    // not the level's floor plan.
    //
    // **`firedThisStep` is set on purpose, and the first version of this test
    // did not.** It cleared the hits and called `listen`, which passed — but it
    // passed because the pistol is semi-automatic, so no shot had been fired on
    // the last step either. It was true for a reason other than the one it was
    // written for, and the mutation it exists to catch walked straight through.
    final run = _Run()..run(2, holding: <GameAction>{ShooterActions.fire});
    expect(run.flashes, greaterThan(0), reason: 'it never flashed at all');

    run.staged.sim
      ..firedThisStep = Weapons.pistol
      ..hits.clear();
    final reaction = run.reactions.listen(run.staged.sim, run.staged.player);

    expect(reaction.flash, isFalse);
  });

  test('a rocket leaves fire that outlives it', () {
    // A burst cannot say "for the next second", which is why `Lingering`
    // exists. Mutation: emit the smoke as a burst and the explosion is over
    // before the fire is.
    final loaded = startingInventory();
    loaded.arsenal.selectSlot(3);
    final run = _Run(inventory: loaded);
    run.staged.player.pitch = -0.2;
    run.run(40, holding: <GameAction>{ShooterActions.fire});

    expect(run.staged.sim.projectiles?.detonations, isNotNull);
    expect(run.saw(Effects.explosionCore), isTrue, reason: 'no fire');
    expect(run.lingering, isNotEmpty, reason: 'no smoke after the fire');
    expect(run.lingering.first.seconds, greaterThan(0.5));
  });

  test('and two rockets are two plumes, not one restarted', () {
    // The key is a fresh object per blast rather than the position: two rockets
    // landing in the same doorway under one key would be the second cancelling
    // the first.
    final loaded = startingInventory();
    loaded.arsenal.selectSlot(3);
    final run = _Run(inventory: loaded);
    run.staged.player.pitch = -0.2;
    run.run(120, holding: <GameAction>{ShooterActions.fire});

    expect(run.lingering.length, greaterThan(1), reason: 'only one rocket flew');
    expect(run.lingering.map((Lingering l) => l.key).toSet(),
        hasLength(run.lingering.length));
  });
}
