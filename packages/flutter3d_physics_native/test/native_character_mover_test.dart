// Characters moved by the core — P9: `CharacterController` with the world's
// `characterMover` set by a `NativeDynamics(movesCharacters: true)`, beside
// the same controller on its own sweeps, the reference. What a step decides
// stays the controller's; where it ends is the core's capsule's. They agree
// to centimetres on a walk, a wall, a step, a jump and a lift, and where they
// part is said: the round of the capsule.
//
//     dart test test/native_character_mover_test.dart

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

/// The yard twice: once moved by the core, once by the controller's own
/// sweeps.
({CharacterController core, CharacterController dart, NativeDynamics dynamics})
_pair({Vector3? at}) {
  final world = _yard();
  final dynamics = NativeDynamics(world: world, movesCharacters: true);
  addTearDown(dynamics.dispose);
  final start = at ?? Vector3(0.0, 0.9, 0.0);
  return (
    core: CharacterController(world: world, position: start),
    dart: CharacterController(world: _yard(), position: start),
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
    // Reported is the rise not travelled through, for a renderer to smooth,
    // on the frames a step lifted the body, as much as it rose on them. The
    // box was lifted the whole riser at once; the capsule's round foot may
    // ride the riser's edge for part of it, as up a slope, and is lifted
    // the rest — the frames add up to no more than the riser.
    expect(lifts, isNotEmpty, reason: 'a step was taken');
    for (final (rose, said) in lifts) {
      expect(said, closeTo(rose, 1e-4));
    }
    expect(
      lifts.fold<double>(0.0, (sum, l) => sum + l.$2),
      lessThanOrEqualTo(0.2 + 0.01),
    );
  });

  test('a jump leaves the floor and lands as the reference does', () {
    final p = _pair();
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
    // One's capsule, 0.35 round, against the other's box, 0.35 half wide,
    // with the core's centimetre of skin between, less a millimetre.
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
}
