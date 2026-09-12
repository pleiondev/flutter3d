/// `packIslands` — `pro-uv-05`'s own worked example: a hundred rectangles,
/// none overlapping once margin is honoured, covering at least 60% of the
/// square they landed in.
///
///     dart test test/uv_pack_test.dart
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A hundred sizes, varied but fixed — no `Random()`, so a failure is the
/// same rectangles every time it is chased.
List<Vector2> _hundredSizes() => <Vector2>[
  for (var i = 0; i < 100; i++)
    Vector2(0.4 + (i % 7) * 0.15, 0.4 + ((i * 3 + 1) % 5) * 0.2),
];

/// Whether island [a] and island [b] — both already at [result]'s own
/// scale — keep at least `margin * result.scale` of empty space between
/// them, checked without assuming which shelf either landed on: the general
/// separated-on-some-axis test any two non-overlapping rectangles with a
/// gap must pass.
bool _separated(
  PackedIsland a,
  Vector2 sizeA,
  PackedIsland b,
  Vector2 sizeB,
  double gap,
) {
  final aRight = a.offset.x + sizeA.x;
  final aTop = a.offset.y + sizeA.y;
  final bRight = b.offset.x + sizeB.x;
  final bTop = b.offset.y + sizeB.y;
  return aRight + gap <= b.offset.x ||
      bRight + gap <= a.offset.x ||
      aTop + gap <= b.offset.y ||
      bTop + gap <= a.offset.y;
}

void main() {
  test('a hundred rectangles pack with none overlapping — the row\'s own '
      'worked example', () {
    final sizes = _hundredSizes();
    final result = packIslands(sizes, margin: 0.02);
    expect(result, isNotNull);

    final placed = <Vector2>[
      for (var i = 0; i < sizes.length; i++)
        Vector2(sizes[i].x, sizes[i].y)..scale(result!.scale),
    ];
    final gap = 0.02 * result!.scale;

    for (var i = 0; i < sizes.length; i++) {
      for (var j = i + 1; j < sizes.length; j++) {
        expect(
          _separated(
            result.islands[i],
            placed[i],
            result.islands[j],
            placed[j],
            gap * 0.999, // floating-point slack, not a relaxed margin
          ),
          isTrue,
          reason: 'islands $i and $j overlap',
        );
      }
    }
  });

  test('the same hundred rectangles cover at least 60% of the square', () {
    // Mutation: search for a width that minimizes wasted space by some
    // wrong criterion (say, minimizing width alone) — the packed square
    // stays valid (nothing overlaps) but wastes far more than 40% of
    // itself, and this is the test that would notice.
    final result = packIslands(_hundredSizes(), margin: 0.02);
    expect(result!.fillRatio, greaterThanOrEqualTo(0.60));
  });

  test('every island lands inside the unit square', () {
    final sizes = _hundredSizes();
    final result = packIslands(sizes, margin: 0.02)!;
    for (var i = 0; i < sizes.length; i++) {
      final size = Vector2(sizes[i].x, sizes[i].y)..scale(result.scale);
      final offset = result.islands[i].offset;
      expect(offset.x, greaterThanOrEqualTo(-1e-6));
      expect(offset.y, greaterThanOrEqualTo(-1e-6));
      expect(offset.x + size.x, lessThanOrEqualTo(1.0 + 1e-6));
      expect(offset.y + size.y, lessThanOrEqualTo(1.0 + 1e-6));
    }
  });

  test('allowRotate90 turns a too-wide island rather than refusing it', () {
    // One island wider than any reasonable container, and short — without
    // rotation it would either force an enormous container or overhang one;
    // with rotation it lies down and packs like anything else.
    final sizes = <Vector2>[Vector2(5.0, 0.2), Vector2(0.3, 0.3)];
    final result = packIslands(sizes, margin: 0.01, allowRotate90: true);
    expect(result, isNotNull);
    expect(result!.islands[0].rotated, isTrue);
  });

  test('refuses an empty list, a negative margin, and a non-positive size', () {
    expect(packIslands(<Vector2>[], margin: 0.01), isNull);
    expect(packIslands(<Vector2>[Vector2(1, 1)], margin: -0.01), isNull);
    expect(packIslands(<Vector2>[Vector2(0, 1)], margin: 0.01), isNull);
    expect(packIslands(<Vector2>[Vector2(1, -1)], margin: 0.01), isNull);
  });
}
