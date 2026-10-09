/// What the crypt rings under the high-contrast look — `N9`.
///
///     flutter test test/high_contrast_rings_test.dart
///
/// The engine draws a ring round whatever carries a colour; this is the
/// game's half, and the whole of it is one question: what in this room
/// matters, and in whose colour. A monster that is alive, a key in its own
/// colour, anything else on the floor in the pickups'; never the room itself.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_demo_dungeon/src/high_contrast_rings.dart';
import 'package:flutter3d_demo_dungeon/src/hud.dart';
import 'package:flutter3d_game/flutter3d_game.dart'
    show ColorRoles, GameSettings, outlineColorOf;
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

Actor _monster({bool dead = false}) {
  final world = CollisionWorld();
  final actor = ActorSystem(world: world, random: GameRandom(1)).spawn(
    body: CharacterController(world: world),
    health: Health(10.0),
  );
  if (dead) actor.health!.damage(999.0);
  return actor;
}

Fixture _lying(Gift gift, {String? detail, Mechanism? instead}) {
  final world = CollisionWorld();
  return Fixture(
    entity: EntityDef(type: 'pickup', position: Vector3.zero()),
    size: Vector3.all(0.3),
    material: 'brass',
    at: Vector3.zero(),
    mechanism:
        instead ??
        Pickup(
          gift: gift,
          amount: 1.0,
          detail: detail,
          collider: world.add(
            Collider(
              shape: CollisionBox(Vector3.all(0.3)),
              position: Vector3.zero(),
              kind: ColliderKind.trigger,
            ),
          ),
        ),
  );
}

void main() {
  const config = GameSettings();
  final rings = CryptRings(() => config);

  Vector3 roleColour(String name) => outlineColorOf(
    dungeonColours.colorOf(name, config, fallback: Colors.white),
  );

  test('a living monster is ringed in the monsters\' colour', () {
    // Mutation: ring every actor whatever its health, and the dead keep a
    // ring the room has to be searched past.
    expect(rings.actor(_monster()), roleColour('monster'));
    expect(rings.actor(_monster(dead: true)), isNull);
  });

  test('a key in its own colour, anything else in the pickups\'', () {
    // A key's ring is the colour its door is drawn in on the HUD, so the
    // two can be matched by eye. Mutation: ring every pickup in the
    // pickups' colour.
    expect(
      rings.fixture(_lying(const KeyGift(), detail: 'brass')),
      roleColour('key.brass'),
    );
    expect(rings.fixture(_lying(const HealthGift())), roleColour('pickup'));
    expect(roleColour('pickup'), isNot(roleColour('key.brass')));
  });

  test('and the room is not ringed', () {
    // A torch is the room, not the quarry; so is a box with nothing in it.
    // Mutation: ring every fixture in the pickups' colour.
    expect(
      rings.fixture(
        _lying(const KeyGift(), instead: LightFixture(light: 'brazier')),
      ),
      isNull,
    );
  });

  test('a colour the player chose is the ring\'s', () {
    // The point of a role over a colour: the player who cannot tell the
    // monsters' ring from a key moves it in the settings, and the ring
    // follows. Mutation: read the role's default rather than `colorOf`.
    final role = dungeonColours.named('monster')!;
    final chosen = const GameSettings().withValue(role.setting, 3);
    expect(
      CryptRings(() => chosen).actor(_monster()),
      outlineColorOf(ColorRoles.choices(role)[3]),
    );
    expect(
      CryptRings(() => chosen).actor(_monster()),
      isNot(roleColour('monster')),
    );
  });
}
