/// Polygons with attributes per point or per corner, triangulated into the
/// engine's vertex layout — what a PLY face list and a USD `Mesh` prim both
/// are.
library;

import 'package:flutter3d_core/geometry.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:vector_math/vector_math.dart';
import '../build_exceptions.dart';

/// Where an attribute's values sit.
final class AttributeRate {
  const AttributeRate._(this.name);

  final String name;

  /// One value per point, shared by every corner on it.
  static const AttributeRate point = AttributeRate._('point');

  /// One value per polygon corner, in face order.
  static const AttributeRate corner = AttributeRate._('corner');

  /// One value per polygon.
  static const AttributeRate face = AttributeRate._('face');

  /// One value for the whole mesh.
  static const AttributeRate constant = AttributeRate._('constant');
}

/// One attribute: values, where they sit, and an optional index list into
/// them (USD's `primvars:st:indices`).
final class PolygonAttribute<T> {
  const PolygonAttribute(this.values, this.rate, {this.indices});

  final List<T> values;
  final AttributeRate rate;
  final List<int>? indices;

  /// The value for [point], corner number [corner] and face [face].
  T? at({required int point, required int corner, required int face}) {
    final slot = switch (rate) {
      AttributeRate.point => point,
      AttributeRate.corner => corner,
      AttributeRate.face => face,
      _ => 0,
    };
    final index = indices == null
        ? slot
        : (slot < indices!.length ? indices![slot] : -1);
    return index >= 0 && index < values.length ? values[index] : null;
  }
}

/// Polygons over [points]: [counts] corners each, their point numbers in
/// [indices].
final class PolygonMesh {
  const PolygonMesh({
    required this.points,
    required this.counts,
    required this.indices,
    this.normals,
    this.uvs,
    this.colors,
    this.flipWinding = false,
  });

  final List<Vector3> points;
  final List<int> counts;
  final List<int> indices;
  final PolygonAttribute<Vector3>? normals;
  final PolygonAttribute<Vector2>? uvs;
  final PolygonAttribute<Vector4>? colors;

  /// Whether the source winds its front faces clockwise — USD's
  /// `orientation = "leftHanded"`.
  final bool flipWinding;

  int get triangleCount {
    var total = 0;
    for (final n in counts) {
      if (n >= 3) total += n - 2;
    }
    return total;
  }

  /// The mesh in [VertexLayout.standard], each polygon a fan from its first
  /// corner. Points are shared when every attribute is per point; otherwise
  /// each corner gets a vertex of its own. Normals the source does not give
  /// are the average of the faces around a point.
  ///
  /// Throws [SourceFormatException] for an index outside [points].
  MeshData build() {
    final shared = _perPoint(normals) && _perPoint(uvs) && _perPoint(colors);
    final smooth = normals == null ? _smoothNormals() : null;
    final builder = MeshBuilder(
      VertexLayout.standard,
      reserveVertices: shared ? points.length : indices.length,
      reserveIndices: triangleCount * 3,
    );

    int emit(int point, int corner, int face) => builder.addVertex(
      position: points[point],
      normal:
          normals?.at(point: point, corner: corner, face: face) ??
          smooth?[point] ??
          Vector3(0.0, 1.0, 0.0),
      texcoord:
          uvs?.at(point: point, corner: corner, face: face) ?? Vector2.zero(),
      // A vertex colour is linear, and the file's numbers are taken as such.
      color: switch (colors?.at(point: point, corner: corner, face: face)) {
        final c? => LinearColor(c.x, c.y, c.z, c.w),
        null => null,
      },
    );

    if (shared) {
      for (var p = 0; p < points.length; p++) {
        emit(p, 0, 0);
      }
    }
    var corner = 0;
    for (var face = 0; face < counts.length; face++) {
      final n = counts[face];
      final first = corner;
      corner += n;
      if (n < 3) continue;
      final vertex = <int>[
        for (var k = 0; k < n; k++)
          () {
            final point = indices[first + k];
            if (point < 0 || point >= points.length) {
              throw SourceFormatException(
                'face $face names point $point of ${points.length}',
              );
            }
            return shared ? point : emit(point, first + k, face);
          }(),
      ];
      for (var k = 1; k + 1 < n; k++) {
        if (flipWinding) {
          builder.addTriangle(vertex[0], vertex[k + 1], vertex[k]);
        } else {
          builder.addTriangle(vertex[0], vertex[k], vertex[k + 1]);
        }
      }
    }
    return builder.build();
  }

  static bool _perPoint(PolygonAttribute<Object>? a) =>
      a == null ||
      a.rate == AttributeRate.point ||
      a.rate == AttributeRate.constant;

  List<Vector3> _smoothNormals() {
    final sums = List<Vector3>.generate(points.length, (_) => Vector3.zero());
    var corner = 0;
    for (final n in counts) {
      if (n >= 3 && corner + n <= indices.length) {
        final a = indices[corner];
        for (var k = 1; k + 1 < n; k++) {
          final b = indices[corner + k];
          final c = indices[corner + k + 1];
          if (a < 0 || b < 0 || c < 0) continue;
          if (a >= points.length || b >= points.length || c >= points.length) {
            continue;
          }
          final normal = (points[b] - points[a]).cross(points[c] - points[a]);
          if (flipWinding) normal.negate();
          sums[a].add(normal);
          sums[b].add(normal);
          sums[c].add(normal);
        }
      }
      corner += n;
    }
    return <Vector3>[
      for (final s in sums)
        s.length2 > 0.0 ? s.normalized() : Vector3(0.0, 1.0, 0.0),
    ];
  }
}
