/// The committed 1.0 snapshots through the Dart side: the bytes a 1.x core
/// has to keep reading, restored and stepped to the digests the C core
/// lands on.
///
/// `test/fixtures/v1/world.f32.snapshot` and `world.f64.snapshot` are a
/// world of every subsystem — a car, a chain of links, joints, a hull, a
/// mesh and a compound, fire, a stream with its spray and bubbles — as the
/// 1.0 cores wrote it in each precision (`csrc/tests/full_world.h`). They
/// were minted once and are never minted again. The Dart bindings run the
/// floats build, which reads the doubles snapshot rounded; both are
/// restored here and stepped two seconds, and the digest is the one
/// `csrc/tests/test_snapshot_fixture.c` holds the floats build to, hashed
/// the same way over every body's transform, velocity and spin.
///
/// **A digest that fails is not to be updated.** It means a snapshot a 1.0
/// game saved no longer restores to the world it was: a field reordered,
/// a section 1.0 wrote read another way. Fix the reader, or the change is
/// a major.
///
///     dart test test/snapshot_fixture_test.dart
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:test/test.dart';

/// FNV-1a, 64 bits, over the floats of [values] as the core holds them.
int _fnv(int hash, Float32List values) {
  final bytes = Uint8List.sublistView(values);
  var h = hash;
  for (final b in bytes) {
    h = (h ^ b) * 1099511628211;
  }
  return h;
}

/// [world]'s digest as `test_snapshot_fixture.c` takes it, in hex.
String _digest(NativeWorld world) {
  final block = world.readTransforms();
  var hash = _fnv(1469598103934665603, block.transforms);
  for (final body in block.bodies) {
    final v = world.velocityOf(body);
    final w = world.angularVelocityOf(body);
    hash = _fnv(
      hash,
      Float32List.fromList(<double>[v.x, v.y, v.z, w.x, w.y, w.z]),
    );
  }
  String half(int bits) => bits.toRadixString(16).padLeft(8, '0');
  return '${half((hash >> 32) & 0xffffffff)}${half(hash & 0xffffffff)}';
}

String _restoredAndStepped(String path) {
  final world = NativeWorld();
  try {
    world.restore(File(path).readAsBytesSync());
    for (var step = 0; step < 120; step++) {
      world.step(1.0 / 60.0);
    }
    return _digest(world);
  } finally {
    world.dispose();
  }
}

void main() {
  test('the 1.0 floats snapshot restores and steps to its digest', () {
    // Mutation: swap two fields of any section's walk in f3d_snapshot.c
    // (both ways, so the round trip still holds) and this restores another
    // world, or refuses it.
    expect(
      _restoredAndStepped('test/fixtures/v1/world.f32.snapshot'),
      '32b28acd47f72370',
      reason:
          'a 1.0 snapshot no longer restores to its world: do not update '
          'the digest, fix the reader',
    );
  });

  test(
    'the 1.0 doubles snapshot restores, rounded, and steps to its digest',
    () {
      expect(
        _restoredAndStepped('test/fixtures/v1/world.f64.snapshot'),
        'ae8f15c67051cdb3',
        reason:
            'a 1.0 snapshot no longer restores to its world: do not update '
            'the digest, fix the reader',
      );
    },
  );
}
