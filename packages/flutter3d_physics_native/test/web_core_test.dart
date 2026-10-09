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
    expect(NativeGpu.open, throwsA(isA<GpuUnavailable>()));
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
      ..emit(<NativeParticle>[
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

  test('a run\'s liquid on the module pours as the reference does', () {
    // A narrow tube tipped over a wide one: waves, a stream and what it
    // splashes, on the module's f3d_liquid_* and on the reference.
    double pour(FluidSolver solver) {
      RevolvedVessel tube(double r) =>
          RevolvedVessel([Vector2(0, 0), Vector2(r, 0), Vector2(r, 0.1)]);
      final world = FluidWorld(gravity: Vector3(0, -9.81, 0), solver: solver);
      final source = LiquidBody(
        shape: tube(0.008),
        medium: FluidMedium.water,
        volume: 1.4e-5,
        modes: 4,
        wallThickness: 0.0008,
      );
      final target = LiquidBody(
        shape: tube(0.012),
        medium: FluidMedium.water,
        volume: 0.0,
        modes: 4,
        wallThickness: 0.0008,
      );
      world.bodies.addAll([source, target]);
      for (var i = 0; i < 240; i++) {
        source.place(Matrix3.rotationX(1.3), Vector3(0, 0.1, -0.1045));
        target.place(Matrix3.identity(), Vector3.zero());
        world.advance(world.step);
      }
      return target.volume;
    }

    final reference = pour(const DartFluid());
    expect(reference, greaterThan(1e-6));
    expect(pour(const NativeLiquid()), closeTo(reference, 0.01 * reference));
  });

  test('a pipe and a float on the module move as the reference\'s do', () {
    // Two tubes joined at their floors, a ball floating in the fuller one.
    (double, double) run(FluidSolver solver) {
      RevolvedVessel tube() =>
          RevolvedVessel([Vector2(0, 0), Vector2(0.03, 0), Vector2(0.03, 0.5)]);
      final gravity = Vector3(0, -9.81, 0);
      final collisions = CollisionWorld();
      final dynamics = Dynamics(world: collisions, gravity: gravity);
      final world = FluidWorld(gravity: gravity, solver: solver);
      final a = LiquidBody(
        shape: tube(),
        medium: FluidMedium.water,
        volume: 3.4e-4,
        modes: 2,
      );
      final b = LiquidBody(
        shape: tube(),
        medium: FluidMedium.water,
        volume: 2.3e-4,
        modes: 2,
      );
      world.bodies.addAll([a, b]);
      world.pipes.add(
        Pipe(
          from: a,
          at: Vector3(0, 0.001, 0),
          to: b,
          toAt: Vector3(0, 0.001, 0),
          radius: 0.01,
          length: 0.1,
        ),
      );
      final ball = RigidBody(
        world: collisions,
        shape: CollisionSphere(0.01),
        position: Vector3(0, 0.15, 0),
        mass: 0.002,
      );
      dynamics.add(ball);
      world.float(ball);
      for (var i = 0; i < 240; i++) {
        a.place(Matrix3.identity(), Vector3.zero());
        b.place(Matrix3.identity(), Vector3(0.2, 0, 0));
        world.advance(world.step);
        dynamics.step(world.step);
      }
      return (a.height - b.height, ball.position.y);
    }

    final reference = run(const DartFluid());
    final core = run(const NativeLiquid());
    expect(core.$1, closeTo(reference.$1, 1e-4));
    expect(core.$2, closeTo(reference.$2, 1e-4));
  });

  test('the shared scene steps to the native library\'s bytes', () {
    expect(hashOf(sharedSceneSnapshot()), sharedSceneHash);
  });
}
