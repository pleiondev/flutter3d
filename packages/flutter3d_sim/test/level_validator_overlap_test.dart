/// A single brush spanning more than one of the overlap check's grid cells
/// does not overlap itself.
///
///     flutter test test/level_validator_overlap_test.dart
///
/// `_checkOverlaps` used to bucket brushes by `(x << 32) ^ (z & 0xFFFFFFFF)`,
/// packed into one int. On the VM that puts `x` in the high 32 bits and `z`
/// in the low 32, so the two never collide; on the web, `<<` truncates its
/// shift to five bits, so `x << 32` there is `x` unshifted, and cells like
/// `(-1, -1)` and `(0, 0)` hash to the same bucket. A brush whose bounding
/// box straddles the origin — the showcase's own `LevelLoaderDemo` document
/// is exactly this shape — then meets itself in the pairing loop and is
/// reported overlapping its own volume by its own volume.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('a brush straddling the grid origin does not overlap itself', () {
    // Centred on the origin with a footprint wider than the validator's
    // 8-metre cell, so it spans cells -1 and 0 on both axes — the same
    // shape as the showcase's `LevelLoaderDemo` document.
    final brush = Brush(
      centre: Vector3(0.0, -0.5, 0.0),
      size: Vector3(4, 1, 4),
    );
    final level = Level(name: 'straddles', brushes: <Brush>[brush]);

    final issues = LevelValidator(
      registry: EntityRegistry(const <EntityKind>[]),
    ).validate(level);

    expect(
      issues.where((LevelIssue i) => i.message.contains('overlaps')),
      isEmpty,
      reason: 'the only brush in the document has nothing else to overlap',
    );
  });
}
