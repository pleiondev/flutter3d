/// `projectBrush` — `pro-pt-02`: a brush measured in three dimensions,
/// answered as runs of texels.
///
///     dart test test/paint_project_test.dart
library;

import 'package:flutter3d_core/geometry.dart' show TriangleBvh;
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// Two quads that touch along `x = 1` in space and are *apart* in the UV
/// layout: the left one takes `u` 0..0.4 and the right one 0.6..1. A brush
/// on the join has to paint both, and nothing in the gap between them.
({EditMesh mesh, TriangleBvh surface}) seamed() {
  final builder = EditMeshBuilder();
  builder
    ..addVertex(Vector3(0, 0, 0))
    ..addVertex(Vector3(1, 0, 0))
    ..addVertex(Vector3(1, 1, 0))
    ..addVertex(Vector3(0, 1, 0))
    ..addVertex(Vector3(2, 0, 0))
    ..addVertex(Vector3(2, 1, 0));
  final int left = builder.addFace(<int>[0, 1, 2, 3]);
  final int right = builder.addFace(<int>[1, 4, 5, 2]);
  final EditMesh mesh = builder.build();

  const Map<int, List<double>> leftUv = <int, List<double>>{
    0: <double>[0.0, 0.0],
    1: <double>[0.4, 0.0],
    2: <double>[0.4, 1.0],
    3: <double>[0.0, 1.0],
  };
  const Map<int, List<double>> rightUv = <int, List<double>>{
    1: <double>[0.6, 0.0],
    4: <double>[1.0, 0.0],
    5: <double>[1.0, 1.0],
    2: <double>[0.6, 1.0],
  };

  mesh.beginStep();
  for (final (int face, Map<int, List<double>> uvs)
      in <(int, Map<int, List<double>>)>[(left, leftUv), (right, rightUv)]) {
    mesh.forEachHalfEdge(face, (int he) {
      final List<double> uv = uvs[mesh.originOf(he)]!;
      mesh.setUv(he, Vector2(uv[0], uv[1]));
    });
  }
  mesh.endStep();
  mesh.clearJournal();
  return (mesh: mesh, surface: surfaceOf(mesh));
}

void main() {
  group('a brush on a seam', () {
    test('paints both islands', () {
      final (:mesh, :surface) = seamed();
      final List<UvSpan> spans = projectBrush(
        mesh: mesh,
        surface: surface,
        // On the join, in space.
        centre: Vector3(1, 0.5, 0),
        radius: 0.3,
        size: 64,
      );

      var onLeft = 0;
      var onRight = 0;
      for (final UvSpan span in spans) {
        for (var x = span.x0; x <= span.x1; x++) {
          // The texel's own centre, which is where the rasterizer samples:
          // u = 0.4 falls at 25.6 and u = 0.6 at 38.4, so texel 25 is the
          // left island's last and texel 38 is the right island's first.
          final double u = (x + 0.5) / 64;
          if (u < 0.4) onLeft++;
          if (u > 0.6) onRight++;
        }
      }
      // **The row's own acceptance.** Mutation: draw a circle in UV space
      // instead. The two islands are far apart in the layout, so one of
      // these counts would be zero and a stroke over a seam would leave
      // half of itself unpainted — the defect every texture painter is
      // judged by.
      expect(onLeft, greaterThan(0));
      expect(onRight, greaterThan(0));
    });

    test('and nothing in the gap between them', () {
      final (:mesh, :surface) = seamed();
      final List<UvSpan> spans = projectBrush(
        mesh: mesh,
        surface: surface,
        centre: Vector3(1, 0.5, 0),
        radius: 0.3,
        size: 64,
      );
      for (final UvSpan span in spans) {
        for (var x = span.x0; x <= span.x1; x++) {
          // The strip between u = 0.4 and u = 0.6 is on neither island, and
          // a circle in UV space would have walked straight through it.
          final double u = (x + 0.5) / 64;
          expect(u > 0.4 && u < 0.6, isFalse, reason: 'x=$x');
        }
      }
    });
  });

  group('the ball', () {
    test('leaves texels outside the 3D radius untouched', () {
      final (:mesh, :surface) = seamed();
      final List<UvSpan> spans = projectBrush(
        mesh: mesh,
        surface: surface,
        centre: Vector3(0.5, 0.5, 0),
        radius: 0.2,
        size: 64,
      );
      expect(spans, isNotEmpty);
      // The brush is at u ≈ 0.2 on the left island; nothing on the right
      // island is within 0.2 of it in space.
      for (final UvSpan span in spans) {
        expect((span.x1 + 0.5) / 64, lessThan(0.4));
      }
    });

    test('and the weight falls off from the middle', () {
      final (:mesh, :surface) = seamed();
      final List<UvSpan> spans = projectBrush(
        mesh: mesh,
        surface: surface,
        centre: Vector3(0.5, 0.5, 0),
        radius: 0.3,
        size: 64,
      );
      var strongest = 0.0;
      var weakest = 1.0;
      for (final UvSpan span in spans) {
        for (final double weight in span.weights) {
          if (weight > strongest) strongest = weight;
          if (weight < weakest) weakest = weight;
        }
      }
      expect(strongest, greaterThan(0.9));
      expect(weakest, lessThan(0.5));
    });

    test('a radius of nothing paints nothing', () {
      final (:mesh, :surface) = seamed();
      expect(
        projectBrush(
          mesh: mesh,
          surface: surface,
          centre: Vector3(0.5, 0.5, 0),
          radius: 0,
          size: 64,
        ),
        isEmpty,
      );
    });

    test('and a brush nowhere near the mesh paints nothing', () {
      final (:mesh, :surface) = seamed();
      expect(
        projectBrush(
          mesh: mesh,
          surface: surface,
          centre: Vector3(50, 50, 50),
          radius: 0.3,
          size: 64,
        ),
        isEmpty,
      );
    });
  });

  group('the spans', () {
    test('are runs of neighbouring texels, in order', () {
      final (:mesh, :surface) = seamed();
      final List<UvSpan> spans = projectBrush(
        mesh: mesh,
        surface: surface,
        centre: Vector3(0.5, 0.5, 0),
        radius: 0.3,
        size: 64,
      );
      expect(spans, isNotEmpty);
      for (final UvSpan span in spans) {
        expect(span.x1, greaterThanOrEqualTo(span.x0));
        expect(span.weights, hasLength(span.x1 - span.x0 + 1));
      }
      for (var i = 1; i < spans.length; i++) {
        final bool ordered =
            spans[i].y > spans[i - 1].y ||
            (spans[i].y == spans[i - 1].y && spans[i].x0 > spans[i - 1].x1);
        expect(ordered, isTrue);
      }
      expect(texelsIn(spans), greaterThan(0));
    });
  });
}
