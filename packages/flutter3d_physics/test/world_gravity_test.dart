/// One gravity per world: the bodies and the characters read it there.
///
///     dart test test/world_gravity_test.dart
///
/// Decision 1 of `tasks/1.0-physics-audit.md`. A game ran three gravities:
/// `Dynamics`' own 22 m/s², `MovementSettings`' 24, and 9.81 for everything
/// else. Each now reads `CollisionWorld.properties`, so a world set on the
/// Moon is the Moon for the crate and for the runner beside it.
library;

import 'dart:math' as math;

import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1 / 60;

final WorldProperties _moon = WorldProperties(
  gravity: Vector3(0.0, -1.62, 0.0),
);

void main() {
  test('a crate falls by its world, and follows a change of it', () {
    // Mutation: give `Dynamics.step` a gravity of its own again — the crate
    // then falls at that whatever the world says.
    final world = CollisionWorld(properties: _moon);
    final dynamics = Dynamics(world: world);
    final crate = dynamics.add(
      RigidBody(
        world: world,
        shape: CollisionBox(Vector3.all(0.5)),
        position: Vector3(0.0, 10.0, 0.0),
      ),
    );
    dynamics.step(_dt);
    expect(crate.velocity.y, closeTo(-1.62 * _dt, 1e-6));
    expect(dynamics.gravity.y, closeTo(-1.62, 1e-6));

    world.properties = world.properties.copyWith(
      gravity: Vector3(0.0, -24.0, 0.0),
    );
    final before = crate.velocity.y;
    dynamics.step(_dt);
    expect(crate.velocity.y - before, closeTo(-24.0 * _dt, 1e-6));
  });

  test('the gravity a Dynamics is made with becomes the world\'s', () {
    final world = CollisionWorld();
    Dynamics(world: world, gravity: Vector3(0.0, -3.0, 0.0));
    expect(world.properties.gravity, Vector3(0.0, -3.0, 0.0));
  });

  test('a character falls by its world unless its tuning says otherwise', () {
    // Mutation: put `MovementSettings.gravity`'s 24 back as its default —
    // the walker then drops fifteen times as fast as its Moon.
    final world = CollisionWorld(properties: _moon);
    final walker = CharacterController(
      world: world,
      position: Vector3(0.0, 20.0, 0.0),
    );
    walker.step(_dt, wishDirection: Vector3.zero());
    expect(walker.gravity, closeTo(1.62, 1e-6));
    expect(walker.velocity.y, closeTo(-1.62 * _dt, 1e-5));

    final pinned = CharacterController(
      world: world,
      position: Vector3(5.0, 20.0, 0.0),
      tuning: const MovementSettings(gravity: 0.0),
    );
    pinned.step(_dt, wishDirection: Vector3.zero());
    expect(pinned.velocity.y, 0.0);
  });

  test('a save carries the world, and a restore puts it back', () {
    final world = CollisionWorld(properties: _moon);
    final dynamics = Dynamics(world: world);
    final saved = dynamics.saveState();
    world.properties = WorldProperties.standard;
    dynamics.restoreState(saved);
    expect(world.properties, _moon);
    // A save from before the world was saved changes nothing.
    dynamics.restoreState(null);
    expect(world.properties, _moon);
  });

  test('two materials meet as their measured pair, if they have one', () {
    // Rubber on concrete was measured, μ 0.8; a body's own numbers are the
    // rubber's and the concrete's otherwise.
    final world = CollisionWorld(properties: WorldProperties.standard);
    final floor = Collider(
      shape: CollisionBox(Vector3(10.0, 0.5, 10.0)),
      position: Vector3(0.0, -0.5, 0.0),
      material: Materials.concrete,
    );
    world.add(floor);
    final tyre = RigidBody(
      world: world,
      shape: CollisionBox(Vector3.all(0.25)),
      position: Vector3(0.0, 0.25, 0.0),
      material: Materials.rubber,
    );
    expect(tyre.friction, MaterialCatalog.defaultFriction);
    final steel = RigidBody(
      world: world,
      shape: CollisionBox(Vector3.all(0.25)),
      position: Vector3(3.0, 0.25, 0.0),
      material: Materials.steel,
    );
    expect(steel.friction, Materials.steel.mechanical!.friction);
    expect(
      world.materials.contact(Materials.rubber, Materials.concrete).friction,
      0.8,
    );
    expect(
      world.materials.contact(Materials.steel, Materials.glass).friction,
      closeTo(math.sqrt(0.57 * 0.4), 1e-12),
    );
  });
}
