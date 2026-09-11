/// `StlWriter`: `fmt-20`'s own row — decode, write, decode again, and
/// compare the facet positions. Not through `compareModelDocuments`: its own
/// count checks on materials/images/nodes return before ever reaching
/// geometry, and a bare triangle soup fails every one of them on the way in
/// from a real glTF. `_facetPositionsOf` below is what is left to ask.
///
///     dart test test/stl_writer_test.dart
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// The Khronos sample assets live in `flutter3d_samples`, a sibling package —
/// read straight off disk by relative path rather than declared as a
/// dependency, since that package pulls the Flutter SDK in for its
/// `flutter.assets` block and this one is not allowed to — the same reason
/// `gltf_writer_test.dart` reads it this way.
Uint8List _sample(String relativePath) =>
    File('../flutter3d_samples/assets/$relativePath').readAsBytesSync();

String _round3(MeshData mesh, int vertex) {
  final int stride = mesh.layout.floatsPerVertex;
  final int o = vertex * stride;
  String round(double v) => v.toStringAsFixed(4);
  return '${round(mesh.vertices[o])},${round(mesh.vertices[o + 1])},'
      '${round(mesh.vertices[o + 2])}';
}

/// Every *facet corner* position in [mesh], rounded to kill float noise, as
/// a multiset — not [MeshData.vertexCount]'s own list. STL shares no vertex
/// between facets, so a mesh whose faces share a corner (Box.glb's own quads
/// split into two triangles each) writes that corner's position twice, once
/// per triangle it is part of; [mesh]'s own vertex list has it once. Walking
/// [MeshData.indices] in triples, the way `StlWriter._facets` does, is what
/// actually produces the 36-entry shape a round trip through STL has to
/// match, not the 24 [mesh] itself carries for the same box.
///
/// `compareModelDocuments` cannot be asked here at all: its own count checks
/// on materials/images/nodes/animations return before ever comparing
/// geometry (see its own doc comment), and Box.glb has one of the first and
/// two of the third against STL's zero of both. A position multiset is what
/// is left to ask a bare triangle soup about.
List<String> _facetPositionsOf(MeshData mesh) => <String>[
  for (var t = 0; t + 2 < mesh.indices.length; t += 3) ...<String>[
    _round3(mesh, mesh.indices[t]),
    _round3(mesh, mesh.indices[t + 1]),
    _round3(mesh, mesh.indices[t + 2]),
  ],
]..sort();

/// [surface]'s own mesh, with its transform applied — the same bake
/// `StlWriter` does, kept here independently so the test states what it
/// expects rather than reusing the writer's own private method.
MeshData _bake(ModelSurface surface) => surface.transform.isIdentity()
    ? surface.mesh
    : surface.mesh.transformed(surface.transform);

void main() {
  group('fmt-20\'s own acceptance: Box.glb through StlWriter', () {
    test('12 triangles, and a binary file of exactly 84 + 50 * count bytes', () async {
      final source = await GltfLoader().load(_sample('Box.glb'));
      final bytes = StlWriter(source).write();

      // Mutation: write an extra byte anywhere, or drop one facet's own 50 —
      // this is the row's own size formula, checked as arithmetic rather than
      // trusted from the byte count alone.
      expect(bytes.length, 84 + 50 * 12);
      expect(isBinaryStl(bytes), isTrue);

      final readBack = await StlLoader().load(bytes);
      expect(readBack.surfaces.single.mesh.indices.length ~/ 3, 12);
    });

    test('the binary round trip holds exactly — a transform baked in, not '
        'dropped', () async {
      final source = await GltfLoader().load(_sample('Box.glb'));
      final expected = _facetPositionsOf(_bake(source.surfaces.single));

      // Mutation: skip `_bake` and write `surface.mesh` unmoved — Box.glb's
      // own root node is not the identity, so this would still produce 12
      // triangles, all at the untransformed positions, which only a
      // position comparison — not a triangle count — can catch.
      final bytes = StlWriter(source).write();
      final readBack = await StlLoader().load(bytes);
      expect(_facetPositionsOf(readBack.surfaces.single.mesh), expected);
    });

    test('the ASCII round trip holds exactly too', () async {
      final source = await GltfLoader().load(_sample('Box.glb'));
      final expected = _facetPositionsOf(_bake(source.surfaces.single));

      final bytes = StlWriter(source).writeAscii();
      expect(looksLikeAsciiStl(bytes), isTrue);

      final readBack = await StlLoader().load(bytes);
      expect(_facetPositionsOf(readBack.surfaces.single.mesh), expected);
    });
  });

  group('a mirrored transform', () {
    /// One triangle, `(0,0,0)`, `(1,0,0)`, `(0,1,0)` — wound so its own
    /// untransformed normal is `(0, 0, 1)`.
    PlainModelDocument mirroredTriangle() {
      final builder = MeshBuilder(VertexLayout.standard);
      final int i0 = builder.addVertex(position: Vector3(0, 0, 0));
      final int i1 = builder.addVertex(position: Vector3(1, 0, 0));
      final int i2 = builder.addVertex(position: Vector3(0, 1, 0));
      builder.addTriangle(i0, i1, i2);
      return PlainModelDocument(
        surfaces: <ModelSurface>[
          ModelSurface(
            mesh: builder.build(),
            // Negative determinant: the shape ObjWriter's own `reversed`
            // check (and this writer's) reads off the baked matrix.
            transform: Matrix4.diagonal3Values(-1, 1, 1),
          ),
        ],
      );
    }

    test('flips the written winding, not only the positions', () async {
      final bytes = StlWriter(mirroredTriangle()).write();
      final readBack = await StlLoader(
        normals: StlNormals.recomputed,
      ).load(bytes);
      final mesh = readBack.surfaces.single.mesh;
      final int normalOffset = mesh.layout.floatOffsetOf(
        VertexLayout.normal.name,
      );

      // A mirror composed with the matching winding swap reads back the
      // same normal sign the untransformed triangle already had, `(0, 0,
      // 1)` — the standard convention for what "flip winding when a
      // transform mirrors" means, the same one ObjWriter's own `reversed`
      // check exists for.
      //
      // Mutation: drop the `reversed` swap in `StlWriter._facets` — the
      // raw mirrored triangle's own cross product reads `(0, 0, -1)`
      // instead, since nothing corrected for the handedness flip.
      expect(mesh.vertices[normalOffset + 2], closeTo(1.0, 1e-5));
    });

    test('the positions themselves are still the mirrored ones, not the '
        'original triangle', () async {
      final bytes = StlWriter(mirroredTriangle()).write();
      final readBack = await StlLoader().load(bytes);
      final mesh = readBack.surfaces.single.mesh;
      final int stride = mesh.layout.floatsPerVertex;
      final xs = <double>[
        for (var v = 0; v < mesh.vertexCount; v++) mesh.vertices[v * stride],
      ]..sort();
      // Mutation: bake nothing (write `surface.mesh` straight) — the
      // triangle's own x values would be 0, 0, 1 instead of -1, 0, 0.
      expect(xs, <double>[-1.0, 0.0, 0.0]);
    });
  });
}
