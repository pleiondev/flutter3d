import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/geometry.dart';
import 'package:test/test.dart';

/// [mesh] with its triangles in a fixed, seeded-random order — the same
/// vertices and triangles, but with the locality a shape generator's own
/// raster order already has thrown away.
///
/// **Why the ACMR test needs this and the topology test does not.** A shape
/// generator that emits a sphere row by row already lays triangles out close
/// to how a strip would — real cache-friendliness a generic reorder pass can
/// struggle to beat rather than only match. A file `GltfWriter` actually
/// compresses came from somewhere else — modelling software, another
/// exporter — with no such guarantee, so scrambling first is what makes the
/// "before" side of the comparison the input this pass exists for, not the
/// one case already stacked in its favour.
MeshData _scrambleTriangleOrder(MeshData mesh, int seed) {
  final triangleCount = mesh.triangleCount;
  final order = List<int>.generate(triangleCount, (t) => t);
  final random = math.Random(seed);
  for (var i = order.length - 1; i > 0; i--) {
    final j = random.nextInt(i + 1);
    final tmp = order[i];
    order[i] = order[j];
    order[j] = tmp;
  }
  final indices = Uint32List(mesh.indices.length);
  for (var t = 0; t < triangleCount; t++) {
    final from = order[t] * 3;
    final to = t * 3;
    indices[to] = mesh.indices[from];
    indices[to + 1] = mesh.indices[from + 1];
    indices[to + 2] = mesh.indices[from + 2];
  }
  return MeshData(
    layout: mesh.layout,
    vertices: mesh.vertices,
    indices: indices,
  );
}

/// The triangles of [mesh], each as its three vertices' full attribute
/// floats in winding order — what a comparison that must not care which byte
/// offset a vertex landed at needs to look at instead of the raw buffers.
List<List<Float32List>> _triangles(MeshData mesh) {
  final stride = mesh.layout.floatsPerVertex;
  Float32List vertexAt(int v) =>
      Float32List.sublistView(mesh.vertices, v * stride, v * stride + stride);
  return [
    for (var t = 0; t < mesh.triangleCount; t++)
      [
        vertexAt(mesh.indices[t * 3]),
        vertexAt(mesh.indices[t * 3 + 1]),
        vertexAt(mesh.indices[t * 3 + 2]),
      ],
  ];
}

bool _sameVertex(Float32List a, Float32List b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Whether [a] and [b] are the same triangle: the same three vertices, in the
/// same winding, allowing the three to start at a different corner —
/// `(v0,v1,v2)` and `(v1,v2,v0)` draw identically, `(v0,v2,v1)` does not.
bool _sameTriangle(List<Float32List> a, List<Float32List> b) {
  for (var rotation = 0; rotation < 3; rotation++) {
    if (_sameVertex(a[0], b[rotation]) &&
        _sameVertex(a[1], b[(rotation + 1) % 3]) &&
        _sameVertex(a[2], b[(rotation + 2) % 3])) {
      return true;
    }
  }
  return false;
}

/// Whether [reordered] draws exactly the triangles [original] does — the same
/// multiset, winding preserved, regardless of which order they come in or
/// which index numbers their corners now carry.
void _expectSameTriangleSet(MeshData original, MeshData reordered) {
  final a = _triangles(original);
  final b = _triangles(reordered);
  expect(
    b.length,
    a.length,
    reason: 'reordering must not add or drop a triangle',
  );
  final matched = List<bool>.filled(b.length, false);
  for (final triangle in a) {
    final found = _firstUnmatched(b, matched, triangle);
    expect(
      found,
      isNotNull,
      reason: 'a source triangle has no match in the reordered mesh',
    );
    matched[found!] = true;
  }
}

int? _firstUnmatched(
  List<List<Float32List>> candidates,
  List<bool> matched,
  List<Float32List> triangle,
) {
  for (var i = 0; i < candidates.length; i++) {
    if (matched[i]) continue;
    if (_sameTriangle(triangle, candidates[i])) return i;
  }
  return null;
}

void main() {
  group('optimizeVertexCache', () {
    final shapes = <String, MeshData>{
      'sphere': const SphereShape(segments: 24, rings: 12).build(),
      'torus': const TorusShape().build(),
      'box': CuboidShape().build(),
    };

    shapes.forEach((name, mesh) {
      test('$name: same triangles, same winding, after reordering', () {
        final reordered = optimizeVertexCache(mesh);
        expect(reordered.vertexCount, mesh.vertexCount);
        expect(reordered.triangleCount, mesh.triangleCount);
        _expectSameTriangleSet(mesh, reordered);
      });
    });

    // Only the two shapes whose vertices are actually shared across many
    // triangles: a flat-shaded box gives each corner its own normal per
    // face, so no vertex is used by more than the two triangles of its own
    // face — already adjacent in any generation order — and 2.0 (one
    // mandatory miss per vertex, no more) is the ACMR floor no reordering
    // can beat. Asserting improvement against a mesh with no room for it
    // would be the "loosely widened until it passes" this session does not
    // ship, in the other direction.
    for (final name in ['sphere', 'torus']) {
      test('$name: lowers the average cache miss ratio', () {
        final mesh = _scrambleTriangleOrder(shapes[name]!, 7);
        final reordered = optimizeVertexCache(mesh);
        final before = averageCacheMissRatio(mesh.indices);
        final after = averageCacheMissRatio(reordered.indices);
        // ignore: avoid_print — the improvement is the point of this test.
        print('$name ACMR: $before -> $after');
        expect(
          after,
          lessThan(before),
          reason: 'reordering should not make cache reuse worse',
        );
        // The floor of a real FIFO cache large enough to hold a full
        // triangle fan is close to 0.5 (six triangles share most vertices on
        // these shapes); a naive fan/grid order most shape generators emit
        // is nowhere near that, so a real reorder should close most of the
        // gap, not shave a rounding error off it.
        expect(after, lessThan(1.0));
      });
    }

    test('a mesh with a morph target keeps its deltas on the same vertex', () {
      final mesh = CuboidShape().build();
      final displaced = Float32List(
        mesh.vertices.length ~/ mesh.layout.floatsPerVertex * 3,
      );
      for (var v = 0; v < mesh.vertexCount; v++) {
        // A distinctive, per-vertex delta: vertex `v`'s displacement encodes
        // its own index, so a delta that ends up on the wrong vertex after
        // reordering is one this test can name rather than merely detect.
        displaced[v * 3] = v.toDouble();
      }
      final withTarget = mesh.withMorphTargets([
        MorphTarget(vertexCount: mesh.vertexCount, positions: displaced),
      ]);

      final reordered = optimizeVertexCache(withTarget);

      // A cuboid duplicates a corner's position across its three faces (one
      // vertex per face, each with that face's own normal/UV), so position
      // alone does not name a vertex — the full attribute row does, since
      // reordering carries every float of a vertex to its new slot together.
      final originalIndexOf = <String, int>{
        for (var v = 0; v < mesh.vertexCount; v++) _vertexKey(mesh, v): v,
      };

      for (var v = 0; v < reordered.vertexCount; v++) {
        final key = _vertexKey(reordered, v);
        final originalIndex = originalIndexOf[key];
        expect(originalIndex, isNotNull);
        final delta = reordered.morphTargets.first.positions[v * 3];
        expect(delta, originalIndex!.toDouble());
      }
    });

    test('an empty mesh is returned unchanged', () {
      final empty = MeshData(
        layout: VertexLayout.positionOnly,
        vertices: Float32List(0),
        indices: Uint32List(0),
      );
      expect(identical(optimizeVertexCache(empty), empty), isTrue);
    });
  });
}

String _vertexKey(MeshData mesh, int vertex) {
  final stride = mesh.layout.floatsPerVertex;
  final start = vertex * stride;
  return mesh.vertices.sublist(start, start + stride).join(',');
}
