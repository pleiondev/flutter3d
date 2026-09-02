/// Which parts of a level can be seen from where.
///
///     flutter test test/level_visibility_test.dart
///
/// A toy level of three rooms: two joined by a doorway, a third sealed off.
/// The table has to say the first two see each other and neither sees the
/// third — and has to say it after a trip through JSON, refuse a table baked
/// from other walls, and never hide what a camera in no cell might see.
library;

import 'dart:convert';

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

Brush _box(double x, double y, double z, double sx, double sy, double sz) =>
    Brush(centre: Vector3(x, y, z), size: Vector3(sx, sy, sz));

/// Three rooms in a row along X, each 8 m square and 4 m high, floors and
/// ceilings included. Room A (x 0..8) and room B (x 10..18) share a wall with
/// a 2 m doorway in it; room C (x 20..28) is sealed.
Level _rooms({bool doorway = true}) => Level(
  name: 'rooms',
  brushes: <Brush>[
    // Floor and ceiling under and over everything.
    _box(14.0, -0.5, 4.0, 30.0, 1.0, 10.0),
    _box(14.0, 4.5, 4.0, 30.0, 1.0, 10.0),
    // Outer walls along Z.
    _box(14.0, 2.0, -0.5, 30.0, 4.0, 1.0),
    _box(14.0, 2.0, 8.5, 30.0, 4.0, 1.0),
    // End walls.
    _box(-0.5, 2.0, 4.0, 1.0, 4.0, 8.0),
    _box(28.5, 2.0, 4.0, 1.0, 4.0, 8.0),
    // A–B wall at x 8..10, with or without a doorway at z 3..5.
    if (doorway) ...<Brush>[
      _box(9.0, 2.0, 1.5, 2.0, 4.0, 3.0),
      _box(9.0, 2.0, 6.5, 2.0, 4.0, 3.0),
    ] else
      _box(9.0, 2.0, 4.0, 2.0, 4.0, 8.0),
    // B–C wall at x 18..20, solid.
    _box(19.0, 2.0, 4.0, 2.0, 4.0, 8.0),
  ],
);

Vector3 _inA() => Vector3(2.0, 1.5, 4.0);
Vector3 _inB() => Vector3(14.0, 1.5, 4.0);
Vector3 _inC() => Vector3(24.0, 1.5, 4.0);

void main() {
  group('three rooms', () {
    final table = LevelVisibility.bake(
      _rooms(),
      cellSize: 2.0,
      samplesPerAxis: 2,
    );
    final a = table.cellAt(_inA());
    final b = table.cellAt(_inB());
    final c = table.cellAt(_inC());

    test('are open cells, and a wall is not', () {
      expect(a, greaterThanOrEqualTo(0));
      expect(b, greaterThanOrEqualTo(0));
      expect(c, greaterThanOrEqualTo(0));
      expect(
        table.cellAt(Vector3(19.0, 2.0, 4.0)),
        -1,
        reason: 'inside the B–C wall',
      );
      expect(table.cellAt(Vector3(-50.0, 0.0, 0.0)), -1, reason: 'off grid');
    });

    test('see through the doorway and not through the wall', () {
      expect(table.canSee(a, b), isTrue, reason: 'A sees B through the door');
      expect(table.canSee(b, a), isTrue, reason: 'and the table is symmetric');
      expect(table.canSee(b, c), isFalse, reason: 'B cannot see into C');
      expect(table.canSee(a, c), isFalse);
      expect(table.canSee(c, c), isTrue, reason: 'a cell sees itself');
    });

    test('and a sealed wall closes the doorway', () {
      final sealed = LevelVisibility.bake(
        _rooms(doorway: false),
        cellSize: 2.0,
      );
      expect(
        sealed.canSee(sealed.cellAt(_inA()), sealed.cellAt(_inB())),
        isFalse,
      );
    });

    test('a batch is visible when any cell it touches is', () {
      // C's far wall is invisible from A; a box spanning B and C is not,
      // because part of it is in B.
      final farWall = Aabb3.minMax(
        Vector3(27.0, 0.0, 0.0),
        Vector3(28.0, 4.0, 8.0),
      );
      final spanning = Aabb3.minMax(
        Vector3(15.0, 0.0, 0.0),
        Vector3(25.0, 4.0, 8.0),
      );
      expect(table.isVisible(a, farWall), isFalse);
      expect(table.isVisible(a, spanning), isTrue);
    });

    test('a camera in no cell sees everything', () {
      // Outside the grid or inside a wall, the table has no opinion, and no
      // opinion draws.
      final farWall = Aabb3.minMax(
        Vector3(27.0, 0.0, 0.0),
        Vector3(28.0, 4.0, 8.0),
      );
      expect(table.isVisible(-1, farWall), isTrue);
      expect(table.canSee(-1, c), isTrue);
    });

    test('a box entirely inside the walls draws', () {
      final inWall = Aabb3.minMax(
        Vector3(18.2, 0.5, 3.0),
        Vector3(19.8, 3.5, 5.0),
      );
      expect(table.isVisible(a, inWall), isTrue);
    });
  });

  group('the sidecar', () {
    test('survives a round trip through JSON', () {
      final table = LevelVisibility.bake(
        _rooms(),
        cellSize: 2.0,
        samplesPerAxis: 2,
      );
      final read = LevelVisibility.fromJson(
        jsonDecode(jsonEncode(table.toJson())) as Map<String, Object?>,
      );

      expect(read.cellCount, table.cellCount);
      expect(read.brushHash, table.brushHash);
      final a = read.cellAt(_inA());
      final b = read.cellAt(_inB());
      final c = read.cellAt(_inC());
      expect(a, table.cellAt(_inA()));
      expect(read.canSee(a, b), isTrue);
      expect(read.canSee(b, c), isFalse);
    });

    test('is stale when a wall moves', () {
      final table = LevelVisibility.bake(
        _rooms(),
        cellSize: 2.0,
        samplesPerAxis: 2,
      );

      expect(table.isStaleFor(_rooms()), isFalse);
      expect(table.isStaleFor(_rooms(doorway: false)), isTrue);
    });

    test('bakes the same bytes twice', () {
      // Deterministic, so CI can bake and compare against the committed one.
      final once = jsonEncode(
        LevelVisibility.bake(_rooms(), samplesPerAxis: 2).toJson(),
      );
      final twice = jsonEncode(
        LevelVisibility.bake(_rooms(), samplesPerAxis: 2).toJson(),
      );
      expect(twice, once);
    });

    test('refuses a table from a newer build, and says so', () {
      final json = LevelVisibility.bake(_rooms(), samplesPerAxis: 2).toJson()
        ..['version'] = LevelVisibility.formatVersion + 1;

      expect(
        () => LevelVisibility.fromJson(json),
        throwsA(
          isA<VisibilityFormatException>().having(
            (e) => e.message,
            'message',
            contains('newer build'),
          ),
        ),
      );
    });

    test('refuses a table cut short', () {
      final json = LevelVisibility.bake(_rooms(), samplesPerAxis: 2).toJson()
        ..remove('pvs');
      expect(
        () => LevelVisibility.fromJson(json),
        throwsA(isA<VisibilityFormatException>()),
      );
    });
  });

  test('brush geometry batches by cell when given a table', () {
    final level = _rooms();
    final table = LevelVisibility.bake(level, cellSize: 2.0, samplesPerAxis: 2);
    const geometry = BrushGeometry();

    final plain = geometry.build(level);
    final celled = geometry.build(level, visibility: table);

    expect(plain.length, 1, reason: 'one material, one batch');
    expect(celled.length, greaterThan(plain.length));
    // Every triangle is still there: the same vertex count, split up.
    int vertices(List<BrushSurface> surfaces) =>
        surfaces.fold(0, (n, s) => n + s.positions.length ~/ 3);
    expect(vertices(celled), vertices(plain));
    // And a batch's box is what it says: inside the level's extent.
    for (final surface in celled) {
      expect(surface.bounds.min.x, greaterThanOrEqualTo(-1.0));
      expect(surface.bounds.max.x, lessThanOrEqualTo(29.0));
    }
  });
}
