/// Ground made of samples, and the joins between its triangles.
///
/// **The file is arranged around one failure**, because that failure is what
/// the shape was written to survive: a body sliding along the surface meets the
/// vertical face where one triangle ends and the next begins, and is stopped by
/// a wall nobody drew or shoved sideways out of the hillside. The group called
/// "the seams between triangles" holds the two measurements that catch it, and
/// both were watched failing before the filtering existed —
/// `CollisionShape.partSeams` returning nothing turns twenty-four of forty-one
/// slides into a horizontal contact and eight of forty-one depenetrations into
/// a sideways shove.
///
/// The rest of the file is the ordinary shape: what it is, what a ray meets,
/// what a body stands on, and what a capsule now rounds that a box does not.
library;

import 'dart:typed_data';

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A field of 33 by 33 samples a metre apart, its heights from [height].
///
/// Big enough that a body can walk for three seconds without reaching the rim,
/// which matters: the ground simply ends there, and a test that wandered off it
/// would be measuring the fall rather than the walk.
CollisionHeightfield ground(double Function(int column, int row) height) {
  const n = 33;
  return CollisionHeightfield(
    columns: n,
    rows: n,
    cellSize: 1.0,
    heights: Float32List.fromList(<double>[
      for (var row = 0; row < n; row++)
        for (var column = 0; column < n; column++) height(column, row),
    ]),
  );
}

CollisionWorld worldOf(CollisionHeightfield field) {
  final world = CollisionWorld()
    ..add(Collider(shape: field, position: Vector3.zero()));
  world.update();
  return world;
}

const double _dt = 1.0 / 60.0;
final Vector3 _origin = Vector3.zero();

void main() {
  group('a field of samples', () {
    test('is centred on its collider, surface and all', () {
      final field = ground((column, row) => 0.0);
      // Thirty-two metres across, level, and one cell of solid under it.
      expect(field.width, 32.0);
      expect(field.depth, 32.0);
      expect(field.thickness, 1.0);
      expect(field.boundsHalfExtents.x, 16.0);
      expect(field.boundsHalfExtents.z, 16.0);
      // Half the sample spread plus the thickness, counted both ways so that
      // the surface's middle is where the collider was put.
      expect(field.boundsHalfExtents.y, 1.0);
      expect(field.heightAt(_origin, 0.0, 0.0), 0.0);
      expect(field.heightAt(_origin, -15.5, 7.25), 0.0);
    });

    test('and reads the drawn surface, not a curve through the samples', () {
      // A single raised corner, so the two triangles of its cell disagree about
      // the middle in exactly the way a bilinear answer would hide.
      final field = ground(
        (column, row) => column == 17 && row == 17 ? 4.0 : 0.0,
      );
      // Sample (17, 17) sits at local (17, 17), which is world (1, 1).
      expect(field.heightAt(_origin, 1.0, 1.0), closeTo(4.0 - 2.0, 1e-6));
      // The middle of the cell below and left of it lies on the diagonal, where
      // both triangles agree.
      expect(field.heightAt(_origin, 0.5, 0.5), closeTo(2.0 - 2.0, 1e-6));
      // And a point off the field meets the edge it can see rather than a cliff
      // to nothing.
      expect(
        field.heightAt(_origin, -40.0, 0.0),
        field.heightAt(_origin, -16.0, 0.0),
      );
    });

    test('and hands back the triangles near a box and no others', () {
      final field = ground((column, row) => 0.0);
      final parts = Int32List(64);
      // A box a quarter of a metre across, over one cell.
      final count = field.partsIn(
        _origin,
        Vector3(0.4, -0.5, 0.4),
        Vector3(0.6, 0.5, 0.6),
        parts,
      );
      expect(count, 2, reason: 'one cell is two triangles');

      // And nothing at all when the box misses the ground: the caller then
      // walks no parts rather than the nearest one.
      expect(
        field.partsIn(
          _origin,
          Vector3(40.0, -0.5, 0.0),
          Vector3(41.0, 0.5, 1.0),
          parts,
        ),
        0,
      );
      expect(
        field.partsIn(
          _origin,
          Vector3(0.0, 40.0, 0.0),
          Vector3(1.0, 41.0, 1.0),
          parts,
        ),
        0,
      );
    });

    test('and says how many parts it has even when the buffer cannot hold '
        'them', () {
      final field = ground((column, row) => 0.0);
      final tiny = Int32List(2);
      final count = field.partsIn(
        _origin,
        Vector3(-4.0, -0.5, -4.0),
        Vector3(4.0, 0.5, 4.0),
        tiny,
      );
      // Nine cells by nine — a box eight metres across touches the cell at
      // each end — two triangles each. The answer is the total rather than
      // what fitted, or a caller would quietly collide with two triangles of a
      // hundred and sixty-two.
      expect(count, 162);
    });

    test('and is not one convex solid, and says so rather than pretending', () {
      final field = ground((column, row) => 0.0);
      // The single-solid door answers with nothing, which is a miss. Writing
      // the bounding box here would make the ground a block of stone with the
      // hills buried in it.
      expect(field.expandedPlaneCount, 0);
      expect(field.expandedPlanes(_origin, Vector3.zero(), Float64List(24)), 0);
      expect(field.partPlaneCount, 5);
    });
  });

  group('a body meeting the ground', () {
    test('lands on it, facing up', () {
      final world = worldOf(ground((column, row) => 0.0));
      final hit = SweepHit();
      final body = CollisionBox(Vector3(0.35, 0.9, 0.35));
      expect(
        world.sweep(body, Vector3(0.5, 3.0, 0.5), Vector3(0.0, -4.0, 0.0), hit),
        isTrue,
      );
      // The surface is at zero, so a body half a metre and a bit tall stops
      // with its centre at 0.9.
      expect(3.0 - 4.0 * hit.fraction, closeTo(0.9, 1e-6));
      expect(hit.normal.y, closeTo(1.0, 1e-6));
    });

    test('and on a slope the normal leans, which is the whole point', () {
      // A metre of rise per metre of run: forty-five degrees.
      final field = ground((column, row) => column * 1.0);
      final world = worldOf(field);
      final hit = SweepHit();
      final body = CollisionBox(Vector3(0.35, 0.9, 0.35));
      expect(
        world.sweep(
          body,
          Vector3(0.0, 8.0, 0.5),
          Vector3(0.0, -12.0, 0.0),
          hit,
        ),
        isTrue,
      );
      expect(hit.normal.y, closeTo(0.70710678, 1e-6));
      expect(hit.normal.x, closeTo(-0.70710678, 1e-6));
      expect(hit.normal.z, closeTo(0.0, 1e-6));
    });

    test('and a walker crosses a level field without losing its footing', () {
      final field = ground((column, row) => 0.0);
      final world = worldOf(field);
      final walker = CharacterController(
        world: world,
        position: Vector3(-8.0, 0.9, 0.6),
      );
      for (var step = 0; step < 120; step++) {
        walker.step(_dt, wishDirection: Vector3(1.0, 0.0, 0.0));
        expect(
          walker.isGrounded,
          isTrue,
          reason: 'the ground was lost at step $step, at ${walker.position}',
        );
        expect(walker.position.y, closeTo(0.901, 1e-3));
      }
      expect(walker.position.x, greaterThan(-8.0 + 10.0));
    });

    test('and walks down a hillside glued to it', () {
      // A quarter of a metre of drop per metre travelled.
      final field = ground((column, row) => -column * 0.25);
      final world = worldOf(field);
      final start = field.heightAt(_origin, -8.0, 0.5);
      final walker = CharacterController(
        world: world,
        position: Vector3(-8.0, start + 0.9, 0.5),
      );
      for (var step = 0; step < 120; step++) {
        walker.step(_dt, wishDirection: Vector3(1.0, 0.0, 0.0));
        final under = field.heightAt(
          _origin,
          walker.position.x,
          walker.position.z,
        );
        // A tenth of a metre of slack, because a body walking downhill leaves
        // the surface for the fraction of a step it takes gravity and the
        // floor snap to catch it. Leaving the hillside means metres, not this.
        expect(
          walker.position.y - under,
          closeTo(0.95, 0.1),
          reason: 'left the hillside at step $step',
        );
        expect(walker.isGrounded, isTrue, reason: 'airborne at step $step');
      }
      expect(walker.position.x, greaterThan(0.0));
    });

    test('and climbs one, more slowly than it walks on the level', () {
      final field = ground((column, row) => column * 0.3);
      final world = worldOf(field);
      final start = field.heightAt(_origin, -8.0, 0.5);
      final walker = CharacterController(
        world: world,
        position: Vector3(-8.0, start + 0.9, 0.5),
      );
      for (var step = 0; step < 120; step++) {
        walker.step(_dt, wishDirection: Vector3(1.0, 0.0, 0.0));
      }
      final under = field.heightAt(_origin, walker.position.x, 0.5);
      expect(walker.isGrounded, isTrue);
      expect(walker.position.y - under, closeTo(0.95, 0.11));
      expect(
        walker.groundNormal.y,
        closeTo(0.9578, 1e-3),
        reason: 'the controller kept the face it is standing on',
      );
      expect(walker.position.x, greaterThan(-8.0));
    });

    test('and is pushed straight up out of the ground, not sideways', () {
      final world = worldOf(ground((column, row) => 0.0));
      final push = Vector3.zero();
      expect(
        world.depenetrate(
          Vector3(0.73, 0.85, 0.41),
          Vector3(0.35, 0.9, 0.35),
          push,
        ),
        isTrue,
      );
      expect(push.y, closeTo(0.05, 1e-5));
      expect(push.x, 0.0);
      expect(push.z, 0.0);
    });

    test('and a flat body under level ground is pushed out too', () {
      // **What [CollisionHeightfield.thickness] is for.** Each triangle becomes
      // a solid by being extended downwards, and the growth by the moving
      // body's own height hides a solid of no depth for anything person-shaped.
      // A body flatter than the noise — a puck, a mine, a dropped plate — is
      // where it stops being hidden: with no thickness the ground it is a
      // centimetre inside has no inside, and it is left there for ever.
      final world = worldOf(ground((column, row) => 0.0));
      final push = Vector3.zero();
      expect(
        world.depenetrate(
          Vector3(0.4, -0.02, 0.4),
          Vector3(0.1, 0.02, 0.1),
          push,
        ),
        isTrue,
      );
      expect(push.y, closeTo(0.04, 1e-5));
    });

    test('and is left alone when it is clear of the ground', () {
      final world = worldOf(ground((column, row) => 0.0));
      final push = Vector3.zero();
      expect(
        world.depenetrate(
          Vector3(0.73, 2.0, 0.41),
          Vector3(0.35, 0.9, 0.35),
          push,
        ),
        isFalse,
      );
      expect(push, Vector3.zero());
    });
  });

  group('the seams between triangles', () {
    // **The two measurements this shape exists to pass.** Each walks a whole
    // cell, a fortieth at a time, so every distance from a join is covered
    // rather than one lucky one. Both were watched failing: with
    // `CollisionShape.partSeams` returning nothing, the first catches
    // twenty-four of the forty-one and the second shoves eight of them
    // sideways.
    test('do not stop a body sliding along the surface', () {
      final world = worldOf(ground((column, row) => 0.0));
      final hit = SweepHit();
      final body = CollisionBox(Vector3(0.35, 0.9, 0.35));
      final caught = <double>[];

      for (var i = 0; i <= 40; i++) {
        final x = 0.5 + i / 40.0;
        // Exactly on the surface, which is where a body put down by the ground
        // probe sits and where the joins are hardest.
        world.sweep(body, Vector3(x, 0.9, 0.53), Vector3(0.4, 0.0, 0.0), hit);
        if (hit.hit) caught.add(x);
      }

      expect(
        caught,
        isEmpty,
        reason:
            'a level field stopped a body sliding along it at $caught — those '
            'are the vertical faces where one triangle ends and the next '
            'begins, and the ground goes straight through them',
      );
    });

    test('do not shove a body sideways out of the ground', () {
      final world = worldOf(ground((column, row) => 0.0));
      final push = Vector3.zero();
      final sideways = <double>[];

      for (var i = 0; i <= 40; i++) {
        final x = 0.5 + i / 40.0;
        // Five centimetres under a level surface: straight up is the only
        // honest way out, wherever in the cell it happens to be.
        world.depenetrate(
          Vector3(x, 0.85, 0.53),
          Vector3(0.35, 0.9, 0.35),
          push,
        );
        if (push.x.abs() > 1e-9 || push.z.abs() > 1e-9) sideways.add(x);
        expect(push.y, closeTo(0.05, 1e-5));
      }

      expect(
        sideways,
        isEmpty,
        reason:
            'a body under level ground was pushed along it at $sideways, which '
            'is the join between two triangles being read as a wall',
      );
    });

    test('and a ray passes through them rather than stopping on one', () {
      final world = worldOf(ground((column, row) => 0.0));
      final hit = RayHit();
      // Along the surface, a hair above it, right across four cells. Every
      // join it crosses is a vertical face of some prism.
      expect(
        world.raycast(
          Vector3(-2.0, 0.001, 0.37),
          Vector3(1.0, 0.0, 0.0),
          6.0,
          hit,
        ),
        isFalse,
        reason: 'the ray was stopped by a join between two triangles',
      );
    });
  });

  group('a ray against the ground', () {
    test('meets the surface under where it was fired', () {
      final field = ground((column, row) => column * 0.5);
      final world = worldOf(field);
      final hit = RayHit();
      expect(
        world.raycast(
          Vector3(3.25, 20.0, -1.6),
          Vector3(0.0, -1.0, 0.0),
          40.0,
          hit,
        ),
        isTrue,
      );
      expect(
        hit.point.y,
        closeTo(field.heightAt(_origin, 3.25, -1.6), 1e-4),
        reason: 'the ray and the height function describe one surface',
      );
      expect(hit.normal.y, greaterThan(0.0));
    });

    test('and finds a hill it is fired across', () {
      // A ridge eight metres high down the middle of the field.
      final field = ground((column, row) => column == 16 ? 8.0 : 0.0);
      final world = worldOf(field);
      final hit = RayHit();
      // Fired level, well above the flat ground and well below the ridge.
      expect(
        world.raycast(
          Vector3(-8.0, 0.0, 0.5),
          Vector3(1.0, 0.0, 0.0),
          20.0,
          hit,
        ),
        isTrue,
        reason: 'the walk across the cells never reached the ridge',
      );
      expect(hit.point.x, lessThan(0.0));
      expect(hit.point.x, greaterThan(-1.5));
    });

    test('and misses a field it is fired over', () {
      final world = worldOf(ground((column, row) => 0.0));
      final hit = RayHit();
      expect(
        world.raycast(
          Vector3(-8.0, 5.0, 0.5),
          Vector3(1.0, 0.0, 0.0),
          20.0,
          hit,
        ),
        isFalse,
      );
    });

    test('and misses a field it is fired away from', () {
      final world = worldOf(ground((column, row) => 0.0));
      final hit = RayHit();
      expect(
        world.raycast(
          Vector3(0.5, 5.0, 0.5),
          Vector3(0.0, 1.0, 0.0),
          40.0,
          hit,
        ),
        isFalse,
      );
    });
  });

  group('overlap against the ground', () {
    final field = ground((column, row) => column * 0.5);

    test('a sphere is in it when it is under the surface', () {
      final under = Vector3(2.0, field.heightAt(_origin, 2.0, 0.0) - 0.1, 0.0);
      final over = Vector3(2.0, field.heightAt(_origin, 2.0, 0.0) + 1.0, 0.0);
      final sphere = CollisionSphere(0.4);
      expect(field.overlaps(_origin, sphere, under), isTrue);
      expect(field.overlaps(_origin, sphere, over), isFalse);
      // And the answer is the same whichever side asks.
      expect(sphere.overlaps(under, field, _origin), isTrue);
    });

    test('a capsule is in it when its feet are', () {
      final capsule = CollisionCapsule(radius: 0.3, halfHeight: 0.6);
      final surface = field.heightAt(_origin, -3.0, 1.0);
      expect(
        field.overlaps(_origin, capsule, Vector3(-3.0, surface + 0.5, 1.0)),
        isTrue,
      );
      expect(
        field.overlaps(_origin, capsule, Vector3(-3.0, surface + 3.0, 1.0)),
        isFalse,
      );
    });

    test('a box is in it, and off the field nothing is', () {
      final box = CollisionBox(Vector3.all(0.5));
      final surface = field.heightAt(_origin, 4.0, 4.0);
      expect(
        field.overlaps(_origin, box, Vector3(4.0, surface - 0.2, 4.0)),
        isTrue,
      );
      // Beyond the rim the ground has ended, whatever the nearest edge's height
      // would say.
      expect(
        field.overlaps(_origin, box, Vector3(40.0, surface - 0.2, 4.0)),
        isFalse,
      );
    });
  });

  group('a capsule against a slope', () {
    // **What the growth being a shape's own business bought.** A capsule swept
    // as its bounding box is grown along a leaning face by nearly half a radius
    // too much, which is the shoulder it catches on a corner it should round.
    // The two figures below are the same sweep with the two growths.
    test('reaches further than the box around it', () {
      final world = worldOf(ground((column, row) => column * 1.0));
      final hit = SweepHit();
      final capsule = CollisionCapsule(radius: 0.35, halfHeight: 0.55);
      final box = CollisionBox(capsule.boundsHalfExtents);

      world.sweep(capsule, Vector3(0.0, 4.0, 0.5), Vector3(3.0, 0.0, 0.0), hit);
      final rounded = hit.fraction;
      world.sweep(box, Vector3(0.0, 4.0, 0.5), Vector3(3.0, 0.0, 0.0), hit);
      final square = hit.fraction;

      expect(rounded, greaterThan(square));
      // The face leans at forty-five degrees, so `c` below is its cosine. A box
      // is grown by `c·(radius + halfHeight + radius)` and a capsule by
      // `c·halfHeight + radius`, and the difference is `radius·(2c − 1)` along
      // the normal — fourteen and a half centimetres of shoulder, which is
      // twenty and a half along the sweep and a fifteenth of its three metres.
      const c = 0.70710678;
      expect(
        (rounded - square) * 3.0,
        closeTo(0.35 * (2 * c - 1) / c, 1e-3),
        reason: 'the difference is the corner the box does not round',
      );
    });

    test('and against a wall it is the same body as the box', () {
      // Six axis faces, and a capsule reaches exactly as far along an axis as
      // its bounding box does — so nothing about a level, boxy world changed
      // the day the growth stopped being a box.
      final world = CollisionWorld()
        ..addBox(Vector3(4.0, 0.0, 0.0), Vector3(1.0, 4.0, 8.0));
      world.update();
      final hit = SweepHit();
      final capsule = CollisionCapsule(radius: 0.35, halfHeight: 0.55);
      world.sweep(capsule, Vector3(0.0, 0.0, 0.0), Vector3(6.0, 0.0, 0.0), hit);
      final rounded = hit.fraction;
      world.sweep(
        CollisionBox(capsule.boundsHalfExtents),
        Vector3(0.0, 0.0, 0.0),
        Vector3(6.0, 0.0, 0.0),
        hit,
      );
      expect(rounded, hit.fraction);
    });

    test('and a sphere reaches its radius, whichever way it is asked', () {
      final sphere = CollisionSphere(0.5);
      expect(sphere.supportAlong(0.0, 1.0, 0.0), 0.5);
      expect(sphere.supportAlong(0.70710678, 0.70710678, 0.0), 0.5);
      // Which a box does not: the corner of a cube is further away than its
      // face.
      expect(
        CollisionBox(
          Vector3.all(0.5),
        ).supportAlong(0.70710678, 0.70710678, 0.0),
        closeTo(0.70710678, 1e-6),
      );
    });
  });

  group('a crate on the ground', () {
    test('comes to rest on the surface rather than in it', () {
      final field = ground((column, row) => 0.0);
      final world = worldOf(field);
      final dynamics = Dynamics(world: world);
      final crate = dynamics.add(
        RigidBody(
          world: world,
          shape: CollisionBox(Vector3.all(0.4)),
          position: Vector3(1.53, 3.0, 0.47),
        ),
      );

      for (var step = 0; step < 240; step++) {
        dynamics.step(_dt);
        dynamics.world.update();
      }

      expect(crate.position.y, closeTo(0.4, 0.03));
      // And it stayed where it was dropped: a contact reported on a join
      // between two triangles is a horizontal push, and a horizontal push every
      // step is a crate that walks.
      expect(crate.position.x, closeTo(1.53, 1e-3));
      expect(crate.position.z, closeTo(0.47, 1e-3));
    });

    test('and on a hillside it does not walk off on its own', () {
      final field = ground((column, row) => column * 0.2);
      final world = worldOf(field);
      final dynamics = Dynamics(world: world);
      final crate = dynamics.add(
        RigidBody(
          world: world,
          shape: CollisionBox(Vector3.all(0.4)),
          position: Vector3(2.0, field.heightAt(_origin, 2.0, 0.5) + 1.5, 0.5),
          friction: 0.9,
        ),
      );

      for (var step = 0; step < 300; step++) {
        dynamics.step(_dt);
        dynamics.world.update();
      }

      final under = field.heightAt(_origin, crate.position.x, crate.position.z);
      expect(
        crate.position.y - under,
        closeTo(0.4, 0.12),
        reason: 'the crate ended up ${crate.position.y - under} above the hill',
      );
      // It slides a little downhill, as a crate on a slope should, and not
      // metres of it.
      expect((crate.position.x - 2.0).abs(), lessThan(1.5));
    });
  });
}
