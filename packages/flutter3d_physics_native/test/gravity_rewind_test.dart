// A run that changes its world's gravity, rewound to before the change and
// stepped again, is the run it was — item 3 of tasks/1.0-physics-audit.md.
//
// It was not, on the core: the step wrote its Dart-side gravity into the core
// every time, so a rollback that restored the core's bytes had them written
// over by the next step with the gravity Dart still held — the new one — and
// the replayed fall was the wrong fall. Gravity, the air and its pressure
// are the world's now (`CollisionWorld.properties`), carried in the
// dynamics' saved state and in the core's snapshot, and pushed into the core
// only when they change.
//
// Mutation: in `NativeDynamics.step`, write `native.gravity =
// world.properties.gravity` back before `native.step(dt)` and leave
// `restoreState` as it is — the replay after the rewind keeps the Moon's
// gravity from the first step, and the digests part.
import 'dart:typed_data';

import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

typedef Backend = RigidDynamics Function(CollisionWorld world);

final Map<String, Backend> backends = <String, Backend>{
  'Dynamics': (world) => Dynamics(world: world),
  'NativeDynamics': (world) {
    final dynamics = NativeDynamics(world: world);
    addTearDown(dynamics.dispose);
    return dynamics;
  },
};

/// Where every body is and how it moves, as one list of numbers: two runs
/// that agree on it to the bit are the same run.
List<double> digest(RigidDynamics dynamics) => <double>[
  for (final body in dynamics.bodies) ...<double>[
    ...body.position.storage,
    ...body.velocity.storage,
  ],
];

void main() {
  for (final MapEntry(key: name, value: make) in backends.entries) {
    group(name, () {
      late CollisionWorld world;
      late RigidDynamics dynamics;

      setUp(() {
        world = CollisionWorld(
          properties: WorldProperties(gravity: Vector3(0.0, -24.0, 0.0)),
        )..addBox(Vector3(0.0, -0.5, 0.0), Vector3(20.0, 1.0, 20.0));
        dynamics = make(world);
        for (var i = 0; i < 3; i++) {
          dynamics.add(
            RigidBody(
              world: world,
              shape: CollisionBox(Vector3.all(0.4)),
              position: Vector3(i * 1.5, 3.0 + i, 0.0),
            ),
          );
        }
      });

      void run(int steps) {
        for (var i = 0; i < steps; i++) {
          dynamics.step(1 / 60);
        }
      }

      Object? save() => <String, Object?>{
        'bodies': <Object?>[for (final b in dynamics.bodies) b.save()],
        'dynamics': dynamics.saveState(),
      };

      void restore(Object? saved) {
        final map = saved! as Map<String, Object?>;
        final bodies = map['bodies']! as List<Object?>;
        for (var i = 0; i < bodies.length; i++) {
          dynamics.bodies[i].restore(bodies[i]! as Map<String, Object?>);
        }
        dynamics.restoreState(map['dynamics']);
      }

      void toTheMoon() => world.properties = world.properties.copyWith(
        gravity: Vector3(0.0, -1.62, 0.0),
        airPressure: 300.0,
      );

      test('a rewind across a change of gravity replays the same run', () {
        run(10);
        final before = save();
        run(5);
        toTheMoon();
        run(30);
        final first = digest(dynamics);

        restore(before);
        // The world it was saved under, not the Moon it was left on.
        expect(world.properties.gravity, Vector3(0.0, -24.0, 0.0));
        expect(world.properties.airPressure, standardAtmosphere);
        expect(dynamics.gravity, Vector3(0.0, -24.0, 0.0));
        run(5);
        toTheMoon();
        run(30);
        expect(digest(dynamics), first);
      });

      test('a rewind to after the change keeps the Moon', () {
        run(5);
        toTheMoon();
        run(5);
        final after = save();
        run(20);
        final first = digest(dynamics);

        // Back on the Earth before the restore: the save says otherwise.
        world.properties = world.properties.copyWith(
          gravity: Vector3(0.0, -24.0, 0.0),
          airPressure: standardAtmosphere,
        );
        restore(after);
        expect(world.properties.gravity, Vector3(0.0, -1.62, 0.0));
        expect(world.properties.airPressure, 300.0);
        run(20);
        expect(digest(dynamics), first);
      });
    });
  }

  test("the core's snapshot carries the air's pressure, and only off the "
      'standard', () {
    final world = NativeWorld();
    addTearDown(world.dispose);
    final standard = world.snapshot();
    world.airPressure = 300.0;
    final thin = world.snapshot();
    expect(thin.length, standard.length + 20);

    world.airPressure = standardAtmosphere;
    world.restore(thin);
    expect(world.airPressure, 300.0);
    world.restore(standard);
    expect(world.airPressure, standardAtmosphere);
    // A world in the standard air writes the bytes it always wrote.
    expect(world.snapshot(), Uint8List.fromList(standard));
  });

  test('a NativeDynamics steps in its world, not in a vacuum of its own', () {
    final world = CollisionWorld(
      properties: WorldProperties(
        gravity: Vector3(0.0, -24.0, 0.0),
        airTemperature: 250.0,
        wind: Vector3(3.0, 0.0, 0.0),
      ),
    );
    final dynamics = NativeDynamics(world: world);
    addTearDown(dynamics.dispose);
    expect(dynamics.native.gravity, Vector3(0.0, -24.0, 0.0));
    expect(dynamics.native.airTemperature, closeTo(250.0, 1e-4));
    expect(
      dynamics.native.airDensity,
      closeTo(world.properties.airDensity, 1e-6),
    );
    expect(dynamics.native.windAt(Vector3.zero()).x, closeTo(3.0, 1e-6));
  });
}
