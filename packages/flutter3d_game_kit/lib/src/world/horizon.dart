import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

/// The height of a world's drawn ground at `(x, z)`, m.
typedef GroundHeight = double Function(double x, double z);

/// Floats a vertex of [VertexLayout.standard] takes.
const int _stride = 16;

/// How far out each ring of the far floor and the far surface lies past the
/// simulated square, m: close together at the edge, where the eye is near,
/// and kilometres apart where water or haze hides everything anyway.
const List<double> _rings = <double>[
  0,
  2,
  5,
  10,
  18,
  30,
  50,
  85,
  140,
  240,
  420,
  800,
  1500,
];

/// The world past the part of it that is simulated, out to the horizon: the
/// ground going on from the simulated square's edge and falling away to a far
/// depth, and a level surface going on over it, so whoever stands at the
/// edge sees the world fade into the distance rather than end.
///
/// **Two meshes of rings round the square**, close at the edge and kilometres
/// apart further out, each growing straight out from the middle so the rings
/// never cross. The far floor starts at whatever height [ground] gives the
/// drawn ground's outermost vertices — the cells' middles — so the two meet
/// without a seam, and eases down to [farDepth] over a few hundred metres
/// with a slow swell in it, so the far floor is not one flat bowl. The
/// surface is level at nought, and carries the depth under it in its first
/// texture coordinate, as a water look reads it.
///
/// The ground function stays the game's: this asks for heights, and draws
/// whatever terrain answers.
final class Horizon {
  const Horizon({
    required this.size,
    required this.floorCell,
    required this.surfaceCell,
    required this.ground,
    this.farDepth = defaultFarDepth,
  });

  /// How deep the far floor lies unless a game says otherwise, in metres.
  static const double defaultFarDepth = 34.0;

  /// The side of the simulated square, from the origin, m.
  final double size;

  /// The drawn ground's cell, m: its outermost vertices stand at the cells'
  /// middles.
  final double floorCell;

  /// The simulated surface's cell, m.
  final double surfaceCell;

  /// The drawn ground's height, which the far floor starts from.
  final GroundHeight ground;

  /// How deep the far floor lies far from the square, in metres.
  final double farDepth;

  /// The far floor's height at [at], [out] metres past the edge point [edge]
  /// it grew from.
  double floorHeight(Vector3 edge, Vector3 at, double out) {
    final start = ground(edge.x, edge.z);
    // A slow swell in the far floor, so the deep is not one flat bowl.
    final swell = 2.5 * math.sin(at.x * 0.021 + 1.3) * math.cos(at.z * 0.017);
    return start + (-farDepth + swell - start) * _smooth(4, 320, out);
  }

  /// The far floor: textured every three metres, white.
  MeshData floorMesh() {
    final edge = _edge(0.5 * floorCell, size - 0.5 * floorCell, floorCell);
    return _bands(edge, floorHeight, (v, o, at, out) {
      v
        ..[o + 6] = at.z / 3
        ..[o + 7] = at.x / 3
        ..[o + 12] = 1
        ..[o + 13] = 1
        ..[o + 14] = 1
        ..[o + 15] = 1;
    });
  }

  /// The far surface: level, as deep as the floor under it is.
  MeshData surfaceMesh() {
    final edge = _edge(
      0.5 * surfaceCell,
      size - 0.5 * surfaceCell,
      surfaceCell,
    );
    return _bands(edge, (p, at, out) => 0.0, (v, o, at, out) {
      final under = floorHeight(
        Vector3(
          at.x.clamp(0.5 * floorCell, size - 0.5 * floorCell),
          0,
          at.z.clamp(0.5 * floorCell, size - 0.5 * floorCell),
        ),
        at,
        out,
      );
      v
        // A water look reads its first texture coordinate as the depth.
        ..[o + 6] = math.max(-under, 0.5)
        ..[o + 7] = 0
        // Still water, no froth: the flow's two halves at a half, no air.
        ..[o + 12] = 0.5
        ..[o + 13] = 0.5
        ..[o + 14] = 0
        ..[o + 15] = 1;
    });
  }

  /// The far floor in [floor]'s material and the far surface in [surface]'s,
  /// uploaded to [device] and added to [scene] as `far floor` and `far sea`.
  void addTo(
    GraphicsDevice device,
    Scene scene, {
    required RenderMaterial floor,
    required RenderMaterial surface,
  }) {
    scene
      ..add(
        MeshNode(
          DeviceMesh.upload(device, floorMesh()),
          floor,
          name: 'far floor',
        ),
      )
      ..add(
        MeshNode(
          DeviceMesh.upload(device, surfaceMesh()),
          surface,
          name: 'far sea',
        ),
      );
  }
}

/// The points round the edge of the square from [lo] to [hi], every [step]
/// metres, and the way out from each: straight out from the middle, so the
/// rings never cross.
List<(Vector3, Vector3)> _edge(double lo, double hi, double step) {
  final middle = Vector3((lo + hi) / 2, 0, (lo + hi) / 2);
  final n = ((hi - lo) / step).round();
  final points = <Vector3>[
    for (var k = 0; k < n; k++) Vector3(lo + k * step, 0, lo),
    for (var k = 0; k < n; k++) Vector3(hi, 0, lo + k * step),
    for (var k = 0; k < n; k++) Vector3(hi - k * step, 0, hi),
    for (var k = 0; k < n; k++) Vector3(lo, 0, hi - k * step),
  ];
  return <(Vector3, Vector3)>[
    for (final p in points)
      (
        p,
        (p - middle)
          ..y = 0
          ..normalize(),
      ),
  ];
}

double _smooth(double a, double b, double x) {
  final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

/// A ring band mesh round the square: [heightAt] gives each vertex's height
/// from where the edge point it grew from is and how far out it is; [paint]
/// writes the rest of the vertex.
MeshData _bands(
  List<(Vector3, Vector3)> edge,
  double Function(Vector3 edgePoint, Vector3 at, double out) heightAt,
  void Function(Float32List v, int o, Vector3 at, double out) paint,
) {
  final m = edge.length, rings = _rings.length;
  final vertices = Float32List(m * rings * _stride);
  for (var r = 0; r < rings; r++) {
    for (var k = 0; k < m; k++) {
      final (p, out) = edge[k];
      final at = p + out * _rings[r];
      at.y = heightAt(p, at, _rings[r]);
      final o = (k + r * m) * _stride;
      vertices
        ..[o] = at.x
        ..[o + 1] = at.y
        ..[o + 2] = at.z
        ..[o + 8] = 1
        ..[o + 11] = 1;
      paint(vertices, o, at, _rings[r]);
    }
  }
  // Normals from the band's own slopes: along the ring and out across it.
  Vector3 vertex(int k, int r) {
    final o = ((k % m) + r * m) * _stride;
    return Vector3(vertices[o], vertices[o + 1], vertices[o + 2]);
  }

  for (var r = 0; r < rings; r++) {
    for (var k = 0; k < m; k++) {
      final along = vertex(k + 1, r) - vertex(k + m - 1, r);
      final across =
          vertex(k, math.min(r + 1, rings - 1)) - vertex(k, math.max(r - 1, 0));
      final normal = across.cross(along)..normalize();
      if (normal.y < 0) normal.negate();
      final o = (k + r * m) * _stride;
      vertices
        ..[o + 3] = normal.x
        ..[o + 4] = normal.y
        ..[o + 5] = normal.z;
    }
  }
  final indices = <int>[
    for (var r = 0; r < rings - 1; r++)
      for (var k = 0; k < m; k++) ...<int>[
        k + r * m,
        (k + 1) % m + r * m,
        k + (r + 1) * m,
        (k + 1) % m + r * m,
        (k + 1) % m + (r + 1) * m,
        k + (r + 1) * m,
      ],
  ];
  return MeshData(
    layout: VertexLayout.standard,
    vertices: vertices,
    indices: Uint32List.fromList(indices),
  );
}
