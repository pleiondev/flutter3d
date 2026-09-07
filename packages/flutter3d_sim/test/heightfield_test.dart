/// The ground a strategy is played on, and the one question it exists to
/// answer correctly: where is the surface, exactly.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A field whose sample at `(column, row)` is `height(column, row)`.
Heightfield _field(
  int columns,
  int rows,
  double Function(int column, int row) height, {
  double cellSize = 1.0,
}) {
  final heights = Float32List(columns * rows);
  for (var row = 0; row < rows; row++) {
    for (var column = 0; column < columns; column++) {
      heights[row * columns + column] = height(column, row);
    }
  }
  return Heightfield(
    columns: columns,
    rows: rows,
    cellSize: cellSize,
    heights: heights,
  );
}

/// What bilinear interpolation would have said, for the tests that exist to
/// show it would have been wrong.
double _bilinear(
  double h00,
  double h10,
  double h01,
  double h11,
  double u,
  double v,
) =>
    h00 * (1 - u) * (1 - v) +
    h10 * u * (1 - v) +
    h01 * (1 - u) * v +
    h11 * u * v;

void main() {
  group('flat ground', () {
    test('is its own height everywhere, and faces up', () {
      // Mutation: drop the `+ (h11 - h10) * cell.v` term from `heightAt`. Flat
      // ground survives it — which is why the saddle below exists.
      final field = _field(4, 4, (_, _) => 2.5);
      final normal = Vector3.zero();

      expect(field.heightAt(1.3, 2.7), closeTo(2.5, 1e-6));
      field.normalAt(1.3, 2.7, normal);
      expect(normal.x, closeTo(0.0, 1e-6));
      expect(normal.y, closeTo(1.0, 1e-6));
      expect(field.slopeAt(1.3, 2.7), closeTo(0.0, 1e-6));
    });
  });

  group('a ramp', () {
    test('rises by its gradient and reports the angle', () {
      // One metre up per metre along, so the answer is forty-five degrees and
      // any confusion of cell size with sample spacing shows as a wrong angle.
      // Mutation: divide by `cellSize` twice in `_cellAt` — the height stays
      // right at the samples and the slope doubles between them.
      final field = _field(4, 4, (column, _) => column.toDouble());

      expect(field.heightAt(0.0, 0.0), closeTo(0.0, 1e-6));
      expect(field.heightAt(1.5, 0.5), closeTo(1.5, 1e-6));
      expect(field.slopeAt(1.5, 0.5), closeTo(math.pi / 4, 1e-6));
    });

    test('is twice as steep when the samples are half as far apart', () {
      // The same heights on a finer grid are a steeper hill, which is the whole
      // meaning of `cellSize`.
      final field = _field(
        4,
        4,
        (column, _) => column.toDouble(),
        cellSize: 0.5,
      );

      expect(field.slopeAt(0.75, 0.25), closeTo(math.atan(2.0), 1e-6));
    });
  });

  group('a saddle, where the surface is not a sheet', () {
    // **The case the class exists for.** Corners 0, 1, 1, 0: the two triangles
    // of the quad are two different planes, and the smooth surface bilinear
    // interpolation describes is drawn by nothing. A body placed by bilinear
    // floats over one triangle and sinks into the other.
    Heightfield saddle() =>
        _field(2, 2, (column, row) => column == row ? 0.0 : 1.0);

    test('answers with the triangle under the point, not a smooth sheet', () {
      // Mutation: replace the two branches in `heightAt` with `_bilinear`.
      // These two expectations fail by an eighth of a metre and the flat and
      // ramp tests above stay green, which is exactly how this got missed.
      final field = saddle();

      // Below the diagonal: the triangle (0,0), (1,0), (1,1) says u - v.
      expect(field.heightAt(0.75, 0.25), closeTo(0.5, 1e-6));
      // Above it: the triangle (0,0), (0,1), (1,1) says v - u.
      expect(field.heightAt(0.25, 0.75), closeTo(0.5, 1e-6));

      // And what the smooth answer would have been, so the gap is on the record
      // rather than implied.
      expect(_bilinear(0.0, 1.0, 1.0, 0.0, 0.75, 0.25), closeTo(0.625, 1e-6));
    });

    test('agrees with itself along the diagonal the quad is split on', () {
      // The two triangles share that edge, so the two branches must meet on it.
      // Mutation: split the quad the other way in one branch only — the halves
      // then disagree here by the corner spread.
      final field = saddle();

      for (final double t in <double>[0.1, 0.35, 0.5, 0.9]) {
        expect(
          field.heightAt(t, t),
          closeTo(0.0, 1e-6),
          reason: 'the seam at $t',
        );
      }
    });

    test('gives each triangle its own normal', () {
      // A shading normal averaged across the quad would be the same on both
      // sides and would hold a body at an angle no drawn triangle has.
      final field = saddle();
      final below = Vector3.zero();
      final above = Vector3.zero();

      field.normalAt(0.75, 0.25, below);
      field.normalAt(0.25, 0.75, above);

      expect(
        below.y,
        greaterThan(0.0),
        reason: 'a normal points up out of the ground',
      );
      expect(above.y, greaterThan(0.0));
      expect(
        (below - above).length,
        greaterThan(0.5),
        reason: 'the two halves of a saddle do not face the same way',
      );
    });
  });

  _navigationTests();
  _geometryTests();
  _documentTests();

  group('off the edge', () {
    test('is the edge, not a hole', () {
      // Mutation: let `_cellAt` clamp to zero instead of to the last cell. A
      // unit walking off the map then drops to the origin plane, which is a
      // cliff that appears in no picture.
      final field = _field(3, 3, (column, _) => column.toDouble());

      expect(field.contains(-1.0, 1.0), isFalse);
      expect(field.heightAt(-5.0, 1.0), closeTo(0.0, 1e-6));
      expect(field.heightAt(99.0, 1.0), closeTo(2.0, 1e-6));
    });

    test('knows its own extent', () {
      final field = _field(5, 3, (_, _) => 0.0, cellSize: 2.0);

      expect(field.width, closeTo(8.0, 1e-9));
      expect(field.depth, closeTo(4.0, 1e-9));
      expect(field.contains(8.0, 4.0), isTrue);
      expect(field.contains(8.1, 4.0), isFalse);
    });
  });
}

/// The other half of the field's job: ground an agent can be sent across.
void _navigationTests() {
  group('a grid baked from a field', () {
    test('covers the field and stands on it', () {
      // Mutation: measure the grid from `columns` rather than from `width` —
      // the grid then covers one cell too many and the far row stands on the
      // edge height for ever.
      final field = _field(9, 9, (_, _) => 3.0);
      final grid = NavGrid.bakeHeightfield(field, cellSize: 2.0);

      expect(grid.columns, 4, reason: '8 metres of field in 2-metre cells');
      expect(grid.rows, 4);
      for (var i = 0; i < grid.cellCount; i++) {
        expect(grid.isWalkable(i), isTrue, reason: 'flat ground is walkable');
        expect(grid.floorAt(i), closeTo(3.0, 1e-6));
      }
    });

    test('refuses ground too steep to stand on', () {
      // A wall of one metre per half metre is sixty-three degrees, over the
      // forty the bake allows by default. Mutation: drop the slope test — the
      // cliff becomes a staircase and units walk up it.
      final field = _field(9, 9, (column, _) => column * 2.0, cellSize: 1.0);
      final grid = NavGrid.bakeHeightfield(field, cellSize: 1.0);

      expect(
        List<int>.generate(
          grid.cellCount,
          (int i) => i,
        ).where(grid.isWalkable).isEmpty,
        isTrue,
        reason: 'nothing on a 63-degree hillside is standable',
      );
    });

    test('and the limit is the callers, not the fields', () {
      // The same hillside, twice, with two agents that disagree about it —
      // which is the reason `slopeAt` reports an angle and stops there.
      final field = _field(9, 9, (column, _) => column * 0.5, cellSize: 1.0);

      final scout = NavGrid.bakeHeightfield(
        field,
        cellSize: 1.0,
        maxSlope: 0.6,
      );
      final tank = NavGrid.bakeHeightfield(field, cellSize: 1.0, maxSlope: 0.3);

      expect(scout.isWalkable(scout.cellIndex(2, 2)), isTrue);
      expect(tank.isWalkable(tank.cellIndex(2, 2)), isFalse);
    });

    test('leaves a cell whose centre is off the field unwalkable', () {
      // Mutation: drop the `contains` guard. `heightAt` answers for points
      // beyond the edge on purpose, so the bake would lay standing places over
      // ground that is not there.
      final field = _field(3, 3, (_, _) => 0.0);
      final grid = NavGrid.bakeHeightfield(field, cellSize: 1.5);

      expect(grid.columns, 2, reason: '2 metres of field in 1.5-metre cells');
      expect(grid.isWalkable(grid.cellIndex(0, 0)), isTrue, reason: 'at 0.75');
      expect(grid.isWalkable(grid.cellIndex(1, 0)), isFalse, reason: 'at 2.25');
    });

    test('refuses ground something else has taken', () {
      // Slope says a courtyard is standable; a wall round it says nobody may.
      // The two are different questions, which is why the bake asks them
      // separately. Mutation: ask `blocked` after the slope test instead of
      // before — flat ground under a building is walkable again.
      final field = _field(11, 11, (_, _) => 0.0);
      final grid = NavGrid.bakeHeightfield(
        field,
        cellSize: 1.0,
        blocked: (double x, double z) =>
            x > 3.0 && x < 7.0 && z > 3.0 && z < 7.0,
      );

      expect(grid.isWalkable(grid.cellAtPoint(5.0, 5.0)), isFalse);
      expect(grid.isWalkable(grid.cellAtPoint(1.5, 5.0)), isTrue);
      expect(grid.isWalkable(grid.cellAtPoint(8.5, 5.0)), isTrue);
    });

    test('gives the middle of open ground room for a body', () {
      // Clearance is what a flow field asks before it sends anything wide
      // through: the middle of a plateau has to have more of it than the rim.
      final field = _field(11, 11, (_, _) => 0.0);
      final grid = NavGrid.bakeHeightfield(field, cellSize: 1.0);

      final middle = grid.clearanceAt(grid.cellIndex(5, 5));
      final rim = grid.clearanceAt(grid.cellIndex(0, 5));

      expect(
        rim,
        1,
        reason: 'the edge has something beside it that is not ground',
      );
      expect(middle, greaterThan(rim));
      expect(middle, greaterThanOrEqualTo(grid.clearanceForRadius(1.5)));
    });
  });
}

/// The triangles the ground is drawn from, and the two things they must agree
/// with: the field underneath and the sky above.
void _geometryTests() {
  group('the triangles of a field', () {
    test('are one vertex per sample and two triangles per quad', () {
      final field = _field(5, 4, (_, _) => 0.0);
      final surface = const HeightfieldGeometry().build(
        field,
        material: 'turf',
      );

      expect(surface.positions.length, 5 * 4 * 3);
      expect(surface.triangleCount, 4 * 3 * 2);
      expect(surface.material, 'turf');
    });

    test('stand exactly where the field says', () {
      // Mutation: read `sample(row, column)` instead of `sample(column, row)`.
      // A square field survives it, which is why this one is not square.
      final field = _field(5, 3, (column, row) => column * 1.0 + row * 10.0);
      final surface = const HeightfieldGeometry().build(
        field,
        material: 'turf',
      );

      for (var row = 0; row < 3; row++) {
        for (var column = 0; column < 5; column++) {
          final v = (row * 5 + column) * 3;
          expect(surface.positions[v], closeTo(column * 1.0, 1e-6));
          expect(
            surface.positions[v + 1],
            closeTo(field.sample(column, row), 1e-6),
            reason: 'sample ($column, $row)',
          );
          expect(surface.positions[v + 2], closeTo(row * 1.0, 1e-6));
        }
      }
    });

    test('face the sky, every one of them', () {
      // Winding is the whole of this: a quad wound the other way is ground seen
      // from underneath, which on a lit scene is black and on a culled one is
      // not there at all. Mutation: swap two indices of either triangle.
      final field = _field(6, 6, (column, row) => (column * row) % 3 * 0.4);
      final surface = const HeightfieldGeometry().build(
        field,
        material: 'turf',
      );

      for (var t = 0; t < surface.triangleCount; t++) {
        final a = surface.indices[t * 3] * 3;
        final b = surface.indices[t * 3 + 1] * 3;
        final c = surface.indices[t * 3 + 2] * 3;
        // Only the Y of the cross product is asked for, so only the two terms
        // that make it are taken.
        final ux = surface.positions[b] - surface.positions[a];
        final uz = surface.positions[b + 2] - surface.positions[a + 2];
        final vx = surface.positions[c] - surface.positions[a];
        final vz = surface.positions[c + 2] - surface.positions[a + 2];

        expect(uz * vx - ux * vz, greaterThan(0.0), reason: 'triangle $t');
      }
    });

    test('split every quad on the diagonal the field splits on', () {
      // The rule written in `Heightfield`: both triangles carry the corner at
      // (0,0) and the one at (1,1). A builder that split the other way would
      // draw a surface `heightAt` does not describe, and nothing would show it
      // but a body standing slightly off the ground.
      final field = _field(3, 3, (_, _) => 0.0);
      final surface = const HeightfieldGeometry().build(
        field,
        material: 'turf',
      );

      for (var t = 0; t < surface.triangleCount; t++) {
        final corners = <int>[
          surface.indices[t * 3],
          surface.indices[t * 3 + 1],
          surface.indices[t * 3 + 2],
        ];
        // Within a quad the shared edge joins the lowest index to the highest.
        expect(
          corners.reduce(math.max) - corners.reduce(math.min),
          3 + 1,
          reason: 'triangle $t spans the quad diagonal of a 3-wide field',
        );
      }
    });

    test('are shaded smooth even though the field answers flat', () {
      // Two different questions, deliberately answered differently: a body
      // stands on a facet, a picture is not made of them. Mutation: copy
      // `Heightfield.normalAt` into the builder — the two normals then agree
      // and the ground draws as a field of visible triangles.
      final field = _field(5, 5, (column, _) => column * 0.5);
      final surface = const HeightfieldGeometry().build(
        field,
        material: 'turf',
      );
      final faceted = Vector3.zero();
      field.normalAt(2.25, 2.25, faceted);

      final v = (2 * 5 + 2) * 3;
      final smooth = Vector3(
        surface.normals[v],
        surface.normals[v + 1],
        surface.normals[v + 2],
      );

      expect(smooth.length, closeTo(1.0, 1e-6), reason: 'normals are unit');
      expect(smooth.y, greaterThan(0.0));
      // On an even ramp the two happen to agree; what must hold everywhere is
      // that the drawn normal is a unit vector out of the ground.
      expect(smooth.dot(faceted), greaterThan(0.9));
    });
  });
}

/// The field as a level document carries it.
void _documentTests() {
  group('a field in a level', () {
    test('survives being written and read back', () {
      // Mutation: write `heights` as a plain list of numbers. It round-trips
      // too — and the file grows from a few kilobytes to a megabyte of digits,
      // which is why the check below is on the bytes rather than on the values.
      final field = _field(9, 5, (column, row) => column * 0.25 - row * 0.5);
      final level = Level(name: 'ridge', heightfield: field);

      final read = Level.fromJson(
        jsonDecode(jsonEncode(level.toJson())) as Map<String, Object?>,
      );

      final ground = read.heightfield;
      expect(ground, isNotNull);
      expect(ground!.columns, 9);
      expect(ground.rows, 5);
      expect(ground.cellSize, closeTo(1.0, 1e-9));
      for (var row = 0; row < 5; row++) {
        for (var column = 0; column < 9; column++) {
          expect(
            ground.sample(column, row),
            closeTo(field.sample(column, row), 1e-6),
            reason: 'sample ($column, $row)',
          );
        }
      }
    });

    test('is absent from a level that has none', () {
      // The format grows by addition: a level written before terrain existed
      // must come back byte for byte.
      final level = Level(name: 'flat');

      expect(level.toJson().containsKey('heightfield'), isFalse);
      expect(Level.fromJson(level.toJson()).heightfield, isNull);
    });

    test('refuses a section whose heights do not match its size', () {
      // Mutation: drop the length check. A field two samples short is read as
      // a field of whatever arrived, and the ground ends early — in the middle
      // of a map, silently.
      final field = _field(4, 4, (_, _) => 1.0);
      final section = field.toJson()..['columns'] = 5;

      expect(
        () => Heightfield.fromJson(section),
        throwsA(isA<FormatException>()),
      );
    });

    test('refuses a section with no surface in it', () {
      expect(
        () => Heightfield.fromJson(<String, Object?>{
          'columns': 1,
          'rows': 9,
          'heights': base64Encode(Float32List(9).buffer.asUint8List()),
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
