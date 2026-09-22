/// A polyline's geometry, laid out for the `PolylineVertex` stage — `gfx-86n`.
///
/// **Built once, not per frame.** A line of constant screen width has its
/// edges wherever the camera puts them, and `MeshOverlay.ribbon` finds them on
/// the CPU, which rebuilds the whole band every time the camera moves — fine
/// for the edges of a selected face, and a rebuild per frame for a route of
/// tens of thousands of points. Here every point is written twice with what the
/// vertex stage needs to find the edges itself, and a camera move is a uniform.
///
/// **What goes where**, because the engine lays out one vertex format and this
/// repacks it (`polyline.vert` says the same from the other side):
///
///  * position — the point;
///  * normal — the point before it, or itself at the start;
///  * texcoord — the distance along the line in metres, and 0 or 1 for the side;
///  * tangent — the point after it, or itself at the end, and in w the half
///    width in pixels, negative on one side;
///  * colour — the colour at this point.
///
/// One draw for the whole line, joined: consecutive segments share the two
/// vertices at the point between them, which is what closes the elbow
/// instead of leaving the gap two independent quads leave.
library;

import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'mesh_data.dart';
import 'vertex_layout.dart';

/// [points] as one band [width] pixels across, coloured per point.
///
/// [colours] is one colour per point and blends along each segment — the
/// gradient a slope or a speed is drawn with. Leave it out and every point is
/// [colour].
///
/// Throws [ArgumentError] for fewer than two points, or a colour list of the
/// wrong length: a line with one point has no direction to be widened across,
/// and colours that do not line up with points would shift the gradient along
/// the route without anything looking broken.
MeshData buildPolyline(
  List<Vector3> points, {
  required double width,
  List<Vector4>? colours,
  Vector4? colour,
}) {
  if (points.length < 2) {
    throw ArgumentError(
      'A polyline needs at least two points; ${points.length} were given.',
    );
  }
  if (colours != null && colours.length != points.length) {
    throw ArgumentError(
      '${colours.length} colours for ${points.length} points. One colour per '
      'point, in the same order.',
    );
  }
  if (!(width > 0)) {
    throw ArgumentError('A line is wider than nothing; $width was given.');
  }

  final stride = VertexLayout.standard.floatsPerVertex;
  final vertices = Float32List(points.length * 2 * stride);
  final fallback = colour ?? Vector4(1, 1, 1, 1);
  final half = width / 2;

  var distance = 0.0;
  for (var i = 0; i < points.length; i++) {
    final here = points[i];
    final before = points[i == 0 ? 0 : i - 1];
    final after = points[i == points.length - 1 ? i : i + 1];
    if (i > 0) distance += here.distanceTo(before);
    final tint = colours?[i] ?? fallback;

    for (var side = 0; side < 2; side++) {
      final at = (i * 2 + side) * stride;
      vertices
        ..[at] = here.x
        ..[at + 1] = here.y
        ..[at + 2] = here.z
        ..[at + 3] = before.x
        ..[at + 4] = before.y
        ..[at + 5] = before.z
        ..[at + 6] = distance
        ..[at + 7] = side.toDouble()
        ..[at + 8] = after.x
        ..[at + 9] = after.y
        ..[at + 10] = after.z
        ..[at + 11] = side == 0 ? -half : half
        ..[at + 12] = tint.x
        ..[at + 13] = tint.y
        ..[at + 14] = tint.z
        ..[at + 15] = tint.w;
    }
  }

  // Two triangles per segment, sharing the pair of vertices at each point.
  final indices = Uint32List((points.length - 1) * 6);
  for (var i = 0; i < points.length - 1; i++) {
    final a = i * 2;
    indices.setRange(i * 6, i * 6 + 6, <int>[
      a,
      a + 1,
      a + 2,
      a + 1,
      a + 3,
      a + 2,
    ]);
  }

  return MeshData(
    layout: VertexLayout.standard,
    vertices: vertices,
    indices: indices,
  );
}
