/// Writing vertices of [VertexLayout.standard] by hand, for the meshes the
/// views rewrite every frame.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:vector_math/vector_math.dart';

/// Floats a vertex of [VertexLayout.standard] takes: position, normal,
/// texture coordinate, tangent and colour.
const int vertexFloats = 3 + 3 + 2 + 4 + 4;

/// Writes vertex [index] of [into]: at [at], facing [normal], coloured
/// [color], with the texture coordinate [uv] and a tangent along x.
void writeVertex(
  Float32List into,
  int index,
  Vector3 at,
  Vector3 normal,
  Vector4 color, {
  (double, double) uv = (0.0, 0.0),
}) {
  final o = index * vertexFloats;
  into[o] = at.x;
  into[o + 1] = at.y;
  into[o + 2] = at.z;
  into[o + 3] = normal.x;
  into[o + 4] = normal.y;
  into[o + 5] = normal.z;
  into[o + 6] = uv.$1;
  into[o + 7] = uv.$2;
  into[o + 8] = 1.0;
  into[o + 9] = 0.0;
  into[o + 10] = 0.0;
  into[o + 11] = 1.0;
  into[o + 12] = color.x;
  into[o + 13] = color.y;
  into[o + 14] = color.z;
  into[o + 15] = color.w;
}

/// The triangles of a grid of [nx] × [nz] vertices, x fastest.
Uint32List gridTriangles(int nx, int nz) => Uint32List.fromList(<int>[
  for (var j = 0; j < nz - 1; j++)
    for (var i = 0; i < nx - 1; i++) ...<int>[
      i + j * nx,
      i + (j + 1) * nx,
      i + 1 + j * nx,
      i + 1 + j * nx,
      i + (j + 1) * nx,
      i + 1 + (j + 1) * nx,
    ],
]);

/// The triangles of [quads] quads of four vertices each, a quad's own.
Uint32List quadTriangles(int quads) => Uint32List.fromList(<int>[
  for (var q = 0; q < quads; q++) ...<int>[
    q * 4,
    q * 4 + 1,
    q * 4 + 2,
    q * 4 + 2,
    q * 4 + 1,
    q * 4 + 3,
  ],
]);
