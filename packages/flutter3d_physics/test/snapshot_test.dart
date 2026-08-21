/// Reading a saved body back from a file somebody else wrote.
///
///     dart test test/snapshot_test.dart
///
/// Two identical copies of this lived in `RigidBody` and `CharacterController`,
/// and both would throw on a truncated save.
library;

import 'package:flutter3d_physics/src/snapshot.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('a vector is read into the body that already exists', () {
    final out = Vector3.zero();

    readVector(<double>[1.0, 2.0, 3.0], out);

    expect(out, Vector3(1.0, 2.0, 3.0));
  });

  test('and integers count, because JSON writes 0 rather than 0.0', () {
    final out = Vector3.zero();

    readVector(<Object?>[1, 2.5, 3], out);

    expect(out, Vector3(1.0, 2.5, 3.0));
  });

  test('and what it cannot read leaves the body where it is', () {
    // **This threw.** Both copies read `value[0] as num`, so a save truncated
    // by a machine that lost power, or written by a build that spelled the key
    // differently, was a `TypeError` on load — a game that will not start
    // rather than a body in the wrong place, which a player can walk out of.
    for (final broken in <Object?>[
      null,
      'somewhere',
      <Object?>[1.0, 2.0],
      <Object?>[1.0, 2.0, null],
      <Object?>['1', '2', '3'],
      <Object?>{},
    ]) {
      final out = Vector3(7.0, 8.0, 9.0);

      expect(() => readVector(broken, out), returnsNormally,
          reason: 'reading $broken threw');
      expect(out, Vector3(7.0, 8.0, 9.0),
          reason: '$broken moved the body');
    }
  });

  test('and a vector is written whole or not at all', () {
    // A half-read vector is a position partly where the body was saved and
    // partly where it happens to be, which is somewhere nobody has ever been.
    final out = Vector3(7.0, 8.0, 9.0);

    readVector(<Object?>[1.0, 2.0, 'three'], out);

    expect(out.x, 7.0, reason: 'the first component was written anyway');
  });

  test('a number that is not a number is nought', () {
    expect(readNumber(0.25), 0.25);
    expect(readNumber(3), 3.0);
    expect(readNumber(null), 0.0);
    expect(readNumber('0.25'), 0.0);
  });
}
