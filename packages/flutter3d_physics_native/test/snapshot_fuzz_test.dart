/// Damaged snapshots through the Dart side — P9: the bytes a world or the
/// dynamics saved, damaged at random, are either read or refused with an
/// [ArgumentError] or a [FormatException], and a refusal leaves the world
/// as it was. Nothing else is thrown: a [RangeError] or a [TypeError] out
/// of a decoder is a decoder that believed what it read.
///
/// The core's own reader is fuzzed harder, field by field and under the
/// sanitisers, in `csrc/tests/test_snapshot.c`; this is the path a game
/// takes to it, and what Dart reads around it — the air's `PRES` section,
/// the dynamics' saved map.
///
///     dart test test/snapshot_fuzz_test.dart
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A world with a little of everything a snapshot holds: bodies of each
/// kind of shape, a hull, a mesh and a compound, a joint, a wind grid,
/// water, and air at another pressure, so its snapshot has a `PRES`.
NativeWorld busyWorld() {
  final world = NativeWorld()
    ..airPressure = 70000
    ..setWindGrid(
      origin: Vector3(-4.0, 0.0, -4.0),
      cell: 4,
      nx: 2,
      ny: 1,
      nz: 2,
      velocities: Float32List.fromList(<double>[
        1,
        0,
        0,
        0,
        0,
        2,
        -1,
        0,
        0,
        0,
        3,
        0,
      ]),
    );
  final floor = world.addBody(
    position: Vector3(0.0, -0.5, 0.0),
    type: NativeBodyType.fixed,
  );
  world.setShape(floor, NativeShape.box(Vector3(10.0, 0.5, 10.0)));
  for (var i = 0; i < 5; i++) {
    final b = world.addBody(position: Vector3(i - 2.0, 1.0 + i * 0.6, 0.0));
    world.setShape(
      b,
      i.isEven
          ? const NativeShape.sphere(0.3)
          : NativeShape.box(Vector3.all(0.25)),
    );
  }
  final hull = world.createHull(<Vector3>[
    Vector3(0.3, 0.0, 0.0),
    Vector3(-0.3, 0.0, 0.0),
    Vector3(0.0, 0.4, 0.0),
    Vector3(0.0, -0.2, 0.0),
    Vector3(0.0, 0.0, 0.3),
    Vector3(0.0, 0.0, -0.3),
  ]);
  world.setHull(world.addBody(position: Vector3(3.0, 2.0, 1.0)), hull);
  final mesh = world.createMesh(
    <Vector3>[
      Vector3(-9.0, 0.0, 3.0),
      Vector3(-5.0, 1.0, 3.0),
      Vector3(-5.0, 1.0, 7.0),
      Vector3(-9.0, 0.0, 7.0),
    ],
    <int>[0, 2, 1, 0, 3, 2],
  );
  world.setMesh(
    world.addBody(position: Vector3.zero(), type: NativeBodyType.fixed),
    mesh,
  );
  final compound = world.createCompound(<NativeCompoundPart>[
    NativeCompoundPart(NativeShape.box(Vector3(0.3, 0.1, 0.1))),
    NativeCompoundPart.hull(hull, at: Vector3(0.0, 0.4, 0.0)),
  ]);
  world.setCompound(
    world.addBody(position: Vector3(-3.0, 2.0, -2.0)),
    compound,
  );
  final a = world.addBody(position: Vector3(1.0, 3.0, -3.0));
  final b = world.addBody(position: Vector3(1.6, 3.0, -3.0));
  world
    ..setShape(a, const NativeShape.sphere(0.2))
    ..setShape(b, const NativeShape.sphere(0.2))
    ..createJoint(
      NativeJointType.spherical,
      a,
      b,
      anchor: Vector3(1.3, 3.0, -3.0),
    );
  world.createShallowLiquid(
    nx: 8,
    nz: 6,
    cell: 0.5,
    origin: Vector3(4.0, 0.0, 4.0),
    ground: List<double>.generate(48, (i) => (i % 8) * 0.05),
  );
  for (var i = 0; i < 40; i++) {
    world.step(1.0 / 60.0);
  }
  return world;
}

/// [bytes] damaged by a few edits: a bit flipped, a word set to a number
/// that breaks counts and indices, or one off by one; sometimes cut short.
Uint8List damaged(Uint8List bytes, math.Random random) {
  final out = Uint8List.fromList(bytes);
  final view = ByteData.sublistView(out);
  const words = <int>[0, 1, 2, 3, 0x7fffffff, 0x80000000, 0xffffffff, 0x10000];
  final edits = 1 + random.nextInt(4);
  for (var e = 0; e < edits; e++) {
    final at = random.nextInt(out.length - 4);
    switch (random.nextInt(4)) {
      case 0:
        out[at] ^= 1 << random.nextInt(8);
      case 1:
        view.setUint32(
          at & ~3,
          words[random.nextInt(words.length)],
          Endian.little,
        );
      case 2:
        final was = view.getUint32(at, Endian.little);
        view.setUint32(
          at,
          (was + (random.nextBool() ? 1 : -1)) & 0xffffffff,
          Endian.little,
        );
      default:
        view.setUint32(at, random.nextInt(1 << 32), Endian.little);
    }
  }
  if (random.nextInt(16) == 0) {
    return Uint8List.sublistView(out, 0, random.nextInt(out.length));
  }
  return out;
}

void main() {
  test('a damaged snapshot is read, or refused with the world as it was', () {
    // Mutation: drop any one of the checks `consistent()` in f3d_snapshot.c
    // makes, or the length check `make()` makes before it allocates — the C
    // test reads past an array; here a world refused is no longer the world
    // it was, or the process dies.
    final source = busyWorld();
    addTearDown(source.dispose);
    final pristine = source.snapshot();
    final target = NativeWorld()..addBody(position: Vector3(7.0, 7.0, 7.0));
    addTearDown(target.dispose);
    final before = target.snapshot();
    final random = math.Random(20261009);
    var taken = 0, refused = 0;
    for (var round = 0; round < 600; round++) {
      final bad = damaged(pristine, random);
      try {
        target.restore(bad);
      } on ArgumentError {
        refused++;
        expect(target.snapshot(), before, reason: 'round $round');
        expect(target.airPressure, standardAtmosphere);
        continue;
      }
      taken++;
      // What was taken reads back as itself.
      final again = target.snapshot();
      final echo = NativeWorld();
      echo.restore(again);
      expect(echo.snapshot(), again, reason: 'round $round');
      expect(target.airPressure, greaterThan(0.0));
      echo.dispose();
      target.restore(before);
    }
    expect(taken, greaterThan(50));
    expect(refused, greaterThan(50));
  });

  test(
    'a damaged saved state is read, or refused with the world as it was',
    () {
      // Mutation: in `NativeDynamics.restoreState`, set the world's
      // properties from the save and leave them set when its core is refused
      // — the world under the save's gravity, the core under its own.
      final world = CollisionWorld(
        properties: WorldProperties(gravity: Vector3(0.0, -24.0, 0.0)),
      )..addBox(Vector3(0.0, -0.5, 0.0), Vector3(20.0, 1.0, 20.0));
      final dynamics = NativeDynamics(world: world);
      addTearDown(dynamics.dispose);
      for (var i = 0; i < 3; i++) {
        dynamics.add(
          RigidBody(
            world: world,
            shape: CollisionBox(Vector3.all(0.4)),
            position: Vector3(i * 1.5, 3.0 + i, 0.0),
          ),
        );
      }
      for (var i = 0; i < 10; i++) {
        dynamics.step(1.0 / 60.0);
      }
      final saved = dynamics.saveState()! as Map<String, Object?>;
      // Saved on the Moon; the world since back under its own gravity.
      final moon = <String, Object?>{
        ...saved,
        'world': WorldProperties(gravity: Vector3(0.0, -1.62, 0.0)).toJson(),
      };
      final core = base64Decode(saved['core']! as String);
      final now = world.properties.gravity.clone();
      final random = math.Random(7);
      var refused = 0;
      for (var round = 0; round < 200; round++) {
        final bad = <String, Object?>{
          ...moon,
          'core': random.nextInt(8) == 0
              ? 'not base64 at all!'
              : base64Encode(damaged(core, random)),
        };
        final bytes = dynamics.native.snapshot();
        try {
          dynamics.restoreState(bad);
          // Taken: put back as it was for the next round.
          dynamics.restoreState(saved);
          continue;
        } on ArgumentError {
          refused++;
        } on FormatException {
          refused++;
        }
        expect(world.properties.gravity, now, reason: 'round $round');
        expect(dynamics.native.snapshot(), bytes, reason: 'round $round');
      }
      expect(refused, greaterThan(20));
    },
  );
}
