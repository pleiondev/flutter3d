// The core in the browser — P9, phase 12: the WebAssembly module loaded
// through `dart:js_interop`, the same API on it as natively — bodies that
// fall and rest, events, a ray, a snapshot and back, the CPU systems — and
// the shared scene stepped to the very bytes the native library steps it
// to.
//
//     dart test -p chrome test/web_core_test.dart
//     dart test -p chrome -c dart2wasm test/web_core_test.dart
@TestOn('browser')
library;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

import 'scenes/shared_scene.dart';

void main() {
  // The test runner serves the package root one up from the test's page.
  setUpAll(() => loadPhysicsCore(url: '../web/f3d_physics.wasm'));

  test('loads once, and has no GPU', () async {
    expect(physicsCoreLoaded, isTrue);
    await loadPhysicsCore(url: 'nowhere');
    expect(NativeGpu.open(), isNull);
  });

  test('a crate falls onto a floor and rests there', () {
    final world = NativeWorld();
    addTearDown(world.dispose);
    final floor = world.addBody(
      position: Vector3(0.0, -0.5, 0.0),
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    world.setShape(floor, NativeShape.box(Vector3(10.0, 0.5, 10.0)));
    final crate = world.addBody(position: Vector3(0.0, 2.0, 0.0));
    world.setShape(crate, NativeShape.box(Vector3(0.5, 0.5, 0.5)));
    expect(world.bodyCount, 2);
    expect(crate.slot, 1);
    for (var i = 0; i < 240; i++) {
      world.step(1 / 60);
    }
    expect(world.positionOf(crate).y, closeTo(0.5, 0.01));
    final events = world.readEvents();
    expect(
      events.where(
        (e) => e.kind == NativeEventKind.contactBegan && e.body == floor,
      ),
      isNotEmpty,
    );
    final hit = world.rayCast(
      Vector3(0.0, 5.0, 0.0),
      Vector3(0.0, -1.0, 0.0),
      10.0,
    )!;
    expect(hit.body, crate);
    expect(hit.at, closeTo(4.0, 0.01));
    final transforms = world.readTransforms();
    expect(transforms.bodies, <NativeBody>[floor, crate]);
    expect(transforms.transforms[8], closeTo(0.5, 0.01));
  });

  test('a slot used again names a new body, its handle 64 bits', () {
    // A handle's high half is its slot's generation: nought for a slot's
    // first body, so only a slot used again crosses a non-zero one — in and
    // out of the module as two halves, and through memory as a 64-bit word.
    final world = NativeWorld();
    addTearDown(world.dispose);
    final first = world.addBody(position: Vector3(0.0, 1.0, 0.0));
    expect(world.removeBody(first), isTrue);
    final second = world.addBody(position: Vector3(2.0, 1.0, 0.0));
    expect(second.slot, first.slot);
    expect(second.generation, greaterThan(first.generation));
    expect(world.contains(first), isFalse);
    expect(world.contains(second), isTrue);
    expect(world.positionOf(second).x, closeTo(2.0, 1e-6));
    expect(world.readTransforms().bodies, <NativeBody>[second]);
    expect(world.removeBody(first), isFalse);
  });

  test('a snapshot restores to the byte, and a disposed world says so', () {
    final world = NativeWorld();
    final ball = world.addBody(position: Vector3(0.0, 1.0, 0.0));
    world
      ..setShape(ball, const NativeShape.sphere(0.25))
      ..setMaterial(ball, NativeMaterial.rubber());
    world.step(1 / 60);
    final saved = world.snapshot();
    world.step(1 / 60);
    final after = world.snapshot();
    world.restore(saved);
    world.step(1 / 60);
    expect(world.snapshot(), after);
    world.dispose();
    expect(() => world.step(1 / 60), throwsStateError);
  });

  test('particles, debris, cloth and water run on the CPU', () {
    final particles = NativeParticles(4)
      ..emit(<Particle>[
        (position: Vector3.zero(), velocity: Vector3(1.0, 0.0, 0.0), life: 1.0),
      ])
      ..step(ParticleForces(), 1 / 60, steps: 30);
    expect(particles.read()[0], closeTo(0.5, 1e-5));
    particles.dispose();
    final debris = NativeDebris(1)
      ..setStatics(<DebrisStatic>[DebrisPlane(Vector3(0.0, 1.0, 0.0), 0.0)])
      ..add(<DebrisBody>[
        (
          position: Vector3(0.0, 0.5, 0.0),
          velocity: Vector3.zero(),
          radius: 0.1,
          mass: 1.0,
        ),
      ]);
    for (var i = 0; i < 120; i++) {
      debris.step(DebrisSettings(restitution: 0.0), 1 / 60);
    }
    expect(debris.read()!.bodies[1], closeTo(0.1, 0.001));
    debris.dispose();
    final cloth = NativeCloth(
      CoreClothMesh.grid(columns: 6, rows: 6, pinned: <int>{0, 5}),
    );
    for (var i = 0; i < 60; i++) {
      cloth.step(CoreClothSettings(), 1 / 60);
    }
    expect(cloth.read()!.points[1], 0.0);
    cloth.dispose();
    final water = NativeFluid(8, 0.05)
      ..add(<FluidParticle>[
        (position: Vector3(0.0, 1.0, 0.0), velocity: Vector3.zero()),
      ]);
    water.step(
      FluidSettings(
        tankMin: Vector3(-1.0, 0.0, -1.0),
        tankMax: Vector3(1.0, 2.0, 1.0),
      ),
      1 / 60,
    );
    expect(water.read()!.particles[1], lessThan(1.0));
    water.dispose();
  });

  test('a run\'s cloth on the module drapes a ball as the reference does', () {
    ClothMesh sheet() => ClothMesh.grid(cols: 8, rows: 8, height: 0.8);
    final ball = <ClothObstacle>[
      ClothObstacle(CollisionSphere(0.2), Vector3(0.35, 0.5, 0.35)),
    ];
    final reference = sheet();
    final cloth = NativeClothSimulation(sheet());
    for (var i = 0; i < 30; i++) {
      cloth.step(const ClothSettings(), 1 / 60, obstacles: ball);
      stepCloth(reference, const ClothSettings(), 1 / 60, obstacles: ball);
    }
    for (var k = 0; k < reference.positions.length; k++) {
      expect(cloth.mesh.positions[k], closeTo(reference.positions[k], 5e-3));
    }
    cloth.dispose();
  });

  test('the shared scene steps to the native library\'s bytes', () {
    expect(hashOf(sharedSceneSnapshot()), sharedSceneHash);
  });
}
