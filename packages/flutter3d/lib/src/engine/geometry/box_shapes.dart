import 'package:vector_math/vector_math.dart';

import 'mesh_builder.dart';
import 'mesh_data.dart';
import 'shape.dart';
import 'vertex_layout.dart';

/// Axis-aligned box centred on the origin.
///
/// Uses 24 vertices rather than 8: each face needs its own normal and UV set, and
/// sharing corners would average the normals into something round.
///
/// Named "cuboid" rather than "box" because `flutter/material.dart` exports a
/// `BoxShape` enum, and a clash there would force every app importing both to
/// disambiguate.
class CuboidShape extends Shape {
  CuboidShape({Vector3? size}) : size = size ?? Vector3.all(1.0);

  final Vector3 size;

  @override
  String get name => 'box';

  // Per face: normal, then the U and V axes of the face. cross(u, v) == normal
  // for every entry, which is what makes the shared corner order wind
  // counter-clockwise as seen from outside.
  static const List<List<List<double>>> _faces = <List<List<double>>>[
    [
      [1, 0, 0],
      [0, 0, -1],
      [0, 1, 0],
    ],
    [
      [-1, 0, 0],
      [0, 0, 1],
      [0, 1, 0],
    ],
    [
      [0, 1, 0],
      [1, 0, 0],
      [0, 0, -1],
    ],
    [
      [0, -1, 0],
      [1, 0, 0],
      [0, 0, 1],
    ],
    [
      [0, 0, 1],
      [1, 0, 0],
      [0, 1, 0],
    ],
    [
      [0, 0, -1],
      [-1, 0, 0],
      [0, 1, 0],
    ],
  ];

  static const List<List<double>> _corners = <List<double>>[
    [-1, -1],
    [1, -1],
    [1, 1],
    [-1, 1],
  ];

  @override
  MeshData build({VertexLayout layout = VertexLayout.standard}) {
    final half = size * 0.5;
    final builder = MeshBuilder(
      layout,
      reserveVertices: 24,
      reserveIndices: 36,
    );
    final position = Vector3.zero();
    final normal = Vector3.zero();
    final texcoord = Vector2.zero();

    // Each face's UV axes are declared above, so the tangent is exactly the U
    // axis — no need to recover it from UV differences. cross(u, v) is the
    // normal for every entry, which makes cross(normal, tangent) equal the V
    // axis; glTF wants the bitangent to be *minus* dP/dv, so the sign is -1.
    final tangent = Vector4.zero();

    for (final face in _faces) {
      normal.setValues(face[0][0], face[0][1], face[0][2]);
      final uAxis = face[1];
      final vAxis = face[2];
      tangent.setValues(uAxis[0], uAxis[1], uAxis[2], -1.0);
      final base = builder.vertexCount;

      for (final corner in _corners) {
        final cu = corner[0];
        final cv = corner[1];
        position.setValues(
          (normal.x + uAxis[0] * cu + vAxis[0] * cv) * half.x,
          (normal.y + uAxis[1] * cu + vAxis[1] * cv) * half.y,
          (normal.z + uAxis[2] * cu + vAxis[2] * cv) * half.z,
        );
        texcoord.setValues((cu + 1.0) * 0.5, (cv + 1.0) * 0.5);
        builder.addVertex(
          position: position,
          normal: normal,
          texcoord: texcoord,
          tangent: tangent,
        );
      }

      builder.addQuad(base, base + 1, base + 2, base + 3);
    }

    return builder.build();
  }
}

/// Subdivided plane in the XZ plane, normal pointing at +Y.
class PlaneShape extends Shape {
  const PlaneShape({
    this.width = 1.0,
    this.depth = 1.0,
    this.widthSegments = 1,
    this.depthSegments = 1,
  });

  final double width;
  final double depth;
  final int widthSegments;
  final int depthSegments;

  @override
  String get name => 'plane';

  @override
  MeshData build({VertexLayout layout = VertexLayout.standard}) {
    if (widthSegments < 1 || depthSegments < 1) {
      throw ArgumentError('Plane segment counts must be >= 1.');
    }

    final builder = MeshBuilder(
      layout,
      reserveVertices: (widthSegments + 1) * (depthSegments + 1),
      reserveIndices: widthSegments * depthSegments * 6,
    );
    final normal = Vector3(0.0, 1.0, 0.0);
    final position = Vector3.zero();
    final texcoord = Vector2.zero();
    // U runs along +X and V along +Z, so cross(normal, +X) is -Z, which is
    // already minus dP/dv — the sign is positive.
    final tangent = Vector4(1.0, 0.0, 0.0, 1.0);

    for (var iz = 0; iz <= depthSegments; iz++) {
      final tz = iz / depthSegments;
      for (var ix = 0; ix <= widthSegments; ix++) {
        final tx = ix / widthSegments;
        position.setValues((tx - 0.5) * width, 0.0, (tz - 0.5) * depth);
        texcoord.setValues(tx, tz);
        builder.addVertex(
          position: position,
          normal: normal,
          texcoord: texcoord,
          tangent: tangent,
        );
      }
    }

    final rowStride = widthSegments + 1;
    for (var iz = 0; iz < depthSegments; iz++) {
      for (var ix = 0; ix < widthSegments; ix++) {
        final a = iz * rowStride + ix;
        final b = a + 1;
        final c = a + rowStride + 1;
        final d = a + rowStride;
        // Winding chosen so the front face is the +Y side.
        builder.addQuad(a, d, c, b);
      }
    }

    return builder.build();
  }
}
