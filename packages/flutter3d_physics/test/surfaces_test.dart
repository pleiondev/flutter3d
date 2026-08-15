/// What a body may pass through, what is under its feet, and what drags it.
///
///     dart test test/surfaces_test.dart
///
/// Four changes, and every one of them closes an asymmetry rather than adding a
/// feature: every collider in the world already chose what it collided with
/// through `layer` and `mask`, and the character was the one body that collided
/// with everything solid whether it wanted to or not; the ground probe recorded
/// what it stood on only when that thing could move; a surface could carry a
/// passenger only by moving itself; and the numbers that decide how a body
/// feels could not be changed once it existed.
///
/// Between them they are one-way platforms, drop-through floors, ice, mud,
/// conveyors, water and footstep sounds — none of which the engine knows the
/// name of.
library;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

/// A bit nothing else in these tests uses. A *game* names its layers; this is
/// the engine's test, so the number is bare on purpose.
const int _thin = 1 << 6;

CollisionWorld _room({bool withFloor = true}) {
  final world = CollisionWorld();
  if (withFloor) {
    world.add(
      Collider(
        shape: CollisionBox(Vector3(20.0, 0.5, 20.0)),
        position: Vector3(0.0, -0.5, 0.0),
      ),
    );
  }
  return world;
}

/// A thin slab on the [_thin] layer, four metres up.
Collider _platform(CollisionWorld world, {double y = 4.0}) => world.add(
      Collider(
        shape: CollisionBox(Vector3(3.0, 0.1, 3.0)),
        position: Vector3(0.0, y, 0.0),
        layer: _thin,
      ),
    );

CharacterController _body(CollisionWorld world, {double y = 0.9}) =>
    CharacterController(world: world, position: Vector3(0.0, y, 0.0));

void _run(CharacterController body, int steps, {Vector3? wish}) {
  final direction = wish ?? Vector3.zero();
  for (var i = 0; i < steps; i++) {
    body.step(_dt, wishDirection: direction);
    body.world.reindex();
  }
}

void main() {
  group('what counts as solid', () {
    test('a body rises through a platform its filter refuses', () {
      // Mutation: drop `allow: solidFilter` from the sweep in `_slide`. The
      // body stops under the slab and this fails at the first assertion.
      final world = _room();
      _platform(world);
      final body = _body(world)
        ..solidFilter = (Collider other, Vector3 normal) =>
            other.layer & _thin == 0 || normal.y > 0.5;

      // Twenty metres a second, which reaches nine: the platform's underside
      // is at 3.9 and the first draft of this jumped to 3.9 exactly and proved
      // that gravity works.
      body.velocity.y = 20.0;
      var highest = body.position.y;
      for (var i = 0; i < 60; i++) {
        _run(body, 1);
        if (body.position.y > highest) highest = body.position.y;
      }

      expect(highest, greaterThan(5.0),
          reason: 'the platform stopped a body that should have passed it');
    });

    test('and lands on the same platform coming down', () {
      // The other half, and the reason the filter takes a normal rather than a
      // layer: one collider whose top face counts and whose other five do not.
      //
      // Mutation: make the filter `other.layer & _thin == 0` — a mask, in other
      // words. The body falls straight through and never lands.
      final world = _room();
      _platform(world);
      final body = _body(world, y: 8.0)
        ..solidFilter = (Collider other, Vector3 normal) =>
            other.layer & _thin == 0 || normal.y > 0.5;

      _run(body, 120);

      expect(body.isGrounded, isTrue, reason: 'it fell through its own floor');
      expect(body.position.y, closeTo(5.0, 0.2));
    });

    test('and is not caught by the platform edge on the way past', () {
      // What a mask cannot do, and the reason this is a predicate. A body
      // running into the *side* of a one-way platform should feel nothing; with
      // a mask the side is as solid as the top, and a player sprinting along a
      // gantry stops dead in mid-air on an invisible lip.
      //
      // Mutation: return `true` for a normal with no vertical component.
      final world = _room();
      world.add(
        Collider(
          shape: CollisionBox(Vector3(3.0, 1.5, 3.0)),
          position: Vector3(0.0, 3.0, 0.0),
          layer: _thin,
        ),
      );
      final body = _body(world, y: 3.0)
        ..solidFilter = (Collider other, Vector3 normal) =>
            other.layer & _thin == 0 || normal.y > 0.5;
      body.position.setValues(-6.0, 3.0, 0.0);

      _run(body, 120, wish: Vector3(1.0, 0.0, 0.0));

      expect(body.position.x, greaterThan(3.0),
          reason: 'it hit the side of a platform it was passing through');
    });

    test('a body inside a platform it ignores is not shoved out of it', () {
      // The four-of-five mistake: thread the filter into the three sweeps and
      // forget `depenetrate`, and a body that rose into a one-way platform is
      // ejected sideways out of it on the very next step. It looks like
      // teleporting, and nothing in the sweep tests can see it.
      //
      // Mutation: drop `allow: solidFilter` from the `depenetrate` call in
      // `_resolveOverlap`.
      final world = _room();
      world.add(
        Collider(
          shape: CollisionBox(Vector3(3.0, 0.6, 3.0)),
          position: Vector3(0.0, 4.0, 0.0),
          layer: _thin,
        ),
      );
      final body = _body(world, y: 4.0)
        ..solidFilter = (Collider other, Vector3 normal) =>
            other.layer & _thin == 0;
      body.velocity.y = 0.0;

      final startedAt = body.position.clone();
      _run(body, 3);

      expect((body.position.x - startedAt.x).abs(), lessThan(0.05),
          reason: 'it was pushed sideways out of a body it ignores');
      expect((body.position.z - startedAt.z).abs(), lessThan(0.05));
    });

    test('the ground probe asks the filter too', () {
      // Mutation: drop `allow: solidFilter` from the sweep in `_probeGround`.
      // The body reports itself standing on a floor it is falling through.
      final world = _room();
      final body = _body(world)
        ..solidFilter = (Collider other, Vector3 normal) => false;

      _run(body, 5);

      expect(body.isGrounded, isFalse);
      expect(body.ground, isNull);
    });

    test('the filter is this body only, and not a hole in the world', () {
      // A phase state must not make the phasing body invisible: monsters still
      // see it, triggers still fire, and another body still collides with what
      // this one ignores.
      //
      // Mutation: implement the filter by clearing bits on the collider's mask
      // instead — the other body starts falling through the platform too.
      final world = _room();
      _platform(world, y: 2.0);
      final ghost = _body(world, y: 6.0)
        ..solidFilter = (Collider other, Vector3 normal) =>
            other.layer & _thin == 0;
      final solid = CharacterController(
        world: world,
        position: Vector3(0.0, 6.0, 0.0),
      );

      for (var i = 0; i < 120; i++) {
        ghost.step(_dt, wishDirection: Vector3.zero());
        solid.step(_dt, wishDirection: Vector3.zero());
        world.reindex();
      }

      expect(ghost.position.y, closeTo(0.9, 0.2), reason: 'it fell to the floor');
      expect(solid.position.y, closeTo(2.9, 0.2), reason: 'it stood on the slab');
    });
  });

  group('what is underfoot', () {
    test('standing on a static brush names the brush', () {
      // Mutation: put the `kind == ColliderKind.kinematic` test back on the
      // store in `_probeGround`. `ground` goes null on every ordinary floor and
      // ice, mud, conveyors and footstep sounds all become unanswerable.
      final world = _room();
      final floor = world.colliderCount;
      final body = _body(world);
      _run(body, 10);

      expect(floor, 1);
      expect(body.isGrounded, isTrue);
      expect(body.ground, isNotNull, reason: 'a floor is a thing to stand on');
      expect(body.ground!.kind, ColliderKind.static);
    });

    test('but a static brush is still not something that carries you', () {
      // The blast radius of the change above, guarded: a lift asks whether
      // anybody is riding it, and every brush in the level must not answer yes.
      //
      // Mutation: `Collider? get groundBody => ground`.
      final world = _room();
      final body = _body(world);
      _run(body, 10);

      expect(body.ground, isNotNull);
      expect(body.groundBody, isNull);
    });

    test('a kinematic body underfoot is both', () {
      final world = _room(withFloor: false);
      world.add(
        Collider(
          shape: CollisionBox(Vector3(4.0, 0.5, 4.0)),
          position: Vector3(0.0, -0.5, 0.0),
          kind: ColliderKind.kinematic,
        ),
      );
      final body = _body(world);
      _run(body, 10);

      expect(body.ground, isNotNull);
      expect(body.groundBody, same(body.ground));
    });
  });

  group('what drags you', () {
    test('a conveyor carries a body that asks for nothing', () {
      // Mutation: drop the `surfaceVelocity` term from `_carryWithGround`. The
      // body stands still for ever, which is what every belt in the engine did.
      final world = CollisionWorld();
      world.add(
        Collider(
          shape: CollisionBox(Vector3(20.0, 0.5, 20.0)),
          position: Vector3(0.0, -0.5, 0.0),
        )..surfaceVelocity.setValues(2.0, 0.0, 0.0),
      );
      final body = _body(world);

      _run(body, 60);

      // Two metres a second for one second, less a skin.
      expect(body.position.x, closeTo(2.0, 0.05));
    });

    test('and the second is not sixty times the first', () {
      // Mutation: forget the `* dt` — a belt that drags at two metres a second
      // moves a hundred and twenty. The tolerance above would catch it; this
      // says which mistake it was.
      final world = CollisionWorld();
      world.add(
        Collider(
          shape: CollisionBox(Vector3(200.0, 0.5, 200.0)),
          position: Vector3(0.0, -0.5, 0.0),
        )..surfaceVelocity.setValues(2.0, 0.0, 0.0),
      );
      final body = _body(world);

      // Settled first: a body is not standing on anything until its own ground
      // probe has run, and nothing carries a body that is still in the air.
      _run(body, 10);
      final restingAt = body.position.x;
      _run(body, 1);

      expect(body.position.x - restingAt, closeTo(2.0 * _dt, 0.005));
    });

    test('jumping off a conveyor goes straight up', () {
      // A decision, stated so it is not rediscovered as a bug: the drag is a
      // position, not a velocity, so the belt's motion does not follow you into
      // the air. That is what a platformer wants of a belt and arguable of a
      // travelator.
      //
      // Mutation: apply the drag as `velocity.x +=`. The jump arcs away.
      final world = CollisionWorld();
      world.add(
        Collider(
          shape: CollisionBox(Vector3(20.0, 0.5, 20.0)),
          position: Vector3(0.0, -0.5, 0.0),
        )..surfaceVelocity.setValues(4.0, 0.0, 0.0),
      );
      final body = _body(world);
      _run(body, 10);

      final tookOffAt = body.position.x;
      body.requestJump();
      _run(body, 20);

      expect(body.position.y, greaterThan(1.5), reason: 'it did jump');
      // One step's worth of drag, and no more: carrying happens at the top of
      // the step and the jump later in the same one, so the step a jump starts
      // on is still a step spent standing on the belt. Four metres a second for
      // one sixtieth is under seven centimetres; a velocity-add would be
      // travelling at four metres a second and still accelerating.
      expect(body.position.x - tookOffAt, lessThan(0.1),
          reason: 'the belt followed it into the air');
    });

    test('a body in the air above a conveyor is not dragged', () {
      // Mutation: apply `surfaceVelocity` from `_resolveOverlap` rather than
      // from what the ground probe found.
      final world = CollisionWorld();
      world.add(
        Collider(
          shape: CollisionBox(Vector3(20.0, 0.5, 20.0)),
          position: Vector3(0.0, -0.5, 0.0),
        )..surfaceVelocity.setValues(5.0, 0.0, 0.0),
      );
      final body = _body(world, y: 6.0);

      _run(body, 10);

      expect(body.isGrounded, isFalse);
      expect(body.position.x.abs(), lessThan(0.01));
    });
  });

  group('how it feels', () {
    test('a low-friction tuning takes longer to stop', () {
      // Mutation: make `tuning` a getter returning the value the constructor
      // was given. Ice becomes stone and the two counts come out equal.
      int stepsToRest(MovementTuning tuning) {
        final world = _room();
        final body = _body(world)..tuning = tuning;
        _run(body, 60, wish: Vector3(1.0, 0.0, 0.0));
        var steps = 0;
        while (body.velocity.x.abs() > 0.05 && steps < 600) {
          body.step(_dt, wishDirection: Vector3.zero());
          world.reindex();
          steps++;
        }
        return steps;
      }

      final onStone = stepsToRest(const MovementTuning());
      final onIce = stepsToRest(const MovementTuning(groundFriction: 4.0));

      expect(onIce, greaterThan(onStone * 3),
          reason: 'ice stopped the body about as fast as stone did');
    });

    test('a tuning swapped between steps takes effect on the next one', () {
      // Mutation: cache any tuning value in a field at construction. The step
      // after the swap still falls at the old gravity.
      final world = _room(withFloor: false);
      final body = _body(world, y: 40.0);
      _run(body, 1);
      final slow = body.velocity.y;

      body.tuning = const MovementTuning(gravity: 96.0);
      _run(body, 1);
      final fast = body.velocity.y - slow;

      expect(fast, lessThan(slow * 3),
          reason: 'the new gravity did not arrive (velocity is negative, so '
              'a bigger fall is a smaller number)');
    });
  });
}
