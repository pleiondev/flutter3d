/// The sight kicks when the gun goes off, and the bullets go where it points.
///
///     flutter test test/recoil_test.dart
///
/// **A weapon whose picture kicks and whose aim does not has no recoil**, it
/// has an animation: the second shot of a burst lands exactly where the first
/// did, and a player who notices stops looking at the screen and holds the
/// trigger. This game had neither — every shot left along the same line as the
/// one before it, for ever.
library;

import 'dart:math' as math;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_shooter/flutter3d_shooter.dart';
import 'package:flutter3d_shooter/sample.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

/// Something that fires while the trigger is held.
///
/// Written here rather than taken from the sample, because the sample has no
/// automatic gun: the fists are the only weapon in it that fires on a held
/// trigger, and they have no recoil. The claim is about what recoil does to a
/// stream of shots, so the stream has to exist.
const WeaponDef _chaingun = WeaponDef(
  name: 'Chaingun',
  behaviour: HitscanBehaviour(),
  ammo: AmmoType.bullets,
  damage: 8.0,
  shotsPerSecond: 10.0,
  automatic: true,
  recoil: 0.02,
  recoilRecovery: 6.0,
);

final class _Range {
  _Range({WeaponDef? weapon}) {
    world
      ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(80.0, 1.0, 80.0))
      ..update();
    player = Player(
      body: CharacterController(world: world, position: Vector3(0.0, 0.9, 0.0)),
      inventory: Inventory(
        arsenal: Arsenal(
          slots: <WeaponDef>[weapon ?? Weapons.pistol],
          ammo: <AmmoType, int>{AmmoType.bullets: 400, AmmoType.shells: 400},
        ),
      ),
    );
    sim = GameSimulation(
      player: player,
      collision: world,
      input: input,
      shot: WeaponShot(
        world: world,
        hitscan: Hitscan(world: world, random: math.Random(7)),
        projectiles: ProjectileSystem(world: world),
      ),
    );
  }

  final CollisionWorld world = CollisionWorld();
  final InputState input = InputState();
  late final Player player;
  late final GameSimulation sim;

  void step({bool firing = false, int times = 1}) {
    for (var i = 0; i < times; i++) {
      input.beginStep();
      if (firing) {
        input.press(ShooterActions.fire);
      } else {
        input.release(ShooterActions.fire);
      }
      sim.step(_dt);
      input.endStep();
    }
  }

  /// How high the crosshair is pointing, in radians.
  double get sight {
    final out = Vector3.zero();
    player.aim(out);
    return math.asin(out.y.clamp(-1.0, 1.0));
  }
}

void main() {
  test('a shot lifts the sight', () {
    final it = _Range();
    final before = it.sight;

    it.step(firing: true);

    expect(it.sight, greaterThan(before), reason: 'the gun went off and the '
        'crosshair did not move, which is a weapon with no recoil');
  });

  test('and the shot goes where the sight points, not where it pointed', () {
    // **The half that makes it a mechanic rather than an animation.** If the
    // kick lived only in the view model, a burst would put every bullet through
    // the same hole.
    final it = _Range(weapon: Weapons.shotgun);
    it.step(firing: true);
    final lifted = it.sight;

    final aim = Vector3.zero();
    it.player.aim(aim);

    expect(math.asin(aim.y), closeTo(lifted, 1e-9));
    expect(aim.y, greaterThan(0.0),
        reason: 'the bullets still leave along the old line');
  });

  test('and it comes back down when the trigger is released', () {
    final it = _Range(weapon: Weapons.shotgun);
    final level = it.sight;
    it.step(firing: true);
    final lifted = it.sight;
    expect(lifted, greaterThan(level));

    it.step(times: 120);

    expect(it.sight, closeTo(level, 1e-4),
        reason: 'the sight stayed up: a player is left looking at the ceiling');
  });

  test('and holding an automatic climbs', () {
    // Ten times a second and pulled back at the weapon's own rate: the climb is
    // what the player has to control.
    final it = _Range(weapon: _chaingun);
    it.step(firing: true);
    final afterOne = it.sight;

    it.step(firing: true, times: 240);

    expect(it.sight, greaterThan(afterOne),
        reason: 'a burst that does not climb is a burst nobody has to control');
  });

  test('and the player is left pointing where they were pointing', () {
    // **Not folded into the player's own pitch, which would be the game moving
    // the thing the player is holding.** They let go of the trigger and would
    // be left looking at the ceiling, having never asked to.
    final it = _Range(weapon: Weapons.shotgun);
    final aimed = it.player.pitch;

    it.step(firing: true, times: 60);

    expect(it.player.pitch, aimed);
  });

  test('and a weapon given no recoil does not kick', () {
    // Every weapon that has not been given a number behaves as it did, which is
    // what a default of zero is for.
    final it = _Range(weapon: Weapons.fists);
    final before = it.sight;

    it.step(firing: true, times: 30);

    expect(it.sight, closeTo(before, 1e-9));
  });

  test('and the climb is the same at any frame rate', () {
    // The property every easing in this repository keeps: a weapon that climbed
    // differently at thirty and at a hundred and forty-four frames would be a
    // different weapon on two machines.
    double settledAfter(double dt, int steps) {
      final it = _Range(weapon: Weapons.shotgun);
      it.player.kick(0.2);
      for (var i = 0; i < steps; i++) {
        it.player.settleRecoil(dt);
      }
      return it.player.recoilPitch;
    }

    expect(settledAfter(1 / 240.0, 240), closeTo(settledAfter(1 / 30.0, 30), 1e-9));
  });
}
