// Characters moved by the core — P9: `CharacterController` with the world's
// `characterMover` set by a `NativeDynamics(movesCharacters: true)`, beside
// the same controller on its own sweeps, the reference. What a step decides
// stays the controller's; where it ends is the core's, which moves the same
// box the reference sweeps. They agree to centimetres on a walk, a wall, a
// step, a jump through a platform and a lift.
//
//     dart test test/native_character_mover_test.dart

import 'dart:math' as math;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const double _dt = 1.0 / 60.0;

/// A floor, a wall across +x at 6, and a step 0.2 high from z = 3 on.
CollisionWorld _yard() => CollisionWorld()
  ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0))
  ..addBox(Vector3(6.5, 1.0, 0.0), Vector3(1.0, 2.0, 2.0))
  ..addBox(Vector3(0.0, 0.1, 6.0), Vector3(2.0, 0.2, 6.0));

/// A game's gravity, 24 m/s², for the jumps: an 8 m/s jump rises 1.33 m
/// and is down in two thirds of a second. A controller falls by its world's
/// gravity otherwise, and under the standard 9.81 that jump rises 3.3 m and
/// is in the air for over a second and a half.
const MovementSettings _gameGravity = MovementSettings(gravity: 24.0);

/// The yard twice: once moved by the core, once by the controller's own
/// sweeps, each moving as [tuning] says.
({CharacterController core, CharacterController dart, NativeDynamics dynamics})
_pair({Vector3? at, MovementSettings tuning = const MovementSettings()}) {
  final world = _yard();
  final dynamics = NativeDynamics(world: world, movesCharacters: true);
  addTearDown(dynamics.dispose);
  final start = at ?? Vector3(0.0, 0.9, 0.0);
  return (
    core: CharacterController(world: world, position: start, tuning: tuning),
    dart: CharacterController(world: _yard(), position: start, tuning: tuning),
    dynamics: dynamics,
  );
}

/// Both stepped [steps] times towards [wish], [and] asked before each step.
void _walk(
  ({
    CharacterController core,
    CharacterController dart,
    NativeDynamics dynamics,
  })
  pair,
  int steps,
  Vector3 wish, {
  void Function(int step, CharacterController body)? and,
}) {
  for (var i = 0; i < steps; i++) {
    for (final body in <CharacterController>[pair.core, pair.dart]) {
      and?.call(i, body);
      body.step(_dt, wishDirection: wish);
    }
    pair.dynamics.step(_dt);
    pair.core.world.clearKinematicDeltas();
    pair.dart.world.clearKinematicDeltas();
  }
}

void main() {
  test('the world says who moves its characters', () {
    final world = _yard();
    final dynamics = NativeDynamics(world: world, movesCharacters: true);
    expect(world.characterMover, isA<NativeCharacterMover>());
    dynamics.dispose();
    expect(world.characterMover, isNull, reason: 'let go with the core');
    final plain = NativeDynamics(world: _yard());
    expect(plain.world.characterMover, isNull, reason: 'asked for');
    plain.dispose();
  });

  test('it stands on the floor, named as the floor\'s collider', () {
    final p = _pair();
    _walk(p, 30, Vector3.zero());
    expect(p.core.isGrounded, isTrue);
    expect(p.core.position.y, closeTo(p.dart.position.y, 0.01));
    expect(p.core.ground, same(p.core.world.statics.first));
    expect(p.core.groundNormal.y, closeTo(1.0, 1e-4));
  });

  test('it walks as the reference walks, and stops at the wall', () {
    final p = _pair();
    _walk(p, 60, Vector3(1.0, 0.0, 0.0));
    expect(p.core.position.x, closeTo(p.dart.position.x, 0.02));
    _walk(p, 120, Vector3(1.0, 0.0, 0.0));
    // The wall's face at 6, less the body's half width.
    expect(p.core.position.x, closeTo(6.0 - 0.35, 0.02));
    expect(p.dart.position.x, closeTo(6.0 - 0.35, 0.02));
    // The speed into the wall taken out by the core, as the reference's
    // slide takes it out: nothing left of it.
    expect(p.core.velocity.x.abs(), lessThan(1e-4), reason: 'into the wall');
  });

  test('it climbs the step, and says how far', () {
    final p = _pair();
    // Each step frame's rise, and what the body said it was lifted by.
    final lifts = <(double, double)>[];
    for (var i = 0; i < 90; i++) {
      final before = p.core.position.y;
      for (final body in <CharacterController>[p.core, p.dart]) {
        body.step(_dt, wishDirection: Vector3(0.0, 0.0, 1.0));
      }
      if (p.core.steppedUp > 0.0) {
        lifts.add((p.core.position.y - before, p.core.steppedUp));
      }
      p.dynamics.step(_dt);
    }
    expect(p.core.position.y, closeTo(0.9 + 0.2, 0.02), reason: 'on the step');
    expect(p.dart.position.y, closeTo(0.9 + 0.2, 0.02));
    expect(p.core.isGrounded, isTrue);
    // Reported is the rise not travelled through, for a renderer to smooth:
    // the box lifted the whole riser at once, in one step, as the reference
    // lifts it, and said so.
    expect(lifts, hasLength(1), reason: 'one step, the riser');
    expect(lifts.single.$1, closeTo(0.2, 0.01), reason: 'rose by the riser');
    expect(lifts.single.$2, closeTo(lifts.single.$1, 1e-4));
  });

  test('a jump leaves the floor and lands as the reference does', () {
    final p = _pair(tuning: _gameGravity);
    _walk(p, 20, Vector3.zero());
    final heights = <(double, double)>[];
    for (var i = 0; i < 90; i++) {
      if (i == 0) {
        p.core.requestJump();
        p.dart.requestJump();
      }
      p.core.step(_dt, wishDirection: Vector3.zero());
      p.dart.step(_dt, wishDirection: Vector3.zero());
      p.dynamics.step(_dt);
      heights.add((p.core.position.y, p.dart.position.y));
      if (i == 5) expect(p.core.isGrounded, isFalse, reason: 'in the air');
    }
    final apex = heights.map((h) => h.$1).reduce((a, b) => a > b ? a : b);
    final apexRef = heights.map((h) => h.$2).reduce((a, b) => a > b ? a : b);
    expect(apex, greaterThan(1.5));
    expect(apex, closeTo(apexRef, 0.02));
    expect(p.core.isGrounded, isTrue, reason: 'landed');
    expect(p.core.position.y, closeTo(0.9, 0.02));
  });

  test('a face too steep to stand on is a wall walked into, as on the '
      'reference', () {
    // Sixty degrees and a bit, uphill along +z: walked into, the body stays
    // on the floor on both — the core always met it as the upright wall its
    // horizontal half is.
    CollisionWorld steep() => CollisionWorld()
      ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0))
      ..add(
        Collider(
          shape: CollisionWedge(
            Vector3(3.0, 3.5, 2.0),
            uphill: WedgeUphill.positiveZ,
          ),
          position: Vector3(0.0, 3.5, 2.0),
        ),
      );
    final world = steep();
    final dynamics = NativeDynamics(world: world, movesCharacters: true);
    addTearDown(dynamics.dispose);
    final core = CharacterController(
      world: world,
      position: Vector3(0.0, 0.9, -3.0),
    );
    final dart = CharacterController(
      world: steep()..update(),
      position: Vector3(0.0, 0.9, -3.0),
    );
    world.update();
    for (var i = 0; i < 150; i++) {
      for (final body in <CharacterController>[core, dart]) {
        body.step(_dt, wishDirection: Vector3(0.0, 0.0, 1.0));
      }
      dynamics.step(_dt);
    }
    expect(core.position.y, closeTo(0.9, 0.05), reason: 'not up the face');
    expect(core.position.y, closeTo(dart.position.y, 0.02));
    expect(core.position.z, closeTo(dart.position.z, 0.05));
  });

  test('dropped onto a face too steep to stand on, it slides down it as the '
      'reference does', () {
    // Falling, a steep face is the slope it is, not a wall: the reference
    // slides down it to the floor. Mutation: in `slide` in f3d_query.c,
    // flatten a steep face's normal whatever the move — the face taken for
    // a wall, the core's body falls straight past it instead of sliding off
    // its foot, and lands 13 cm short of where the reference does.
    CollisionWorld steep() => CollisionWorld()
      ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0))
      ..add(
        Collider(
          shape: CollisionWedge(
            Vector3(3.0, 3.5, 2.0),
            uphill: WedgeUphill.positiveZ,
          ),
          position: Vector3(0.0, 3.5, 2.0),
        ),
      );
    final world = steep();
    final dynamics = NativeDynamics(world: world, movesCharacters: true);
    addTearDown(dynamics.dispose);
    // Over the middle of the face, a metre and a half up it.
    final start = Vector3(0.0, 4.0, 2.0);
    final core = CharacterController(world: world, position: start);
    final dart = CharacterController(world: steep()..update(), position: start);
    world.update();
    var lowest = (double.infinity, double.infinity);
    for (var i = 0; i < 180; i++) {
      for (final body in <CharacterController>[core, dart]) {
        body.step(_dt, wishDirection: Vector3.zero());
      }
      dynamics.step(_dt);
      lowest = (
        math.min(lowest.$1, core.position.y),
        math.min(lowest.$2, dart.position.y),
      );
    }
    expect(dart.position.y, closeTo(0.9, 0.05), reason: 'the reference');
    expect(core.position.y, closeTo(0.9, 0.05), reason: 'down on the floor');
    expect(core.position.z, closeTo(dart.position.z, 0.1));
    expect(lowest.$1, greaterThan(0.85), reason: 'not through the floor');
  });

  test('a platform closing on it does not push it through the floor, as on '
      'the reference', () {
    // A kinematic slab coming down onto a body on the floor: the body stays
    // on the floor, never pushed into it, until the slab's middle passes the
    // body's and out of the slab is up, onto its top — on the core as on the
    // reference, which lets the floor win against the slab. The core gets
    // there by pushing out of the deepest overlap, four times over, which
    // ends on the floor's push. Mutation: leave fixed bodies out of
    // `push_out` in f3d_query.c — the body stays on the floor inside the
    // slab, 0.92 where the reference stands on top at 1.43.
    CollisionWorld room() =>
        CollisionWorld()
          ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0));
    Collider slab(CollisionWorld world) => world.add(
      Collider(
        shape: CollisionBox(Vector3(3.0, 0.5, 3.0)),
        position: Vector3(0.0, 6.0, 0.0),
        kind: ColliderKind.kinematic,
      ),
    );
    final world = room();
    final ceiling = slab(world);
    final dynamics = NativeDynamics(world: world, movesCharacters: true);
    addTearDown(dynamics.dispose);
    final reference = room();
    final ceilingRef = slab(reference);
    reference.update();
    world.update();
    final core = CharacterController(
      world: world,
      position: Vector3(0.0, 0.9, 0.0),
    );
    final dart = CharacterController(
      world: reference,
      position: Vector3(0.0, 0.9, 0.0),
    );
    var lowest = (double.infinity, double.infinity);
    for (var i = 0; i < 200; i++) {
      for (final c in <Collider>[ceiling, ceilingRef]) {
        c.moveTo(c.position + Vector3(0.0, -0.03, 0.0));
      }
      world.reindex();
      for (final body in <CharacterController>[core, dart]) {
        body.step(_dt, wishDirection: Vector3.zero());
      }
      dynamics.step(_dt);
      world
        ..update()
        ..clearKinematicDeltas();
      reference
        ..update()
        ..clearKinematicDeltas();
      lowest = (
        math.min(lowest.$1, core.position.y),
        math.min(lowest.$2, dart.position.y),
      );
    }
    expect(lowest.$2, greaterThan(0.0), reason: 'the reference');
    expect(lowest.$1, greaterThan(0.85), reason: 'never into the floor');
    // Once the slab's middle is below the body's, out of it is up, onto its
    // top, on both.
    expect(core.position.y, closeTo(dart.position.y, 0.05));
  });

  test('a lift carries it up, standing on the lift\'s collider', () {
    final world = CollisionWorld()
      ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0));
    final lift = world.add(
      Collider(
        shape: CollisionBox(Vector3(1.0, 0.25, 1.0)),
        position: Vector3(5.0, 0.25, 0.0),
        kind: ColliderKind.kinematic,
      ),
    );
    final dynamics = NativeDynamics(world: world, movesCharacters: true);
    addTearDown(dynamics.dispose);
    final body = CharacterController(
      world: world,
      position: Vector3(5.0, 1.4, 0.0),
    );
    for (var i = 0; i < 30; i++) {
      body.step(_dt, wishDirection: Vector3.zero());
      dynamics.step(_dt);
      world.clearKinematicDeltas();
    }
    expect(body.ground, same(lift));
    for (var i = 0; i < 60; i++) {
      lift.moveTo(lift.position + Vector3(0.0, 1.0 / 60.0, 0.0));
      world.reindex();
      body.step(_dt, wishDirection: Vector3.zero());
      dynamics.step(_dt);
      world.clearKinematicDeltas();
    }
    expect(body.position.y, closeTo(1.4 + 1.0, 0.03));
    expect(body.isGrounded, isTrue);
  });

  test('a body that asks about each contact keeps its own sweeps', () {
    final world = _yard();
    final dynamics = NativeDynamics(world: world, movesCharacters: true);
    addTearDown(dynamics.dispose);
    // Nothing is solid to it: through the floor it falls, as only its own
    // sweeps can make it — the core would stand it on the floor.
    final ghost = CharacterController(
      world: world,
      position: Vector3(0.0, 0.9, 0.0),
    )..solidFilter = (_) => false;
    for (var i = 0; i < 30; i++) {
      ghost.step(_dt, wishDirection: Vector3.zero());
      dynamics.step(_dt);
    }
    expect(ghost.position.y, lessThan(0.0));
  });

  test('two characters meet each other, not pass through', () {
    final world = _yard();
    final dynamics = NativeDynamics(world: world, movesCharacters: true);
    addTearDown(dynamics.dispose);
    final a = CharacterController(world: world, position: Vector3(0, 0.9, 0));
    final b = CharacterController(world: world, position: Vector3(3, 0.9, 0));
    for (var i = 0; i < 120; i++) {
      a.step(_dt, wishDirection: Vector3(1.0, 0.0, 0.0));
      b.step(_dt, wishDirection: Vector3(-1.0, 0.0, 0.0));
      dynamics.step(_dt);
      world.update();
    }
    // Two boxes 0.35 half wide, with the core's centimetre of skin between,
    // less a millimetre.
    expect(b.position.x - a.position.x, greaterThan(0.70 + 0.01 - 0.001));
  });

  test('it jumps up through a platform solid from above and lands on it, as '
      'the reference does', () {
    // Layer 1 << 3 solid only from above, low enough that the jump clears
    // it: the body's apex puts its feet above the platform's top. On the
    // way up the core starts inside the platform for a few frames — and
    // once stood on what it was inside of, which cut the jump short there.
    //
    // **A jump that does not clear it is not asked here, and the two
    // differ:** the core falls back down through, as a body inside a
    // platform solid from above does; the reference's box is pushed up out
    // of it onto the top, its overlap resolved upwards once it falls.
    CollisionWorld platformed() => CollisionWorld()
      ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0))
      ..add(
        Collider(
          shape: CollisionBox(Vector3(2.0, 0.1, 2.0)),
          position: Vector3(0.0, 1.2, 0.0),
          layer: 1 << 3,
        ),
      );
    final world = platformed();
    final dynamics = NativeDynamics(world: world, movesCharacters: true);
    addTearDown(dynamics.dispose);
    final core = CharacterController(world: world, position: Vector3(0, 0.9, 0))
      ..fromAboveLayers = 1 << 3;
    final dart = CharacterController(
      world: platformed()..update(),
      position: Vector3(0, 0.9, 0),
    )..fromAboveLayers = 1 << 3;
    world.update();
    var top = (0.0, 0.0);
    for (var i = 0; i < 150; i++) {
      for (final body in <CharacterController>[core, dart]) {
        if (i == 10) body.requestJump();
        body.step(_dt, wishDirection: Vector3.zero());
      }
      dynamics.step(_dt);
      top = (
        core.position.y > top.$1 ? core.position.y : top.$1,
        dart.position.y > top.$2 ? dart.position.y : top.$2,
      );
    }
    expect(top.$1, closeTo(top.$2, 0.02), reason: 'the jump not cut short');
    expect(top.$1 - 0.9, greaterThan(1.3), reason: 'feet over the platform');
    expect(core.position.y, closeTo(1.3 + 0.9, 0.02), reason: 'landed on it');
    expect(dart.position.y, closeTo(1.3 + 0.9, 0.02));
  });

  test('a jump that does not clear a platform solid from above falls back '
      'through it, on the core as on the reference', () {
    // The platform's top at 2.3, the jump's apex putting the feet at about
    // 1.4: inside it at the top of the jump, the body falls back down
    // through it to the floor. The reference's box was pushed up out of
    // the overlap onto the top once it began to fall.
    CollisionWorld platformed() => CollisionWorld()
      ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0))
      ..add(
        Collider(
          shape: CollisionBox(Vector3(2.0, 0.1, 2.0)),
          position: Vector3(0.0, 2.2, 0.0),
          layer: 1 << 3,
        ),
      );
    final world = platformed();
    final dynamics = NativeDynamics(world: world, movesCharacters: true);
    addTearDown(dynamics.dispose);
    final core = CharacterController(
      world: world,
      position: Vector3(0, 0.9, 0),
      tuning: _gameGravity,
    )..fromAboveLayers = 1 << 3;
    final dart = CharacterController(
      world: platformed()..update(),
      position: Vector3(0, 0.9, 0),
      tuning: _gameGravity,
    )..fromAboveLayers = 1 << 3;
    world.update();
    var top = (0.0, 0.0);
    for (var i = 0; i < 150; i++) {
      for (final body in <CharacterController>[core, dart]) {
        if (i == 10) body.requestJump();
        body.step(_dt, wishDirection: Vector3.zero());
      }
      dynamics.step(_dt);
      top = (
        core.position.y > top.$1 ? core.position.y : top.$1,
        dart.position.y > top.$2 ? dart.position.y : top.$2,
      );
    }
    expect(top.$1 - 0.9, lessThan(2.3), reason: 'the feet never cleared it');
    expect(top.$1, closeTo(top.$2, 0.02));
    expect(core.position.y, closeTo(0.9, 0.02), reason: 'back on the floor');
    expect(dart.position.y, closeTo(0.9, 0.02), reason: 'back on the floor');
  });

  test('restored from a snapshot taken before anything stood, it still '
      'stands on the floor', () {
    // The snapshot holds no standing bodies; the mirror had stood the world
    // before the restore and counted it done, so a character moved before
    // the next step met no floor.
    final world = _yard();
    final dynamics = NativeDynamics(world: world, movesCharacters: true);
    addTearDown(dynamics.dispose);
    final body = CharacterController(
      world: world,
      position: Vector3(0, 0.9, 0),
    );
    world.update();
    final start = dynamics.snapshot();
    for (var i = 0; i < 5; i++) {
      body.step(_dt, wishDirection: Vector3.zero());
      dynamics.step(_dt);
    }
    dynamics.restore(start);
    body.teleport(Vector3(0.0, 0.9, 0.0));
    body.step(_dt, wishDirection: Vector3.zero());
    expect(body.position.y, closeTo(0.9, 0.02), reason: 'not through it');
    expect(body.isGrounded, isTrue);
  });
}
