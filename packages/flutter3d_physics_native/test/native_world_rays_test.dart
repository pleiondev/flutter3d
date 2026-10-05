// A world's rays cast by the core — P9: `CollisionWorld.raycast` with the
// world's `rays` set by a `NativeDynamics(castsRays: true)`, beside the same
// world's own walk. Every ray that does not ask for triggers is the core's:
// the same collider met at the same distance, a mover where it is this
// step, what is ignored and masked away not met; a ray that asks for
// triggers is the world's own.
//
//     dart test test/native_world_rays_test.dart

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  late CollisionWorld world;
  late NativeDynamics dynamics;
  late Collider floor, wall, door, sensor;
  setUp(() {
    world = CollisionWorld();
    floor = world.addBox(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0));
    wall = world.addBox(Vector3(5.0, 1.0, 0.0), Vector3(0.5, 2.0, 4.0));
    door = world.add(
      Collider(
        shape: CollisionBox(Vector3(0.1, 1.0, 1.0)),
        position: Vector3(2.0, 1.0, 10.0),
        kind: ColliderKind.kinematic,
        layer: 1 << 2,
      ),
    );
    sensor = world.add(
      Collider(
        shape: CollisionBox(Vector3(0.5, 0.5, 0.5)),
        position: Vector3(-3.0, 1.0, 0.0),
        kind: ColliderKind.trigger,
      ),
    );
    // Indexed, as a game's step indexes it; the core has not stepped yet.
    world.update();
    dynamics = NativeDynamics(world: world, castsRays: true);
    addTearDown(dynamics.dispose);
  });

  /// [world]'s answer, through the core and through its own walk.
  (RayHit, RayHit) both(
    Vector3 origin,
    Vector3 direction, {
    int mask = Layers.all,
    Collider? ignore,
  }) {
    final core = RayHit();
    world.raycast(origin, direction, 50.0, core, mask: mask, ignore: ignore);
    final rays = world.rays;
    world.rays = null;
    final own = RayHit();
    world.raycast(origin, direction, 50.0, own, mask: mask, ignore: ignore);
    world.rays = rays;
    return (core, own);
  }

  test('the world says who casts its rays', () {
    expect(world.rays, isA<NativeWorldRays>());
    dynamics.dispose();
    expect(world.rays, isNull);
    dynamics = NativeDynamics(world: world);
  });

  test('a shot meets the wall the walk meets, as far', () {
    final (core, own) = both(Vector3(0.0, 1.0, 0.0), Vector3(1.0, 0.0, 0.0));
    expect(core.collider, same(wall));
    expect(own.collider, same(wall));
    expect(core.distance, closeTo(own.distance, 1e-4));
    expect(core.normal.x, closeTo(-1.0, 1e-4));
    expect(core.point.x, closeTo(4.75, 1e-4));
  });

  test('down to the floor, and the floor ignored sees nothing', () {
    final (core, own) = both(Vector3(1.0, 3.0, 1.0), Vector3(0.0, -1.0, 0.0));
    expect(core.collider, same(floor));
    expect(core.distance, closeTo(own.distance, 1e-4));
    final (missed, _) = both(
      Vector3(1.0, 3.0, 1.0),
      Vector3(0.0, -1.0, 0.0),
      ignore: floor,
    );
    expect(missed.hit, isFalse);
  });

  test('a door moved this step is met where it is, and masked away', () {
    door.moveTo(Vector3(2.0, 1.0, 0.0));
    // Indexed for the walk; the core has not stepped since it moved.
    world.reindex();
    final (core, own) = both(Vector3(0.0, 1.0, 0.0), Vector3(1.0, 0.0, 0.0));
    expect(own.collider, same(door));
    expect(core.collider, same(door), reason: 'placed before the ray');
    expect(core.distance, closeTo(own.distance, 1e-4));
    final (past, _) = both(
      Vector3(0.0, 1.0, 0.0),
      Vector3(1.0, 0.0, 0.0),
      mask: Layers.all & ~(1 << 2),
    );
    expect(past.collider, same(wall));
  });

  test('a ray that asks for triggers is the world\'s own', () {
    final hit = RayHit();
    world.raycast(
      Vector3(0.0, 1.0, 0.0),
      Vector3(-1.0, 0.0, 0.0),
      50.0,
      hit,
      includeTriggers: true,
    );
    expect(hit.collider, same(sensor));
    final solid = RayHit();
    world.raycast(Vector3(0.0, 1.0, 0.0), Vector3(-1.0, 0.0, 0.0), 2.0, solid);
    expect(solid.hit, isFalse, reason: 'the core holds no trigger');
  });

  test('rays between steps leave the simulation as it was, to the byte', () {
    // A crate gone to sleep against a door that stands still, and rays cast
    // between the steps or not. Writing the door's place for every query
    // woke the crate against it, and the simulation came to depend on how
    // many rays a frame had cast.
    Uint8List run({required bool rays}) {
      final w = CollisionWorld()
        ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0));
      w.add(
        Collider(
          shape: CollisionBox(Vector3(0.1, 1.0, 1.0)),
          position: Vector3(5.4, 1.0, 0.0),
          kind: ColliderKind.kinematic,
        ),
      );
      final d = NativeDynamics(world: w, castsRays: true);
      addTearDown(d.dispose);
      final crate = d.add(
        RigidBody(
          world: w,
          shape: CollisionBox(Vector3(0.3, 0.3, 0.3)),
          position: Vector3(5.0, 0.3, 0.0),
          mass: 1.0,
        ),
      );
      w.update();
      final hit = RayHit();
      var slept = false;
      for (var i = 0; i < 180; i++) {
        if (rays) {
          for (var k = 0; k < 5; k++) {
            w.raycast(Vector3(4, 3, k * 0.2), Vector3(0, -1, 0), 5.0, hit);
          }
        }
        d.step(1.0 / 60.0);
        w.update();
        slept = slept || d.native.isAsleep(d.handleOf(crate)!);
      }
      expect(slept, isTrue, reason: 'the crate slept against the door');
      return d.snapshot();
    }

    expect(run(rays: true), run(rays: false));
  });

  test('a body that crouches is a crouched one to the core\'s rays', () {
    final w = CollisionWorld()
      ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0));
    final d = NativeDynamics(world: w, castsRays: true, movesCharacters: true);
    addTearDown(d.dispose);
    final body = CharacterController(world: w, position: Vector3(0, 0.9, 0));
    w.update();
    final hit = RayHit();
    bool atHead() =>
        // Between the crouched body's top at 0.9 and the standing one's at
        // 1.8 — and under the standing box's top had it only moved down.
        w.raycast(Vector3(-3.0, 1.2, 0.0), Vector3(1.0, 0.0, 0.0), 6.0, hit);
    expect(atHead(), isTrue, reason: 'standing, its head is met');
    expect(body.tryResize(CollisionBox(Vector3(0.35, 0.45, 0.35))), isTrue);
    // As the step that crouched it ends: a body is made again in the core
    // there, not by a query between steps.
    w.update();
    expect(atHead(), isFalse, reason: 'crouched, the ray passes over');
  });

  test('a ragdoll in the same core is met as nobody\'s, or not at all on a '
      'layer the ray leaves out', () {
    // One bone across the ray's path, made in the core by hand.
    NativeRagdoll bone({int layer = 1}) => NativeRagdoll(
      dynamics.native,
      <RagdollBone>[
        RagdollBone(
          name: 'Body',
          parent: -1,
          head: Vector3(-1.0, 0.5, -1.0),
          tail: Vector3(-1.0, 0.5, 1.0),
          orientation: Quaternion.identity(),
          radius: 0.2,
          mass: 10.0,
        ),
      ],
      dynamics: dynamics,
      layer: layer,
    );
    final hit = RayHit();
    final ragdoll = bone();
    expect(
      world.raycast(Vector3(-4.0, 0.5, 0.0), Vector3(1.0, 0.0, 0.0), 5.0, hit),
      isTrue,
    );
    expect(hit.collider, isNull, reason: 'nobody\'s collider stands for it');
    ragdoll.dispose();
    bone(layer: 1 << 7);
    expect(
      world.raycast(
        Vector3(-4.0, 0.5, 0.0),
        Vector3(1.0, 0.0, 0.0),
        5.0,
        hit,
        mask: Layers.all & ~(1 << 7),
      ),
      isFalse,
    );
  });

  test('a mover moved after the core stepped is in place before anything '
      'asks, so a snapshot is the same with rays between steps or none', () {
    // The lift moves after the core's step, as a game's lifts can, and the
    // step ends in `update`. A ray between steps placed it in the core then;
    // a run without rays placed it on the next step: two runs, two
    // snapshots. Placed in `update`, it is in place in both.
    Uint8List run({required bool rays}) {
      final w = CollisionWorld()
        ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0));
      final lift = w.add(
        Collider(
          shape: CollisionBox(Vector3(1.0, 0.25, 1.0)),
          position: Vector3(5.0, 0.25, 0.0),
          kind: ColliderKind.kinematic,
        ),
      );
      final d = NativeDynamics(world: w, castsRays: true);
      addTearDown(d.dispose);
      w.update();
      final hit = RayHit();
      for (var i = 0; i < 30; i++) {
        d.step(1.0 / 60.0);
        lift.moveTo(lift.position + Vector3(0.0, 1.0 / 60.0, 0.0));
        w
          ..update()
          ..clearKinematicDeltas();
        if (rays) w.raycast(Vector3(5, 5, 0), Vector3(0, -1, 0), 10.0, hit);
      }
      return d.snapshot();
    }

    expect(run(rays: true), run(rays: false));
  });

  test('queries leave the core\'s step as it was: a pile settles to the same '
      'bytes whether rays and casts were asked of it between steps or not', () {
    // A query brings the core's broadphase to where the bodies are, with no
    // motion swept, and notes those it moved; the pairs the next step finds
    // are kept in order of their slots, not of the tree, so that must change
    // nothing the step does — and this holds it to that.
    Uint8List pile({required bool asked}) {
      final world = NativeWorld();
      addTearDown(world.dispose);
      final floor = world.addBody(
        position: Vector3(0.0, -0.5, 0.0),
        type: NativeBodyType.fixed,
        mass: 0.0,
      );
      world.setShape(floor, NativeShape.box(Vector3(20.0, 0.5, 20.0)));
      for (var i = 0; i < 12; i++) {
        final crate = world.addBody(
          position: Vector3((i % 3) * 0.3, 0.5 + i * 0.7, (i % 2) * 0.2),
          mass: 1.0,
        );
        world.setShape(crate, NativeShape.box(Vector3.all(0.25)));
      }
      // Three lifts placed by hand between steps, as the mirror places a
      // game's movers: what a query found out of its leaf and put back.
      final lifts = <NativeBody>[
        for (var k = 0; k < 3; k++)
          world.addBody(
            position: Vector3(-1.0 + k, 0.2, 1.0),
            type: NativeBodyType.fixed,
            mass: 0.0,
          ),
      ];
      for (final lift in lifts) {
        world.setShape(lift, NativeShape.box(Vector3(0.4, 0.1, 0.4)));
      }
      for (var step = 0; step < 240; step++) {
        world.step(1.0 / 60.0);
        for (final (k, lift) in lifts.indexed) {
          world.setPosition(
            lift,
            Vector3(-1.0 + k, 0.2 + 0.4 * ((step + 20 * k) % 60) / 60.0, 1.0),
          );
        }
        if (asked) {
          world.rayCast(Vector3(-3.0, 1.0, 0.0), Vector3(1.0, 0.0, 0.0), 10.0);
          world.moveCharacter(
            shape: NativeShape.box(Vector3(0.3, 0.9, 0.3)),
            position: Vector3(2.0, 1.0, 2.0),
            move: Vector3(-0.1, -0.02, 0.0),
          );
        }
      }
      return world.snapshot();
    }

    expect(pile(asked: true), pile(asked: false));
  });

  test('a save after a mover moved with no step of the core is the same '
      'whether a ray came between or not', () {
    // A runner put back at its checkpoint: moved, and the step ends without
    // the core stepping or the world updating. A ray then put it in place in
    // the core; a save without one held it where it had been.
    Object? saved({required bool ray}) {
      final w = CollisionWorld()
        ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0));
      final d = NativeDynamics(world: w, castsRays: true);
      addTearDown(d.dispose);
      final body = CharacterController(world: w, position: Vector3(0, 0.9, 0));
      w.update();
      d.step(1.0 / 60.0);
      w.update();
      body.teleport(Vector3(10.0, 0.9, 10.0));
      if (ray) w.raycast(Vector3(0, 5, 0), Vector3(0, -1, 0), 10.0, RayHit());
      return d.saveState();
    }

    expect(saved(ray: true), saved(ray: false));
  });

  test('a world staged afresh and restored from a save goes on as the run '
      'that saved it, save for save', () {
    // The core's bodies hold no collider: a fresh world restored took the
    // snapshot's level bodies for nobody's, took them out and stood the
    // level again in other slots — the same physics, other bytes, and a
    // replay that checks its saves parted from the run it recorded.
    ({CollisionWorld w, NativeDynamics d, CharacterController body}) staged() {
      final w = CollisionWorld()
        ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0))
        ..addBox(Vector3(5.5, 1.0, 0.0), Vector3(1.0, 2.0, 4.0))
        ..add(
          Collider(
            shape: CollisionWedge(Vector3(2.0, 1.0, 2.0)),
            position: Vector3(-4.0, 0.5, 0.0),
          ),
        );
      final d = NativeDynamics(
        world: w,
        castsRays: true,
        movesCharacters: true,
      );
      addTearDown(d.dispose);
      final body = CharacterController(world: w, position: Vector3(0, 0.9, 0));
      return (w: w, d: d, body: body);
    }

    void step(
      ({CollisionWorld w, NativeDynamics d, CharacterController body}) s,
    ) {
      s.body.step(1.0 / 60.0, wishDirection: Vector3(1.0, 0.0, 0.3));
      s.d.step(1.0 / 60.0);
      s.w.update();
    }

    final live = staged();
    for (var i = 0; i < 5; i++) {
      step(live);
    }
    final saved = jsonDecode(jsonEncode(live.d.saveState()));
    final body =
        jsonDecode(jsonEncode(live.body.save())) as Map<String, Object?>;
    final again = staged();
    // The colliders first, as a simulation restores them: the core's bodies
    // are matched to them by where they stand.
    again.body.restore(body);
    again.d.restoreState(saved);
    expect(
      jsonEncode(again.d.saveState()),
      jsonEncode(live.d.saveState()),
      reason: 'as restored',
    );
    for (var i = 0; i < 60; i++) {
      step(live);
      step(again);
      expect(
        jsonEncode(again.d.saveState()),
        jsonEncode(live.d.saveState()),
        reason: 'step $i',
      );
    }
  });
}
