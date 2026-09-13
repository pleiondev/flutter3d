/// `pro-uv-07`'s own acceptance, read literally: three islands, one
/// deliberately stretched island paints the acceptance's own `#FF458E`, and
/// the seam this mesh was actually cut on is the only edge `uvSeamEdges`
/// names.
///
///     flutter test test/uv_seam_test.dart
library;

import 'dart:ui';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_modeler/src/uv_seam_overlay.dart';
import 'package:flutter3d_modeler/src/uv_unwrap_layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// An overlay with no device behind it — the same no-op fixture
/// `mesh_overlay_builder_test.dart` uses, since nothing here ever encodes a
/// frame.
MeshOverlay _overlay() =>
    MeshOverlay(
      vertexShader: const ShaderHandle(backend: 0, name: 'DebugLineVertex'),
      fragmentShader: const ShaderHandle(backend: 0, name: 'DebugLineFragment'),
    )..lookFrom(
      eye: Vector3(0, 0, 5),
      right: Vector3(1, 0, 0),
      up: Vector3(0, 1, 0),
      pixel: 0.0012,
    );

/// Two quads sharing the edge 1-2 (A|B), and a third detached from both.
///
///     v3---v2---v5          v9---v8
///      | A |  B |            | C |
///     v0---v1---v4          v6---v7
///
/// All ten points and three faces lie flat on Z=0, wound counter-clockwise
/// seen from +Z, so [UvProjection.box] reads every one of them straight off
/// its own world X/Y with nothing lost — the same "axis-aligned face, no
/// stretch" case `uv_stretch_test.dart`'s own worked example measures.
EditMesh _buildMesh() => EditMesh.fromFaces(
  <Vector3>[
    Vector3(0, 0, 0), // 0
    Vector3(1, 0, 0), // 1
    Vector3(1, 1, 0), // 2
    Vector3(0, 1, 0), // 3
    Vector3(2, 0, 0), // 4
    Vector3(2, 1, 0), // 5
    Vector3(5, 0, 0), // 6
    Vector3(6, 0, 0), // 7
    Vector3(6, 1, 0), // 8
    Vector3(5, 1, 0), // 9
  ],
  <List<int>>[
    <int>[0, 1, 2, 3], // A
    <int>[2, 1, 4, 5], // B
    <int>[6, 7, 8, 9], // C
  ],
);

/// The one half-edge of [face] running from [from] to [to] — a mesh this
/// small reads better as a linear search than a lookup table.
int _halfEdgeFromTo(EditMesh mesh, int face, int from, int to) {
  int? found;
  mesh.forEachHalfEdge(face, (int half) {
    if (mesh.originOf(half) == from && mesh.originOf(mesh.nextOf(half)) == to) {
      found = half;
    }
  });
  return found!;
}

void main() {
  test(
    'three islands: two cut apart by a marked seam, one already detached',
    () {
      final mesh = _buildMesh();
      mesh.beginStep();
      for (var face = 0; face < 3; face++) {
        projectUv(mesh, <int>[face], UvProjection.box);
      }
      // A and B share the edge 1-2; box projection alone leaves the two
      // sides agreeing (both read straight off the same world X/Y), so the
      // only reason `splitIslands` cuts here is this explicit mark — the
      // seam-flag half of `uvSeamEdges`'s own two-way definition.
      final seamHalf = _halfEdgeFromTo(mesh, 0, 1, 2);
      mesh.setEdgeFlag(seamHalf, EdgeFlags.seam, on: true);
      // Deliberately stretch island C: shrinking its own UV to a tenth of
      // its world size reads, by `stretchOf`'s own scale, as roughly ×10 —
      // comfortably past any reasonable "severe" threshold.
      mesh.forEachHalfEdge(2, (int half) {
        mesh.setUv(half, mesh.uvOf(half)..scale(0.1));
      });
      mesh.endStep();

      final islands = splitIslands(mesh);
      expect(islands, hasLength(3));

      // Seam detection: exactly the marked edge, none of the outer
      // boundary (every one of which has no live twin) and nothing from the
      // untouched, still-agreeing rest of A|B's own shared loop.
      final seams = uvSeamEdges(mesh);
      expect(seams, hasLength(1));
      expect(mesh.edgeOf(seams.single), mesh.edgeOf(seamHalf));

      // The colour ramp: only the deliberately stretched island reaches the
      // acceptance's own literal colour, and it is `buildUvIslandData`'s own
      // pipeline that produces it — not a value asserted in isolation.
      final layout = buildUvIslandData(mesh, islands);
      final stretched = layout.firstWhere(
        (UvIslandData island) => island.stretch > 5,
      );
      expect(stretched.stretch, closeTo(10.0, 1e-6));
      expect(stretched.color, const Color(0xFFFF458E));
      expect(stretched.triangles, isNotEmpty);

      for (final island in layout) {
        if (island.id == stretched.id) continue;
        expect(island.stretch, closeTo(1.0, 1e-6));
        expect(island.color, isNot(const Color(0xFFFF458E)));
      }
    },
  );

  test('emitUvSeamOverlay draws one ribbon per seam, reusing MeshOverlay', () {
    final mesh = _buildMesh();
    mesh.beginStep();
    for (var face = 0; face < 3; face++) {
      projectUv(mesh, <int>[face], UvProjection.box);
    }
    mesh.setEdgeFlag(_halfEdgeFromTo(mesh, 0, 1, 2), EdgeFlags.seam, on: true);
    mesh.endStep();

    final overlay = _overlay();
    expect(overlay.isActive, isFalse);
    emitUvSeamOverlay(overlay, mesh);

    // One seam edge, drawn as one ribbon — [MeshOverlay.ribbon]'s own quad
    // of two triangles, six vertices — into the same batch a selected edge
    // already draws into, not a new one.
    expect(overlay.handles.vertexCount, 6);
    expect(overlay.lines.isEmpty, isTrue);
    expect(overlay.isActive, isTrue);
  });

  test('an unflagged UV discontinuity is still a seam', () {
    final mesh = EditMesh.cuboid();
    for (var face = 0; face < 6; face++) {
      mesh.beginStep();
      projectUv(mesh, <int>[face], UvProjection.box);
      mesh.endStep();
    }
    // Every face of a box projected independently disagrees with its own
    // neighbours in UV space — six unrelated little squares — so this is
    // also where `uvSeamEdges`' implicit, unflagged branch is exercised:
    // every internal edge of the cube is a seam despite nothing ever calling
    // `setEdgeFlag`.
    final seams = uvSeamEdges(mesh);
    expect(seams, hasLength(mesh.edgeCount));
  });

  test(
    'uvStretchColor is neutral at 1.0 and saturates at and above severe',
    () {
      expect(uvStretchColor(1.0), kUvNeutralColor);
      expect(uvStretchColor(0.4), kUvNeutralColor); // compression reads neutral
      expect(uvStretchColor(2.5), kUvMaxStretchColor);
      expect(uvStretchColor(50.0), kUvMaxStretchColor);
      expect(uvStretchColor(double.nan), kUvNeutralColor);

      final midway = uvStretchColor(1.75); // halfway to severe = 2.5
      expect(midway, isNot(kUvNeutralColor));
      expect(midway, isNot(kUvMaxStretchColor));
    },
  );
}
