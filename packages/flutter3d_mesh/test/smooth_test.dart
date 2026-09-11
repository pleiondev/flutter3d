/// Averaging vertex positions toward their neighbours, without hollowing the
/// mesh out.
///
///     dart test test/smooth_test.dart
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// Runs [body] as one step of history.
void edit(EditMesh mesh, void Function() body) {
  mesh.beginStep();
  body();
  mesh.endStep();
}

Selection allVertices(EditMesh mesh) => Selection.of(ElementLevel.vertex, <int>[
  for (var v = 0; v < mesh.vertexSlotCount; v++)
    if (mesh.isVertexAlive(v)) v,
]);

/// The mean distance from every live vertex to their shared centroid — the
/// sphere's own effective radius, measured rather than assumed.
double meanRadius(EditMesh mesh) {
  final ids = <int>[
    for (var v = 0; v < mesh.vertexSlotCount; v++)
      if (mesh.isVertexAlive(v)) v,
  ];
  final centroid = Vector3.zero();
  for (final v in ids) {
    centroid.add(mesh.positionOf(v));
  }
  centroid.scale(1 / ids.length);
  var total = 0.0;
  for (final v in ids) {
    total += (mesh.positionOf(v) - centroid).length;
  }
  return total / ids.length;
}

void main() {
  group('smoothVertices', () {
    test('10 iterations with preserveVolume shrink a sphere by under 5%', () {
      final mesh = const ParametricSphere(
        radius: 1,
        segments: 16,
        rings: 8,
      ).toEditMesh();
      final before = meanRadius(mesh);

      edit(
        mesh,
        () => smoothVertices(
          mesh,
          allVertices(mesh),
          iterations: 10,
          preserveVolume: true,
        ),
      );
      mesh.validate();

      final after = meanRadius(mesh);
      // Mutation: skip the HC correction whenever `preserveVolume` is true
      // (fall through to the plain average unconditionally) — ten plain
      // Laplacian passes shrink a sphere this coarse by well over 5%, which
      // is the whole reason `preserveVolume` exists rather than a footnote.
      expect((before - after) / before, lessThan(0.05));
    });

    test('without preserveVolume, the same ten passes shrink it far more', () {
      final mesh = const ParametricSphere(
        radius: 1,
        segments: 16,
        rings: 8,
      ).toEditMesh();
      final before = meanRadius(mesh);

      edit(mesh, () => smoothVertices(mesh, allVertices(mesh), iterations: 10));

      final after = meanRadius(mesh);
      // Not a specific number — just confirms the HC correction in the test
      // above is doing real work, rather than the sphere already shrinking
      // by under 5% either way regardless of it.
      expect((before - after) / before, greaterThan(0.05));
    });

    test('topology is untouched: same vertices, edges and faces', () {
      final mesh = const ParametricSphere(
        radius: 1,
        segments: 16,
        rings: 8,
      ).toEditMesh();
      final v = mesh.vertexCount;
      final e = mesh.edgeCount;
      final f = mesh.faceCount;

      edit(
        mesh,
        () => smoothVertices(
          mesh,
          allVertices(mesh),
          iterations: 10,
          preserveVolume: true,
        ),
      );

      // Mutation: add or remove a vertex or face anywhere in smoothVertices
      // — nothing here is meant to touch topology at all, only positions.
      expect(mesh.vertexCount, v);
      expect(mesh.edgeCount, e);
      expect(mesh.faceCount, f);
    });

    test('no selection is refused rather than a silent no-op', () {
      final mesh = const ParametricSphere().toEditMesh();
      late OpResult result;
      edit(mesh, () {
        result = smoothVertices(
          mesh,
          Selection.empty(ElementLevel.vertex),
          iterations: 5,
        );
      });
      expect(result.reason, contains('no vertices'));
    });

    test('fewer than one iteration is refused', () {
      final mesh = const ParametricSphere().toEditMesh();
      late OpResult result;
      edit(mesh, () {
        result = smoothVertices(mesh, allVertices(mesh), iterations: 0);
      });
      expect(result.reason, contains('one iteration'));
    });

    test('a lone vertex with no neighbours is left exactly where it is', () {
      final mesh = EditMesh.empty();
      edit(mesh, () => mesh.addVertex(Vector3(1, 2, 3)));
      late OpResult result;
      edit(
        mesh,
        () => result = smoothVertices(
          mesh,
          Selection.of(ElementLevel.vertex, <int>[0]),
          iterations: 5,
          preserveVolume: true,
        ),
      );
      expect(result.ok, isTrue);
      expect(mesh.positionOf(0), Vector3(1, 2, 3));
    });
  });
}
