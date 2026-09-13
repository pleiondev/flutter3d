/// `mesh-61`'s own row: `ShapeKey` on its own — `grownTo`, `remappedBy`,
/// `blend` — against `EditMesh.cuboid()` and hand-built fixtures.
///
/// **What this file does not cover, and why.** The row's own acceptance
/// line also asks for "импорт 2 targets → 2 ключа" — two `MorphTarget`s
/// producing two `ShapeKey`s on import — which needs a source-vertex-to-
/// `EditMesh`-vertex weld map `importMeshData` computes internally and does
/// not currently expose. Building one independently would either touch
/// `importMeshData`'s own public return shape (used by callers in
/// `flutter3d_modeler`, a tree another session is concurrently editing this
/// week) or re-derive the weld map by a second, separately-tolerance'd pass
/// that could disagree with the real one at a welded corner — neither is a
/// change this row's own scope should force through in the same commit as
/// `ShapeKey` itself. Recorded as the reason this row stays `partial`.
///
///     dart test test/shape_key_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('construction', () {
    test('refuses a positions array not a multiple of three', () {
      expect(() => ShapeKey('bad', Float32List(5)), throwsArgumentError);
    });

    test('positionOf and setPosition round-trip', () {
      final key = ShapeKey('k', Float32List(6));
      key.setPosition(1, Vector3(1.0, 2.0, 3.0));
      final read = key.positionOf(1);
      expect(read.x, 1.0);
      expect(read.y, 2.0);
      expect(read.z, 3.0);
      // The other vertex is untouched.
      expect(key.positionOf(0).x, 0.0);
    });
  });

  group('grownTo', () {
    test('a key already covering the mesh is returned unchanged', () {
      final mesh = EditMesh.cuboid();
      final key = ShapeKey('k', Float32List(mesh.vertexSlotCount * 3));
      final grown = key.grownTo(mesh);
      // Mutation: always allocate a new instance — this would still be
      // equal in content but a different object, which `identical` catches
      // and a content comparison would not.
      expect(identical(grown, key), isTrue);
    });

    test('a shorter key grows, seeded from the mesh\'s own current '
        'positions', () {
      final mesh = EditMesh.cuboid();
      // Covers only the first two vertices of the eight the cube has.
      final short = ShapeKey(
        'k',
        Float32List.fromList(<double>[9, 9, 9, 8, 8, 8]),
      );
      final grown = short.grownTo(mesh);

      expect(grown.vertexCount, mesh.vertexSlotCount);
      // The two vertices it already had are untouched.
      expect(grown.positionOf(0).x, 9.0);
      expect(grown.positionOf(1).x, 8.0);
      // Mutation: seed new slots to (0, 0, 0) instead of the mesh's own
      // position — this cube has no vertex at the origin, so this would
      // read wrong for every one of the six new vertices.
      for (var v = 2; v < mesh.vertexSlotCount; v++) {
        final expected = mesh.positionOf(v);
        final actual = grown.positionOf(v);
        expect(actual.x, closeTo(expected.x, 1e-9), reason: 'vertex $v x');
        expect(actual.y, closeTo(expected.y, 1e-9), reason: 'vertex $v y');
        expect(actual.z, closeTo(expected.z, 1e-9), reason: 'vertex $v z');
      }
    });
  });

  group('remappedBy', () {
    test('a dropped vertex drops out; a survivor lands at its new number', () {
      // Four vertices, hand-numbered; the remap drops 1 and 3, keeps 0 (as
      // 0) and 2 (renumbered to 1) — the exact shape `EditMesh.compact()`'s
      // own `IdRemap` produces.
      final key = ShapeKey(
        'k',
        Float32List.fromList(<double>[
          0, 0, 0, // vertex 0 -> stays 0
          1, 1, 1, // vertex 1 -> dropped
          2, 2, 2, // vertex 2 -> becomes 1
          3, 3, 3, // vertex 3 -> dropped
        ]),
      );
      final remap = IdRemap(
        vertices: Int32List.fromList(<int>[0, EditMesh.none, 1, EditMesh.none]),
        faces: Int32List(0),
      );

      final remapped = key.remappedBy(remap);

      expect(remapped.vertexCount, 2);
      // Mutation: iterate `remap.vertices` in the wrong direction (write
      // `result[old] = ...` instead of `result[to] = ...`) — vertex 0 would
      // then read (2, 2, 2) instead of (0, 0, 0).
      expect(remapped.positionOf(0).x, 0.0);
      expect(remapped.positionOf(1).x, 2.0);
    });

    test('a vertex the key never grew to cover is skipped, not read out '
        'of range', () {
      // Only one vertex's worth of data, but the remap names two —
      // representing a vertex added to the mesh after this key was last
      // grown, which `grownTo` (not `remappedBy`) is what backfills.
      final key = ShapeKey('k', Float32List.fromList(<double>[5, 5, 5]));
      final remap = IdRemap(
        vertices: Int32List.fromList(<int>[0, 1]),
        faces: Int32List(0),
      );
      // The point of this test is that it does not throw a range error.
      final remapped = key.remappedBy(remap);
      expect(remapped.vertexCount, 2);
      expect(remapped.positionOf(0).x, 5.0);
    });
  });

  group('blend', () {
    test('weight 1.0 on a single key reproduces that key exactly', () {
      final mesh = EditMesh.cuboid();
      final target = Float32List(mesh.vertexSlotCount * 3);
      for (var v = 0; v < mesh.vertexSlotCount; v++) {
        target[v * 3] = v.toDouble();
        target[v * 3 + 1] = v * 2.0;
        target[v * 3 + 2] = v * 3.0;
      }
      final key = ShapeKey('smile', target);

      final blended = ShapeKey.blend(mesh, <ShapeKey>[key], <double>[1.0]);
      // Mutation: scale the base's own contribution by weight too instead
      // of only the delta — at weight 1.0 both formulas agree, so this
      // check alone would not catch it; the 0.0-weight test below does.
      expect(blended, orderedEquals(target));
    });

    test('weight 0.0 leaves the base exactly as it was', () {
      final mesh = EditMesh.cuboid();
      final key = ShapeKey(
        'smile',
        Float32List(mesh.vertexSlotCount * 3)
          ..fillRange(0, mesh.vertexSlotCount * 3, 100.0),
      );
      final blended = ShapeKey.blend(mesh, <ShapeKey>[key], <double>[0.0]);

      final base = Float32List(mesh.vertexSlotCount * 3);
      final position = Vector3.zero();
      for (var v = 0; v < mesh.vertexSlotCount; v++) {
        mesh.positionOf(v, position);
        base[v * 3] = position.x;
        base[v * 3 + 1] = position.y;
        base[v * 3 + 2] = position.z;
      }
      // Mutation: skip the `weight == 0.0` short-circuit and always walk
      // the key — floating point makes `x + (y - x) * 0.0` equal to `x`
      // exactly, so this alone would still pass; it is here for the
      // reason stated above the weight-1.0 test, not to catch this one.
      expect(blended, orderedEquals(base));
    });

    test('two keys at half weight land halfway between both, additively', () {
      final mesh = EditMesh.cuboid();
      final base = mesh.positionOf(0);

      final keyA = ShapeKey(
        'a',
        _fullOf(mesh, 0, base + Vector3(2.0, 0.0, 0.0)),
      );
      final keyB = ShapeKey(
        'b',
        _fullOf(mesh, 0, base + Vector3(0.0, 4.0, 0.0)),
      );

      final blended = ShapeKey.blend(
        mesh,
        <ShapeKey>[keyA, keyB],
        <double>[0.5, 0.5],
      );

      // base + 0.5*(2,0,0) + 0.5*(0,4,0) = base + (1, 2, 0).
      // Mutation: blend by replacing rather than summing (the last
      // nonzero-weight key wins outright) — this would read (1, 0, 0) or
      // (0, 2, 0) instead of (1, 2, 0), whichever key is applied last.
      expect(blended[0], closeTo(base.x + 1.0, 1e-6));
      expect(blended[1], closeTo(base.y + 2.0, 1e-6));
      expect(blended[2], closeTo(base.z, 1e-6));
    });

    test('mismatched keys and weights lengths is refused', () {
      final mesh = EditMesh.cuboid();
      expect(
        () => ShapeKey.blend(
          mesh,
          <ShapeKey>[ShapeKey('a', Float32List(mesh.vertexSlotCount * 3))],
          <double>[0.5, 0.5],
        ),
        throwsArgumentError,
      );
    });

    test('a key shorter than the mesh contributes nothing past its own '
        'length', () {
      final mesh = EditMesh.cuboid();
      // Covers only vertex 0.
      final short = ShapeKey(
        'short',
        Float32List.fromList(<double>[99, 99, 99]),
      );
      final blended = ShapeKey.blend(mesh, <ShapeKey>[short], <double>[1.0]);

      final position = Vector3.zero();
      mesh.positionOf(1, position);
      // Mutation: read past `key.vertexCount` anyway (a fixed loop bound
      // of `slots` rather than `min(key.vertexCount, slots)`) — this
      // throws a range error immediately rather than reading vertex 1 as
      // untouched, which is what this checks instead.
      expect(blended[3], closeTo(position.x, 1e-9));
    });
  });

  group('shapeKeyMorphTargets', () {
    test('a delta round-trips: base + target == the shape key', () {
      final mesh = EditMesh.cuboid();
      final plan = MeshLayoutPlan()..build(mesh);
      final key = ShapeKey(
        'puffed',
        _fullOf(mesh, 0, mesh.positionOf(0) + Vector3(0, 0.5, 0)),
      );

      final targets = shapeKeyMorphTargets(plan, mesh, <ShapeKey>[key]);
      expect(targets, hasLength(1));
      expect(targets.single.name, 'puffed');
      expect(targets.single.vertexCount, plan.vertexCount);

      // Every GPU row that came from EditMesh vertex 0 carries the same
      // delta — the row's own "round-trip дельт" — checked by rebuilding
      // the shaped position from base + delta at each one, not just the
      // first.
      final gpuVertexToVertex = plan.gpuVertexToVertex;
      final base = Vector3.zero();
      var sawVertexZero = false;
      for (var g = 0; g < plan.vertexCount; g++) {
        final vertex = gpuVertexToVertex[g];
        mesh.positionOf(vertex, base);
        final shapedFromDelta = Vector3(
          base.x + targets.single.positions[g * 3],
          base.y + targets.single.positions[g * 3 + 1],
          base.z + targets.single.positions[g * 3 + 2],
        );
        final wanted = key.positionOf(vertex);
        expect(shapedFromDelta.x, closeTo(wanted.x, 1e-6));
        expect(shapedFromDelta.y, closeTo(wanted.y, 1e-6));
        expect(shapedFromDelta.z, closeTo(wanted.z, 1e-6));
        if (vertex == 0) sawVertexZero = true;
      }
      expect(sawVertexZero, isTrue);
    });

    test('a vertex duplicated across a sharp edge carries the same delta on '
        'every row it was split into', () {
      final mesh = EditMesh.cuboid();
      final plan = MeshLayoutPlan()..build(mesh);
      // `mesh-14`'s own acceptance: a sharp cube's 8 vertices become more
      // than 8 GPU rows — the seam this function has to carry a delta
      // across correctly, not just the 1:1 case.
      expect(plan.vertexCount, greaterThan(mesh.vertexSlotCount));

      final key = ShapeKey(
        'moved',
        _fullOf(mesh, 0, mesh.positionOf(0) + Vector3(0.3, 0, 0)),
      );
      final target = shapeKeyMorphTargets(plan, mesh, <ShapeKey>[key]).single;

      final gpuVertexToVertex = plan.gpuVertexToVertex;
      final rowsOfVertexZero = <int>[
        for (var g = 0; g < plan.vertexCount; g++)
          if (gpuVertexToVertex[g] == 0) g,
      ];
      // A sharp cube duplicates every vertex into the three faces meeting
      // there — otherwise this test is not exercising a seam at all.
      expect(rowsOfVertexZero.length, greaterThan(1));
      for (final g in rowsOfVertexZero) {
        expect(target.positions[g * 3], closeTo(0.3, 1e-6));
        expect(target.positions[g * 3 + 1], closeTo(0.0, 1e-6));
        expect(target.positions[g * 3 + 2], closeTo(0.0, 1e-6));
      }
    });

    test('composes with toMeshData/withMorphTargets, GPU-vertex-counted', () {
      final mesh = EditMesh.cuboid();
      final plan = MeshLayoutPlan()..build(mesh);
      final key = ShapeKey('k', _fullOf(mesh, 0, mesh.positionOf(0)));

      final drawn = plan
          .toMeshData(mesh)
          .withMorphTargets(shapeKeyMorphTargets(plan, mesh, <ShapeKey>[key]));

      expect(drawn.morphTargets.single.vertexCount, drawn.vertexCount);
    });

    test('a target sized to EditMesh vertices instead of GPU rows is refused '
        'by MeshData, not silently accepted', () {
      final mesh = EditMesh.cuboid();
      final plan = MeshLayoutPlan()..build(mesh);
      final drawn = plan.toMeshData(mesh);
      expect(mesh.vertexSlotCount, isNot(drawn.vertexCount));

      // Built to the wrong count on purpose — `EditMesh`'s own vertex count
      // rather than the plan's GPU vertex count — the row's own "мутация
      // «по вершинам EditMesh»".
      final wrongTarget = MorphTarget(
        vertexCount: mesh.vertexSlotCount,
        positions: Float32List(mesh.vertexSlotCount * 3),
      );
      expect(
        () => drawn.withMorphTargets(<MorphTarget>[wrongTarget]),
        throwsArgumentError,
      );
    });
  });
}

/// [mesh]'s own current positions, with vertex [vertex] overridden to
/// [position] — a full `Float32List` the size `ShapeKey.blend` expects.
Float32List _fullOf(EditMesh mesh, int vertex, Vector3 position) {
  final out = Float32List(mesh.vertexSlotCount * 3);
  final scratch = Vector3.zero();
  for (var v = 0; v < mesh.vertexSlotCount; v++) {
    mesh.positionOf(v, scratch);
    out[v * 3] = v == vertex ? position.x : scratch.x;
    out[v * 3 + 1] = v == vertex ? position.y : scratch.y;
    out[v * 3 + 2] = v == vertex ? position.z : scratch.z;
  }
  return out;
}
